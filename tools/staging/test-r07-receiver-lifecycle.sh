#!/usr/bin/env bash
#
# R-07 staging validation — Cloud Run receiver lifecycle (no GCP needed).
#
# Drives 3 scenarios with a mocked `gcloud` shim on PATH:
#   1. Happy path:           secrets appear after 2 polls → teardown invoked.
#   2. Timeout:               secrets never appear → teardown still invoked
#                             (mirrors `if: always()` in bootstrap.yml:628).
#   3. WEBHOOK_URL pre-flight: missing var → fail-closed BEFORE any deploy
#                             call (re-asserts the PR #8 invariant).
#
# This script tests the *contract* the bootstrap workflow's R-07 logic must
# uphold. It re-implements the same poll/teardown patterns as
# `.github/workflows/bootstrap.yml:525-636` so any drift between the test
# contract and the YAML is visible. The full E2E with a real GitHub App
# registration remains a manual checklist in
# `docs/runbooks/staging-validation.md` — the 2 browser clicks are R-07's
# irreducible HITL.

set -euo pipefail

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# ─── mock gcloud ──────────────────────────────────────────────────────────────
# Logs every invocation to $WORKDIR/gcloud.log. Behavior is controlled via
# files in $WORKDIR:
#   - $WORKDIR/secret_present_after_polls (int): number of polls before
#       `gcloud secrets versions access` starts succeeding. -1 = never.
#   - $WORKDIR/poll_count: incremented each call.

cat > "$WORKDIR/gcloud" <<'SHIM'
#!/usr/bin/env bash
set -e
LOG="${MOCK_GCLOUD_LOG:-/tmp/gcloud.log}"
STATE_DIR="${MOCK_GCLOUD_STATE:-/tmp}"
echo "$@" >> "$LOG"
case "$1 $2" in
  "run deploy")          echo "Service [github-app-bootstrap-receiver] deployed."; exit 0 ;;
  "run services")
    case "$3" in
      describe) echo "https://mock-receiver.example.run.app"; exit 0 ;;
      delete)   echo "Deleted service."; exit 0 ;;
      update)   exit 0 ;;
      *)        echo "mock-gcloud: unhandled 'run services $3'" >&2; exit 64 ;;
    esac
    ;;
  "secrets describe")    exit 1 ;;  # always "not exist" so the deploy path runs
  "secrets versions")
    case "$3" in
      access)
        COUNT_FILE="$STATE_DIR/poll_count"
        THRESHOLD_FILE="$STATE_DIR/secret_present_after_polls"
        [ -f "$COUNT_FILE" ] || echo 0 > "$COUNT_FILE"
        C=$(cat "$COUNT_FILE")
        C=$((C + 1))
        echo "$C" > "$COUNT_FILE"
        THR=$(cat "$THRESHOLD_FILE" 2>/dev/null || echo -1)
        if [ "$THR" -ge 0 ] && [ "$C" -ge "$THR" ]; then
          echo "12345"; exit 0
        fi
        exit 1
        ;;
      add) exit 0 ;;
      *)   echo "mock-gcloud: unhandled 'secrets versions $3'" >&2; exit 64 ;;
    esac
    ;;
  "artifacts repositories") exit 0 ;;
  "auth configure-docker")  exit 0 ;;
  *) echo "mock-gcloud: unhandled '$1 $2'" >&2; exit 64 ;;
esac
SHIM
chmod +x "$WORKDIR/gcloud"

export PATH="$WORKDIR:$PATH"
export MOCK_GCLOUD_LOG="$WORKDIR/gcloud.log"
export MOCK_GCLOUD_STATE="$WORKDIR"

# Sanity: PATH override took effect.
if [ "$(command -v gcloud)" != "$WORKDIR/gcloud" ]; then
  echo "FAIL: PATH override did not catch the gcloud shim." >&2
  exit 1
fi

# ─── helpers re-implementing bootstrap.yml semantics ──────────────────────────
# These mirror .github/workflows/bootstrap.yml:525-636 with sleeps shrunk so
# the test runs in <30s. If the YAML changes its semantics, update both.

GCP_PROJECT_ID=mock-project
GCP_REGION=us-central1

preflight_webhook_url() {
  if [ -z "${WEBHOOK_URL_VAR:-}" ]; then
    echo "❌ WEBHOOK_URL repo variable is not set."
    return 1
  fi
  echo "✅ WEBHOOK_URL set."
}

deploy_receiver() {
  gcloud run deploy github-app-bootstrap-receiver --image=mock --quiet
  SERVICE_URL=$(gcloud run services describe github-app-bootstrap-receiver \
    --platform=managed --region="$GCP_REGION" --project="$GCP_PROJECT_ID" \
    --format='value(status.url)')
  gcloud run services update github-app-bootstrap-receiver \
    --update-env-vars="REDIRECT_URL=${SERVICE_URL}/callback" --quiet
  export SERVICE_URL
}

poll_for_secret() {
  local max_polls=$1
  local interval=${2:-0}  # 0 = no sleep in tests
  for i in $(seq 1 "$max_polls"); do
    if gcloud secrets versions access latest \
        --secret="github-app-id" \
        --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
      echo "✅ secret found after ${i} poll(s)"
      return 0
    fi
    [ "$interval" -gt 0 ] && sleep "$interval"
  done
  echo "❌ Timed out waiting for secret"
  return 1
}

teardown_receiver() {
  gcloud run services delete github-app-bootstrap-receiver \
    --platform=managed --region="$GCP_REGION" --project="$GCP_PROJECT_ID" \
    --quiet 2>/dev/null || true
}

# ─── shared assertion helpers ─────────────────────────────────────────────────
assert_logged() {
  if ! grep -q "$1" "$MOCK_GCLOUD_LOG"; then
    echo "  FAIL: expected gcloud invocation '$1' not found in log" >&2
    return 1
  fi
}

assert_not_logged() {
  if grep -q "$1" "$MOCK_GCLOUD_LOG"; then
    echo "  FAIL: forbidden gcloud invocation '$1' found in log" >&2
    return 1
  fi
}

reset_mock() {
  : > "$MOCK_GCLOUD_LOG"
  echo 0 > "$WORKDIR/poll_count"
  echo "${1:--1}" > "$WORKDIR/secret_present_after_polls"
}

# ─── scenario 1: happy path ───────────────────────────────────────────────────
echo "[R-07] Scenario 1: happy path (secret appears after 2 polls)..."
reset_mock 2
WEBHOOK_URL_VAR="https://n8n.example.com/webhook/github"
preflight_webhook_url
deploy_receiver
poll_for_secret 5
teardown_receiver
assert_logged "run deploy github-app-bootstrap-receiver"
assert_logged "run services delete github-app-bootstrap-receiver"
echo "[R-07] Scenario 1: PASS"

# ─── scenario 2: timeout, teardown still runs ─────────────────────────────────
echo "[R-07] Scenario 2: timeout (secret never appears, teardown still runs)..."
reset_mock -1  # never present
WEBHOOK_URL_VAR="https://n8n.example.com/webhook/github"
preflight_webhook_url
deploy_receiver
TIMED_OUT=0
poll_for_secret 3 || TIMED_OUT=1
# Mirror `if: always()` semantics: teardown runs unconditionally.
teardown_receiver
if [ "$TIMED_OUT" -ne 1 ]; then
  echo "[R-07] FAIL: poll_for_secret should have timed out" >&2
  exit 1
fi
assert_logged "run deploy github-app-bootstrap-receiver"
assert_logged "run services delete github-app-bootstrap-receiver"
echo "[R-07] Scenario 2: PASS"

# ─── scenario 3: WEBHOOK_URL pre-flight ───────────────────────────────────────
echo "[R-07] Scenario 3: WEBHOOK_URL unset → pre-flight fail, no deploy..."
reset_mock -1
unset WEBHOOK_URL_VAR
PREFLIGHT_RC=0
preflight_webhook_url || PREFLIGHT_RC=$?
if [ "$PREFLIGHT_RC" -eq 0 ]; then
  echo "[R-07] FAIL: pre-flight should have rejected missing WEBHOOK_URL" >&2
  exit 1
fi
assert_not_logged "run deploy"
assert_not_logged "run services"
echo "[R-07] Scenario 3: PASS"

echo ""
echo "[R-07] All 3 scenarios PASS — Cloud Run receiver lifecycle contract holds."
echo "       (Real-GCP E2E with GitHub App registration remains manual; see"
echo "        docs/runbooks/staging-validation.md.)"
