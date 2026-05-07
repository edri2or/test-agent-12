#!/usr/bin/env bash
# tools/one-shot.sh — Configure GitHub and trigger bootstrap with a single command.
#
# After this script finishes, your only remaining actions are 2 browser clicks
# visible in the GitHub Actions summary:
#   1. Click the link in the "github-app-registration" job summary
#   2. Click  ► Create GitHub App
#   3. Click  ► Install
#
# ─────────────────────────────────────────────────────────────────────────────
# REQUIRED env vars — export these before running:
#
#   GITHUB_TOKEN              GitHub Personal Access Token
#                             Scopes: repo, workflow
#                             (stored as GH_ADMIN_TOKEN secret for post-terraform var updates)
#   GCP_PROJECT_ID            GCP project ID
#   RAILWAY_API_TOKEN         Railway account-level token (not project token)
#   CLOUDFLARE_API_TOKEN      Cloudflare API token
#   CLOUDFLARE_ACCOUNT_ID     Cloudflare account ID
#   TELEGRAM_BOT_TOKEN        Token from @BotFather  (/newbot)
#   OPENROUTER_MANAGEMENT_KEY OpenRouter management key
#
# FIRST BOOTSTRAP — if WIF doesn't exist yet, also export:
#   GOOGLE_CREDENTIALS        GCP service account key JSON (raw JSON or base64)
#                             Get once from: GCP Console → IAM → Service Accounts → Keys
#                             This secret is AUTOMATICALLY DELETED from GitHub after
#                             terraform creates WIF (bootstrap.yml cleanup step).
#
# ─────────────────────────────────────────────────────────────────────────────
# OPTIONAL env vars (defaults shown):
#
#   GITHUB_REPO                     auto-detected from git remote (owner/repo)
#   GITHUB_ORG                      auto-detected from GITHUB_REPO
#   APP_NAME                        my-agent
#   GCP_REGION                      us-central1
#   TF_STATE_BUCKET                 {GCP_PROJECT_ID}-tfstate
#   GCP_WORKLOAD_IDENTITY_PROVIDER  (empty — auto-set by bootstrap after terraform)
#   GCP_SERVICE_ACCOUNT_EMAIL       (empty — auto-set by bootstrap after terraform)
#   CLOUDFLARE_ZONE_ID              (empty)
#   TELEGRAM_CHAT_ID                (empty)
#   RAILWAY_PROJECT_ID              (empty)
#   RAILWAY_ENVIRONMENT_ID          (empty)
#   RAILWAY_N8N_SERVICE_ID          (empty)
#   RAILWAY_AGENT_SERVICE_ID        (empty)
#   N8N_OWNER_EMAIL                 ops@example.com
#   WEBHOOK_URL                     (empty — set after n8n deploy, re-run script)
#
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   export GITHUB_TOKEN=ghp_...
#   export GCP_PROJECT_ID=my-project-123
#   export RAILWAY_API_TOKEN=...
#   export CLOUDFLARE_API_TOKEN=...
#   export CLOUDFLARE_ACCOUNT_ID=...
#   export TELEGRAM_BOT_TOKEN=...
#   export OPENROUTER_MANAGEMENT_KEY=...
#   export GOOGLE_CREDENTIALS='{"type":"service_account",...}'   # first run only
#   ./tools/one-shot.sh

set -euo pipefail

# ── Detect repo ───────────────────────────────────────────────────────────────
if [[ -z "${GITHUB_REPO:-}" ]]; then
  GITHUB_REPO="$(git remote get-url origin 2>/dev/null \
    | sed 's|.*github\.com[:/]\(.*\)\.git$|\1|; s|.*github\.com[:/]\(.*\)$|\1|' || echo '')"
fi
[[ -n "${GITHUB_REPO}" ]] \
  || { echo "ERROR: Cannot detect GitHub repo. Set GITHUB_REPO=owner/repo" >&2; exit 1; }

export GITHUB_REPO
export GITHUB_ORG="${GITHUB_ORG:-${GITHUB_REPO%%/*}}"
export APP_NAME="${APP_NAME:-my-agent}"
export GCP_REGION="${GCP_REGION:-us-central1}"
export TF_STATE_BUCKET="${TF_STATE_BUCKET:-${GCP_PROJECT_ID:-}-tfstate}"
export N8N_OWNER_EMAIL="${N8N_OWNER_EMAIL:-ops@example.com}"

# ── Required var check ────────────────────────────────────────────────────────
MISSING=()
for var in GITHUB_TOKEN GCP_PROJECT_ID RAILWAY_API_TOKEN \
           CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID \
           TELEGRAM_BOT_TOKEN OPENROUTER_MANAGEMENT_KEY; do
  [[ -n "${!var:-}" ]] || MISSING+=("$var")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "ERROR: Missing required env vars:" >&2
  printf '  %s\n' "${MISSING[@]}" >&2
  exit 1
fi

if [[ -z "${GCP_WORKLOAD_IDENTITY_PROVIDER:-}" && -z "${GOOGLE_CREDENTIALS:-}" ]]; then
  echo ""
  echo "WARNING: Neither GCP_WORKLOAD_IDENTITY_PROVIDER nor GOOGLE_CREDENTIALS is set."
  echo "         The bootstrap workflow cannot authenticate to GCP."
  echo ""
  echo "  First bootstrap: export GOOGLE_CREDENTIALS='{\"type\":\"service_account\",...}'"
  echo "  After WIF exists: export GCP_WORKLOAD_IDENTITY_PROVIDER=projects/.../providers/..."
  echo ""
  read -r -p "Continue anyway? (y/N): " confirm
  [[ "${confirm}" =~ ^[yY]$ ]] || exit 1
fi

# ── Install PyNaCl (GitHub secrets need libsodium sealed box encryption) ──────
if ! python3 -c "from nacl.public import SealedBox" 2>/dev/null; then
  echo "Installing PyNaCl..."
  pip3 install PyNaCl --quiet
fi

echo ""
echo "━━━ Bootstrap: ${GITHUB_REPO} ━━━"

# ── All work done in Python (reads from os.environ — no shell interpolation) ──
python3 <<'PYEOF'
import os, sys, base64, json, urllib.request, urllib.error, time
from nacl.public import PublicKey, SealedBox

REPO  = os.environ['GITHUB_REPO']
TOKEN = os.environ['GITHUB_TOKEN']


def gh(method, path, body=None):
    """GitHub API call. Returns parsed JSON or {}. Raises urllib.error.HTTPError."""
    url = f"https://api.github.com{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={
            'Authorization': f'Bearer {TOKEN}',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'Content-Type': 'application/json',
        }
    )
    try:
        with urllib.request.urlopen(req) as r:
            response_body = r.read()
            return json.loads(response_body) if response_body.strip() else {}
    except urllib.error.HTTPError:
        raise


def encrypt_secret(pub_key_b64, value):
    pk = PublicKey(base64.b64decode(pub_key_b64))
    return base64.b64encode(SealedBox(pk).encrypt(value.encode())).decode()


# Fetch once — all secret encryptions share the same repo public key
try:
    pk_data = gh('GET', f'/repos/{REPO}/actions/secrets/public-key')
except urllib.error.HTTPError as e:
    sys.exit(f"ERROR: Cannot reach GitHub API ({e.code}). Check GITHUB_TOKEN and repo name.")


def set_secret(name, value):
    if not value:
        print(f"  ⏭  {name} (empty — skipped)")
        return
    encrypted = encrypt_secret(pk_data['key'], value)
    try:
        gh('PUT', f'/repos/{REPO}/actions/secrets/{name}',
           {'encrypted_value': encrypted, 'key_id': pk_data['key_id']})
        print(f"  ✅ secret: {name}")
    except urllib.error.HTTPError as e:
        sys.exit(f"  ERROR setting secret {name}: HTTP {e.code} — {e.read().decode()}")


def set_variable(name, value):
    if not value:
        print(f"  ⏭  {name} (empty — skipped)")
        return
    try:
        gh('PATCH', f'/repos/{REPO}/actions/variables/{name}',
           {'name': name, 'value': value})
    except urllib.error.HTTPError as e:
        if e.code == 404:
            try:
                gh('POST', f'/repos/{REPO}/actions/variables',
                   {'name': name, 'value': value})
            except urllib.error.HTTPError as e2:
                sys.exit(f"  ERROR setting variable {name}: HTTP {e2.code} — {e2.read().decode()}")
        else:
            sys.exit(f"  ERROR setting variable {name}: HTTP {e.code} — {e.read().decode()}")
    print(f"  ✅ var:    {name}")


def create_environment(name):
    try:
        gh('PUT', f'/repos/{REPO}/environments/{name}', {})
        print(f"  ✅ env:    {name}")
    except urllib.error.HTTPError as e:
        print(f"  ⚠  env {name}: HTTP {e.code} (non-fatal — add manually if needed)", file=sys.stderr)


# ─────────────────────────────────────────────────────────────────────────────
# 1. GitHub Secrets
# ─────────────────────────────────────────────────────────────────────────────
print("\n[1/4] Setting GitHub Secrets...")
set_secret('RAILWAY_API_TOKEN',         os.environ.get('RAILWAY_API_TOKEN', ''))
set_secret('CLOUDFLARE_API_TOKEN',      os.environ.get('CLOUDFLARE_API_TOKEN', ''))
set_secret('OPENROUTER_MANAGEMENT_KEY', os.environ.get('OPENROUTER_MANAGEMENT_KEY', ''))
set_secret('TELEGRAM_BOT_TOKEN',        os.environ.get('TELEGRAM_BOT_TOKEN', ''))
set_secret('GOOGLE_CREDENTIALS',        os.environ.get('GOOGLE_CREDENTIALS', ''))
# Store the PAT as GH_ADMIN_TOKEN so bootstrap-dispatch.yml can auto-update GitHub
# variables after terraform creates WIF (and then delete GOOGLE_CREDENTIALS).
set_secret('GH_ADMIN_TOKEN',            os.environ.get('GITHUB_TOKEN', ''))

# ─────────────────────────────────────────────────────────────────────────────
# 2. GitHub Variables
# ─────────────────────────────────────────────────────────────────────────────
print("\n[2/4] Setting GitHub Variables...")
set_variable('GCP_PROJECT_ID',                 os.environ.get('GCP_PROJECT_ID', ''))
set_variable('GCP_REGION',                     os.environ.get('GCP_REGION', 'us-central1'))
set_variable('TF_STATE_BUCKET',                os.environ.get('TF_STATE_BUCKET', ''))
# These two are empty on first run; bootstrap.yml will auto-populate them.
set_variable('GCP_WORKLOAD_IDENTITY_PROVIDER', os.environ.get('GCP_WORKLOAD_IDENTITY_PROVIDER', ''))
set_variable('GCP_SERVICE_ACCOUNT_EMAIL',      os.environ.get('GCP_SERVICE_ACCOUNT_EMAIL', ''))
set_variable('CLOUDFLARE_ACCOUNT_ID',          os.environ.get('CLOUDFLARE_ACCOUNT_ID', ''))
set_variable('CLOUDFLARE_ZONE_ID',             os.environ.get('CLOUDFLARE_ZONE_ID', ''))
set_variable('TELEGRAM_CHAT_ID',               os.environ.get('TELEGRAM_CHAT_ID', ''))
set_variable('RAILWAY_PROJECT_ID',             os.environ.get('RAILWAY_PROJECT_ID', ''))
set_variable('RAILWAY_ENVIRONMENT_ID',         os.environ.get('RAILWAY_ENVIRONMENT_ID', ''))
set_variable('RAILWAY_N8N_SERVICE_ID',         os.environ.get('RAILWAY_N8N_SERVICE_ID', ''))
set_variable('RAILWAY_AGENT_SERVICE_ID',       os.environ.get('RAILWAY_AGENT_SERVICE_ID', ''))
set_variable('N8N_OWNER_EMAIL',                os.environ.get('N8N_OWNER_EMAIL', 'ops@example.com'))
set_variable('GITHUB_ORG',                     os.environ.get('GITHUB_ORG', ''))
set_variable('APP_NAME',                       os.environ.get('APP_NAME', 'my-agent'))
set_variable('WEBHOOK_URL',                    os.environ.get('WEBHOOK_URL', ''))

# ─────────────────────────────────────────────────────────────────────────────
# 3. GitHub environment (no reviewers = no blocking gate)
# ─────────────────────────────────────────────────────────────────────────────
print("\n[3/4] Creating GitHub environment...")
create_environment('bootstrap')

# ─────────────────────────────────────────────────────────────────────────────
# 4. Trigger bootstrap workflow
# ─────────────────────────────────────────────────────────────────────────────
print("\n[4/4] Triggering bootstrap workflow...")
try:
    gh('POST', f'/repos/{REPO}/actions/workflows/bootstrap-dispatch.yml/dispatches',
       {'ref': 'main', 'inputs': {
           'dry_run':        'false',
           'skip_terraform': 'false',
           'skip_railway':   'false',
       }})
except urllib.error.HTTPError as e:
    sys.exit(f"ERROR: Could not trigger workflow: HTTP {e.code} — {e.read().decode()}")

print()
print("━" * 64)
print(f"  Triggered: https://github.com/{REPO}/actions/workflows/bootstrap-dispatch.yml")
print()
print("  YOUR ONLY REMAINING STEPS:")
print("  1. Open the Actions run (link above) → wait for 'github-app-registration' job")
print("  2. Open the URL printed in the job summary")
print("  3. Click  ► Create GitHub App    (click 1)")
print("  4. Click  ► Install              (click 2)")
print()
print("  All credentials write to GCP Secret Manager automatically.")
print("  GOOGLE_CREDENTIALS is deleted from GitHub once WIF is operational.")
print("━" * 64)
PYEOF
