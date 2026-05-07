"""
GitHub App Bootstrap Receiver — GCP Cloud Run service

Reduces GitHub App registration to exactly 2 browser clicks:
  1. "Create GitHub App" on GitHub (one click after auto-redirect)
  2. "Install" on the org installation page (one click)

Flow:
  GET /                → serves manifest form → auto-submits to GitHub
  GET /callback        → exchanges code → writes app secrets → shows install page
  GET /install-callback → receives installation_id → writes to Secret Manager

Zero pip dependencies. Uses only Python stdlib + GCP metadata server for auth.
Deployed temporarily during bootstrap; torn down automatically afterward.

Required environment variables (set at Cloud Run deploy time):
  GCP_PROJECT_ID   — GCP project for Secret Manager writes
  GITHUB_ORG       — GitHub organization name
  APP_NAME         — desired GitHub App name (e.g. "my-agent")
  REDIRECT_URL     — this service's own /callback URL (set after deploy)
  GITHUB_REPO      — owner/repo slug for updating APP_INSTALLATION_ID variable

Optional environment variables:
  WEBHOOK_URL      — n8n or agent webhook URL for GitHub events; omit for
                     API-only Apps (e.g. the Provisioner App) — no hook_attributes
                     or events are registered when this is unset
  SECRET_PREFIX    — prefix for Secret Manager secret names (default: "github-app-")
                     e.g. "provisioner-app-" writes provisioner-app-id, etc.
  APP_PERMISSIONS  — base64-encoded JSON dict of GitHub App permissions
                     (default: runtime App permissions — contents/pull_requests/
                     workflows/secrets/metadata)
"""

import http.server
import json
import os
import urllib.parse
import urllib.request
import base64
import sys

# ── Configuration ─────────────────────────────────────────────────────────────

GCP_PROJECT_ID  = os.environ.get("GCP_PROJECT_ID", "")
GITHUB_ORG      = os.environ.get("GITHUB_ORG", "")
APP_NAME        = os.environ.get("APP_NAME", "autonomous-agent")
REDIRECT_URL    = os.environ.get("REDIRECT_URL", "")   # set after Cloud Run URL is known
WEBHOOK_URL     = os.environ.get("WEBHOOK_URL", "")    # omit for API-only Apps (no hook registered)
GITHUB_REPO     = os.environ.get("GITHUB_REPO", "")    # owner/repo — for updating APP_INSTALLATION_ID
SECRET_PREFIX   = os.environ.get("SECRET_PREFIX", "github-app-")  # e.g. "provisioner-app-"
_raw_perms      = os.environ.get("APP_PERMISSIONS", "")
APP_PERMISSIONS: dict = (
    json.loads(base64.b64decode(_raw_perms).decode())
    if _raw_perms
    else {
        "contents":      "write",
        "pull_requests": "write",
        "workflows":     "write",
        "secrets":       "write",
        "metadata":      "read",
    }
)
PORT            = int(os.environ.get("PORT", "8080"))

# ── GCP Secret Manager helpers ────────────────────────────────────────────────

def _get_access_token() -> str:
    """Retrieve GCP access token from the metadata server (Cloud Run identity)."""
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())["access_token"]


def write_secret(name: str, value: str, token: str) -> None:
    """Create or update a GCP Secret Manager secret version."""
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    base_url = f"https://secretmanager.googleapis.com/v1/projects/{GCP_PROJECT_ID}/secrets"

    try:
        urllib.request.urlopen(
            urllib.request.Request(f"{base_url}/{name}", headers=headers),
            timeout=10,
        )
    except urllib.error.HTTPError as e:
        if e.code == 404:
            body = json.dumps({"replication": {"automatic": {}}}).encode()
            urllib.request.urlopen(
                urllib.request.Request(f"{base_url}?secretId={name}", data=body, headers=headers, method="POST"),
                timeout=10,
            )

    payload = json.dumps({
        "payload": {"data": base64.b64encode(value.encode()).decode()}
    }).encode()
    urllib.request.urlopen(
        urllib.request.Request(
            f"{base_url}/{name}:addVersion",
            data=payload,
            headers=headers,
            method="POST",
        ),
        timeout=10,
    )
    print(f"[SECRET] Written: {name}", flush=True)


def read_secret(name: str, token: str) -> str:
    req = urllib.request.Request(
        f"https://secretmanager.googleapis.com/v1/projects/{GCP_PROJECT_ID}/secrets/{name}/versions/latest:access",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
    return base64.b64decode(data["payload"]["data"]).decode()


def update_github_variable(name: str, value: str, gh_token: str) -> None:
    if not GITHUB_REPO:
        raise ValueError("GITHUB_REPO not set — cannot update GitHub variable")
    headers = {
        "Authorization": f"Bearer {gh_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
    }
    body = json.dumps({"name": name, "value": value}).encode()
    try:
        req = urllib.request.Request(
            f"https://api.github.com/repos/{GITHUB_REPO}/actions/variables/{name}",
            data=body, headers=headers, method="PATCH",
        )
        urllib.request.urlopen(req, timeout=10)
    except urllib.error.HTTPError:
        req = urllib.request.Request(
            f"https://api.github.com/repos/{GITHUB_REPO}/actions/variables",
            data=body, headers=headers, method="POST",
        )
        urllib.request.urlopen(req, timeout=10)
    print(f"[GITHUB] Variable updated: {name}", flush=True)


# ── GitHub API helper ─────────────────────────────────────────────────────────

def exchange_manifest_code(code: str) -> dict:
    """Exchange a manifest temporary code for GitHub App credentials."""
    req = urllib.request.Request(
        f"https://api.github.com/app-manifests/{code}/conversions",
        data=b"",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


# ── HTML pages ────────────────────────────────────────────────────────────────

def manifest_form_html() -> str:
    manifest: dict = {
        "name": APP_NAME,
        "url": f"https://github.com/{GITHUB_ORG}",
        "redirect_url": REDIRECT_URL or "https://placeholder/callback",
        **({"setup_url": REDIRECT_URL.replace("/callback", "/install-callback")} if REDIRECT_URL else {}),
        "default_permissions": APP_PERMISSIONS,
        "public": False,
    }
    if WEBHOOK_URL:
        manifest["hook_attributes"] = {"url": WEBHOOK_URL, "active": True}
        # NOTE: do NOT list "installation" — GitHub's manifest validator rejects it
        # ("Default events unsupported: installation").
        manifest["default_events"] = ["push", "pull_request"]
    manifest_json = json.dumps(manifest)
    github_url = f"https://github.com/organizations/{GITHUB_ORG}/settings/apps/new"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Register GitHub App — {APP_NAME}</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 480px; margin: 80px auto; padding: 0 20px; color: #24292f; }}
    h1 {{ font-size: 1.4rem; }}
    p {{ color: #57606a; }}
    .note {{ background: #ddf4ff; border: 1px solid #54aeff; border-radius: 6px; padding: 12px 16px; font-size: 0.9rem; }}
  </style>
</head>
<body>
  <h1>Registering GitHub App: <code>{APP_NAME}</code></h1>
  <p>You will be redirected to GitHub in a moment. Click <strong>"Create GitHub App"</strong> — that's the only action required.</p>
  <p class="note">All credentials will be stored automatically in GCP Secret Manager. You will never see the private key.</p>

  <form id="manifest-form" action="{github_url}" method="post">
    <input type="hidden" name="manifest" id="manifest-input">
  </form>

  <script>
    document.getElementById("manifest-input").value = {json.dumps(manifest_json)};
    // Auto-submit — human lands directly on GitHub confirmation page
    document.getElementById("manifest-form").submit();
  </script>
</body>
</html>"""


def success_html(app_name: str, app_id: str, install_url: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>GitHub App Created ✓</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 480px; margin: 80px auto; padding: 0 20px; color: #24292f; }}
    .ok {{ color: #1a7f37; font-size: 1.2rem; font-weight: 600; }}
    .step {{ background: #f6f8fa; border-radius: 6px; padding: 12px 16px; margin: 16px 0; }}
    a.btn {{ display: inline-block; background: #1f883d; color: white; padding: 10px 20px;
             border-radius: 6px; text-decoration: none; font-weight: 600; margin-top: 8px; }}
    a.btn:hover {{ background: #1a7f37; }}
  </style>
</head>
<body>
  <p class="ok">✓ GitHub App "{app_name}" created successfully</p>
  <p>App ID <code>{app_id}</code> and private key have been written to GCP Secret Manager automatically.</p>

  <div class="step">
    <strong>One more click required:</strong> Install the app on your organization.
    <br><br>
    <a class="btn" href="{install_url}">Install App on {GITHUB_ORG} →</a>
  </div>

  <p style="color:#57606a; font-size:0.85rem">
    After clicking Install, GitHub will redirect back here automatically.
    The installation ID is stored to GCP Secret Manager — no manual paste needed.
  </p>
</body>
</html>"""


def _install_html_page(title: str, body_content: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{title}</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 520px; margin: 80px auto; padding: 0 20px; color: #24292f; }}
    .ok {{ color: #1a7f37; font-size: 1.2rem; font-weight: 600; }}
    .warn {{ color: #9a6700; font-size: 1rem; font-weight: 600; }}
    .step {{ background: #f6f8fa; border-radius: 6px; padding: 12px 16px; margin: 16px 0; }}
    .err {{ background: #fff8c5; border: 1px solid #d4a72c; border-radius: 4px; padding: 8px 12px; font-size: 0.85rem; }}
  </style>
</head>
<body>
{body_content}
</body>
</html>"""


def install_success_html(installation_id: str) -> str:
    return _install_html_page("Installation Complete ✓", f"""  <p class="ok">✓ GitHub App installed successfully</p>
  <div class="step">
    <strong>Installation ID:</strong> <code>{installation_id}</code><br>
    Written to GCP Secret Manager as <code>{SECRET_PREFIX}installation-id</code> automatically.
  </div>
  <p style="color:#57606a; font-size:0.85rem">
    The bootstrap workflow will now continue automatically. You can close this tab.
  </p>""")


def install_partial_html(installation_id: str, error: str) -> str:
    return _install_html_page("Installation Complete (manual step needed)", f"""  <p class="ok">✓ GitHub App installed successfully on GitHub</p>
  <p class="warn">⚠ Secret Manager write failed — manual recovery needed</p>
  <div class="step">
    <strong>Installation ID:</strong> <code>{installation_id}</code><br>
    Run <code>write-clone-secret.yml</code> with:<br>
    <code>secret_name={SECRET_PREFIX}installation-id</code><br>
    <code>secret_value={installation_id}</code>
  </div>
  <div class="err">Error: {error}</div>
  <p style="color:#57606a; font-size:0.85rem">
    The GitHub App installation is complete. Only the automatic secret write failed.
    Once you inject the secret manually, bootstrap will continue.
  </p>""")


def error_html(message: str) -> str:
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Error</title></head>
<body style="font-family:system-ui;max-width:480px;margin:80px auto;padding:0 20px">
  <h2 style="color:#cf222e">Bootstrap error</h2>
  <pre style="background:#f6f8fa;padding:12px;border-radius:6px">{message}</pre>
  <p>Check the Cloud Run logs for details.</p>
</body></html>"""


# ── HTTP handler ──────────────────────────────────────────────────────────────

class Handler(http.server.BaseHTTPRequestHandler):

    def send_html(self, status: int, body: str) -> None:
        encoded = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path in ("/", "/start"):
            self.send_html(200, manifest_form_html())
            return

        if parsed.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
            return

        if parsed.path == "/callback":
            params = urllib.parse.parse_qs(parsed.query)
            code = (params.get("code") or [None])[0]
            if not code:
                self.send_html(400, error_html("Missing 'code' parameter in callback URL."))
                return
            self._handle_callback(code)
            return

        if parsed.path == "/install-callback":
            params = urllib.parse.parse_qs(parsed.query)
            installation_id = (params.get("installation_id") or [None])[0]
            if not installation_id:
                self.send_html(400, error_html("Missing 'installation_id' in install callback."))
                return
            self._handle_install_callback(installation_id)
            return

        self.send_response(404)
        self.end_headers()

    def _handle_callback(self, code: str) -> None:
        try:
            print(f"[CALLBACK] Exchanging manifest code...", flush=True)
            app_data = exchange_manifest_code(code)

            app_id   = str(app_data["id"])
            pem      = app_data["pem"]
            secret   = app_data.get("webhook_secret", "")
            app_name = app_data.get("name", APP_NAME)
            app_slug = app_data.get("slug", app_name.lower().replace(" ", "-"))

            print(f"[CALLBACK] App created: id={app_id} slug={app_slug}", flush=True)

            token = _get_access_token()
            write_secret(f"{SECRET_PREFIX}id", app_id, token)
            write_secret(f"{SECRET_PREFIX}private-key", pem, token)
            if secret:
                write_secret(f"{SECRET_PREFIX}webhook-secret", secret, token)

            # /apps/{slug}/installations/new is Marketplace-only and 404s for private org apps.
            install_url = f"https://github.com/organizations/{GITHUB_ORG}/settings/apps/{app_slug}/installations"
            self.send_html(200, success_html(app_name, app_id, install_url))
            print("[CALLBACK] All secrets written to Secret Manager. Bootstrap receiver job complete.", flush=True)

        except Exception as exc:
            print(f"[ERROR] {exc}", flush=True)
            self.send_html(500, error_html(str(exc)))

    def _handle_install_callback(self, installation_id: str) -> None:
        print(f"[INSTALL-CALLBACK] installation_id={installation_id}", flush=True)
        try:
            token = _get_access_token()
            write_secret(f"{SECRET_PREFIX}installation-id", installation_id, token)
            print(f"[INSTALL-CALLBACK] {SECRET_PREFIX}installation-id written to Secret Manager.", flush=True)
            # Best-effort: gh-admin-token may be absent in early clones; GSM is authoritative.
            try:
                gh_token = read_secret("gh-admin-token", token)
                update_github_variable("APP_INSTALLATION_ID", installation_id, gh_token)
            except Exception as e:
                print(f"[INSTALL-CALLBACK] GitHub variable update skipped (non-fatal): {e}", flush=True)
        except Exception as exc:
            # GitHub App installation succeeded but SM write failed.
            # Show installation_id prominently so the operator can inject it manually.
            print(f"[ERROR] Secret Manager write failed: {exc}", flush=True)
            self.send_html(200, install_partial_html(installation_id, str(exc)))
        else:
            self.send_html(200, install_success_html(installation_id))
            print("[INSTALL-CALLBACK] Installation ID stored. Bootstrap will continue.", flush=True)

    def log_message(self, fmt, *args):  # suppress default access log noise
        print(f"[HTTP] {fmt % args}", flush=True)


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if not GCP_PROJECT_ID:
        print("ERROR: GCP_PROJECT_ID environment variable is required.", file=sys.stderr)
        sys.exit(1)
    server = http.server.HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[RECEIVER] Bootstrap receiver listening on port {PORT}", flush=True)
    print(f"[RECEIVER] App: {APP_NAME}  Org: {GITHUB_ORG}", flush=True)
    server.serve_forever()
