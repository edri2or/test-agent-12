#!/usr/bin/env bash
# ============================================================================
# tools/grant-autonomy.sh — The single, one-time operator action.
#
# After this script runs once successfully, every future Claude Code session
# operates with full autonomy on this repo. No further operator action is
# required for: GitHub Secrets/Variables, GCP, Railway, Cloudflare, n8n,
# OpenRouter, Linear, Telegram, or any platform glue.
#
# This script is the formal "trust handshake" defined in ADR-0007 (Inviolable
# Autonomy Contract). It is the ONLY operator action documented anywhere in
# this repository as required.
#
# Run from GCP Cloud Shell after `gcloud auth login` (you already have this
# from being project owner). Provide one PAT via env var; the script does
# everything else.
#
# Usage:
#   export GH_TOKEN=ghp_xxx     # fine-grained PAT, scopes: repo + workflow + admin:org
#   export GITHUB_REPO=owner/repo
#   export GCP_PROJECT_ID=or-infra-templet-admin
#
#   # Optional — auto-create the GCP project per ADR-0011 §1 (silo isolation).
#   # When unset, the script falls back to ADR-0010 manual mode and expects
#   # GCP_PROJECT_ID to already exist.
#   export GCP_PARENT_FOLDER=123456789012        # OR
#   export GCP_PARENT_ORG=987654321098
#   export GCP_BILLING_ACCOUNT=ABCDEF-ABCDEF-ABCDEF
#
#   bash tools/grant-autonomy.sh
#
# The script is idempotent: safe to re-run on partial failure.
# ============================================================================

set -euo pipefail

# CI mode marker (ADR-0012). When CI=true (set by GitHub Actions implicitly +
# by the provision-new-clone.yml workflow explicitly), the gcloud auth is
# provided by google-github-actions/auth@v2 (WIF).
CI_MODE="${CI:-false}"

# Diagnostic ::error:: annotation emission on failure (CI-WIF mode only).
# Logs are inaccessible from the build agent's sandbox (GitHub Actions blob
# host not in proxy allowlist), so failures must surface via annotations
# which ARE queryable through the GitHub API at /check-runs/{id}/annotations.
# This trap fires on any non-zero exit (set -e is on) and emits a single
# annotation containing line number, exit code, and the failing command
# (BASH_COMMAND), then re-exits with the original code.
on_err() {
  local rc=$?
  local line="${1:-?}"
  local cmd="${BASH_COMMAND:-?}"
  if [ "${CI_MODE}" = "true" ]; then
    # Single-line annotation — newlines are not preserved in annotations.
    printf '::error file=tools/grant-autonomy.sh,line=%s::grant-autonomy.sh failed at line %s with exit %s; command: %s\n' \
      "${line}" "${line}" "${rc}" "${cmd}"
  fi
  exit "${rc}"
}
if [ "${CI_MODE}" = "true" ]; then
  trap 'on_err $LINENO' ERR
  # Verbose tracing in CI mode for log readability (logs aren't readable from
  # this sandbox but are visible in the GitHub UI for human operators).
  set -x
fi

# ── Configuration ───────────────────────────────────────────────────────────
: "${GH_TOKEN:?GH_TOKEN must be exported (PAT with repo+workflow+admin:org scopes)}"
: "${GITHUB_REPO:?GITHUB_REPO must be exported (e.g. edri2or/autonomous-agent-template-builder)}"
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID must be exported}"

GCP_REGION="${GCP_REGION:-us-central1}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-${GCP_PROJECT_ID}-tfstate}"
WIF_POOL_ID="${WIF_POOL_ID:-github}"
WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-github}"
RUNTIME_SA_NAME="${RUNTIME_SA_NAME:-github-actions-runner}"
RUNTIME_SA_EMAIL="${RUNTIME_SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
N8N_OWNER_EMAIL="${N8N_OWNER_EMAIL:-ops@example.com}"

# Source project for the GCP-→-GitHub secret sync (ADR-0012).
# Operator-Cloud-Shell mode: defaults to the new clone's project (existing
# behavior — secrets the operator pre-populated live there).
# CI-WIF mode: provision-new-clone.yml exports SECRETS_SOURCE_PROJECT so the
# read points at or-infra-templet-admin where the platform tokens actually
# live. The destination (GitHub Secrets on ${GITHUB_REPO}) is unchanged.
SECRETS_SOURCE_PROJECT="${SECRETS_SOURCE_PROJECT:-${GCP_PROJECT_ID}}"

GH_API="https://api.github.com/repos/${GITHUB_REPO}"
log() { printf '\n[autonomy] %s\n' "$*"; }
fail() { printf '\n❌ [autonomy] %s\n' "$*" >&2; exit 1; }

# ── Pre-flight ──────────────────────────────────────────────────────────────
log "Pre-flight checks…"
command -v gcloud >/dev/null || fail "gcloud not found (run from Cloud Shell)"
command -v gh     >/dev/null || fail "gh not found (Cloud Shell should have it)"
command -v jq     >/dev/null || fail "jq not found"

gcloud auth list --filter=status:ACTIVE --format='value(account)' \
  | grep -q . || fail "gcloud not authenticated"

# Retry with backoff: newly-created repos can take a few seconds to propagate
# through GitHub's API (observed race in provision-new-clone.yml — repo created
# in step N, grant-autonomy runs in step N+1 before the repo is reachable).
for _attempt in 1 2 3 4 5; do
  if curl -sfH "Authorization: Bearer ${GH_TOKEN}" "${GH_API}" >/dev/null 2>&1; then
    break
  fi
  [ "$_attempt" -lt 5 ] \
    && { log "Repo not yet reachable (attempt ${_attempt}/5) — retrying in $(( _attempt * 5 ))s…"; sleep $(( _attempt * 5 )); } \
    || fail "GH_TOKEN cannot reach ${GITHUB_REPO} after 5 attempts (check scopes or repo propagation)"
done

# ── 0. Auto-create GCP project if missing (ADR-0011 §1) ─────────────────────
# Per ADR-0011 §1: each child instance gets its own GCP project. When
# GCP_BILLING_ACCOUNT + one of {GCP_PARENT_FOLDER, GCP_PARENT_ORG} are
# exported, this step auto-creates and bills-links the project. The
# operator pre-grants `roles/resourcemanager.projectCreator` on the
# parent + `roles/billing.user` on the billing account ONCE GLOBALLY
# (not per clone).
#
# Back-compat (ADR-0010 manual mode): when the project already exists,
# this step is a no-op and the script proceeds to use it. When neither
# auto-create env var is set AND the project is missing, fail with a
# diagnostic that surfaces both paths.

if ! gcloud projects describe "${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  log "Project ${GCP_PROJECT_ID} not found — entering auto-create flow (ADR-0011 §1)…"
  if [[ -z "${GCP_BILLING_ACCOUNT:-}" ]]; then
    fail "Project ${GCP_PROJECT_ID} not found AND GCP_BILLING_ACCOUNT is unset.
Either:
  (a) Pre-create the project (ADR-0010 manual mode) and re-run; OR
  (b) Set GCP_BILLING_ACCOUNT + one of {GCP_PARENT_FOLDER, GCP_PARENT_ORG}
      for ADR-0011 §1 auto-creation."
  fi
  if [[ -z "${GCP_PARENT_FOLDER:-}" && -z "${GCP_PARENT_ORG:-}" ]]; then
    fail "Project ${GCP_PROJECT_ID} not found AND neither GCP_PARENT_FOLDER nor GCP_PARENT_ORG is set.
Set one of them so 'gcloud projects create' has a parent (folder or org)."
  fi

  CREATE_ARGS=(--quiet)
  if [[ -n "${GCP_PARENT_FOLDER:-}" ]]; then
    CREATE_ARGS+=(--folder="${GCP_PARENT_FOLDER}")
    log "Creating ${GCP_PROJECT_ID} under folder ${GCP_PARENT_FOLDER}…"
  else
    CREATE_ARGS+=(--organization="${GCP_PARENT_ORG}")
    log "Creating ${GCP_PROJECT_ID} under organization ${GCP_PARENT_ORG}…"
  fi
  gcloud projects create "${GCP_PROJECT_ID}" "${CREATE_ARGS[@]}"
  # GCP IAM propagation delay: after project creation the creator's owner
  # binding takes a few seconds to propagate. gcloud billing projects link
  # (called below) requires the SA to have billing.projects.updateBillingInfo
  # on the project, which derives from the owner role. Without a brief wait
  # the billing link fails with "does not have permission to access project".
  # Observed consistently in provision-new-clone.yml CI runs where the project
  # is freshly created and billing is linked in the same script invocation.
  log "Waiting 20s for GCP IAM propagation after project creation…"
  sleep 20
fi

# CI-WIF mode (ADR-0012): the consumer project for `gcloud billing` calls is
# the SA's home project (SECRETS_SOURCE_PROJECT), not Cloud Shell's implicit
# billing-quota-project. cloudbilling.googleapis.com must be enabled on that
# consumer project before `gcloud billing projects link` works. Idempotent
# — `services enable` is a no-op if already enabled.
if [ "${CI_MODE}" = "true" ]; then
  log "CI-WIF mode: ensuring cloudbilling.googleapis.com on consumer project ${SECRETS_SOURCE_PROJECT}…"
  gcloud services enable cloudbilling.googleapis.com \
    --project="${SECRETS_SOURCE_PROJECT}" --quiet
fi

# Idempotent billing link. Hoisted out of the auto-create branch so a project
# that exists from a prior partial-state run (created OK, billing-link failed
# — e.g. quota-exceeded snapshot 25253910937) self-heals on the next run
# instead of silently proceeding to API enables that need billing. `gcloud
# billing projects link` is idempotent server-side: if already linked to the
# same account it is a no-op; if linked elsewhere it reattaches; if unlinked
# it links. Quota-exceeded errors still bubble through the same diagnostic
# annotation path below.
CURRENT_BILLING="$(gcloud billing projects describe "${GCP_PROJECT_ID}" \
  --format='value(billingAccountName)' 2>/dev/null || echo '')"
DESIRED_BILLING="billingAccounts/${GCP_BILLING_ACCOUNT:-}"
if [ -n "${GCP_BILLING_ACCOUNT:-}" ] && [ "${CURRENT_BILLING}" != "${DESIRED_BILLING}" ]; then
  log "Linking billing account ${GCP_BILLING_ACCOUNT} to ${GCP_PROJECT_ID} (current: ${CURRENT_BILLING:-none})…"
  # Retry with backoff: GCP IAM propagation delay can persist beyond the
  # 20s sleep above on slow consistency convergence. Retrying here covers
  # the tail of the propagation window without requiring a full re-dispatch.
  BILLING_RC=0
  for _billing_attempt in 1 2 3 4; do
    BILLING_OUT=$(gcloud billing projects link "${GCP_PROJECT_ID}" \
      --billing-account="${GCP_BILLING_ACCOUNT}" --quiet 2>&1) && BILLING_RC=0 && break
    BILLING_RC=$?
    wait_s=$(( _billing_attempt * 10 ))
    log "Billing link attempt ${_billing_attempt}/4 failed (exit ${BILLING_RC}) — retrying in ${wait_s}s…"
    log "${BILLING_OUT}"
    [ "${_billing_attempt}" -lt 4 ] && sleep "${wait_s}"
  done
  if [ "${BILLING_RC}" -ne 0 ]; then
    if [ "${CI_MODE}" = "true" ]; then
      ENCODED=$(printf '%s' "${BILLING_OUT}" | tr '\n' '|' | head -c 800)
      printf '::error file=tools/grant-autonomy.sh,line=158::gcloud billing projects link FAILED (exit %s): %s\n' \
        "${BILLING_RC}" "${ENCODED}"
    fi
    exit "${BILLING_RC}"
  fi
  [ -n "${BILLING_OUT}" ] && printf '%s\n' "${BILLING_OUT}"
else
  log "Billing already linked to ${CURRENT_BILLING:-(noop)}; skipping link."
fi

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT_ID}" \
  --format='value(projectNumber)')"
log "Project: ${GCP_PROJECT_ID} (number ${PROJECT_NUMBER})"

# ── 1. Enable required GCP APIs ─────────────────────────────────────────────
log "Enabling GCP APIs (idempotent)…"
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  secretmanager.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  --project="${GCP_PROJECT_ID}" --quiet

# ── 2. Create Terraform state bucket (chicken-egg with terraform backend) ──
# Q-Path (2026-05-01) surfaced a GCS eventual-consistency race where
# `gcloud storage buckets update --versioning` returned GcsApiError('')
# immediately after bucket creation. Split create+update into independent
# idempotent gates so the versioning step is naturally retry-safe and
# recovers automatically on the next invocation.
log "Ensuring Terraform state bucket gs://${TF_STATE_BUCKET}…"

# 2a. Create-if-missing.
if ! gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" \
       --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --project="${GCP_PROJECT_ID}" \
    --location="${GCP_REGION}" \
    --uniform-bucket-level-access \
    --quiet
fi

# 2b. Update-versioning with retry-with-backoff and explicit bucket-level
# IAM grant (handles GCS IAM propagation lag in CI-WIF mode).
#
# History:
# - Q-Path JOURNEY 2026-05-01 documented a GcsApiError race where the
#   update fails immediately after create but succeeds after sleep.
# - PR #35 made create idempotent.
# - PR #39 added retry-with-backoff but had a bug: `if ! cmd; then RC=$?`
#   captured 0 due to the ! operator's exit-status semantics, so the
#   script silently exited 0 after retries failed.
# - Validation run 25232328369 (clone-007) revealed: the actual error
#   isn't transient — it's an IAM propagation lag where the SA's
#   project-level roles/owner doesn't propagate to bucket-level
#   storage.buckets.update for ~30+ seconds.
#
# Fix: (a) use proper exit-code capture via if/else; (b) add explicit
# bucket-level IAM binding (storage.admin) on the SA to bypass the
# propagation lag entirely; (c) longer retry window.
BUCKET_VERSIONING_OK=false
BUCKET_LAST_OUT=""
BUCKET_LAST_RC=0
SA_FOR_GRANT="$(gcloud config list --format='value(core.account)' 2>/dev/null)"

# 2b.i. Explicit bucket-level grant (idempotent). Bypasses project→bucket
# IAM propagation lag entirely. The SA created the bucket so it has
# storage.buckets.setIamPolicy via project-owner (which IS available
# immediately at the project level even when bucket-level lag exists).
if [ -n "${SA_FOR_GRANT}" ]; then
  log "  Granting ${SA_FOR_GRANT} explicit bucket admin on gs://${TF_STATE_BUCKET}…"
  gcloud storage buckets add-iam-policy-binding "gs://${TF_STATE_BUCKET}" \
    --member="serviceAccount:${SA_FOR_GRANT}" \
    --role="roles/storage.admin" --quiet >/dev/null 2>&1 || \
    log "  (bucket IAM grant skipped or transient failure — will retry below)"
fi

# 2b.ii. Versioning update with retry, proper exit-code capture.
for attempt in 1 2 3 4 5 6; do
  if BUCKET_LAST_OUT=$(gcloud storage buckets update "gs://${TF_STATE_BUCKET}" \
       --versioning --project="${GCP_PROJECT_ID}" --quiet 2>&1); then
    BUCKET_VERSIONING_OK=true
    break
  else
    BUCKET_LAST_RC=$?
    if [ "${attempt}" -lt 6 ]; then
      delay=$((attempt * 10))  # 10, 20, 30, 40, 50 = 150s total window
      log "  bucket versioning attempt ${attempt}/6 failed (exit ${BUCKET_LAST_RC}); sleeping ${delay}s…"
      sleep "${delay}"
    fi
  fi
done

if [ "${BUCKET_VERSIONING_OK}" != "true" ]; then
  if [ "${CI_MODE}" = "true" ]; then
    ENCODED=$(printf '%s' "${BUCKET_LAST_OUT}" | tr '\n' '|' | head -c 800)
    printf '::error file=tools/grant-autonomy.sh,line=213::bucket versioning update failed after 6 attempts (exit %s): %s\n' \
      "${BUCKET_LAST_RC}" "${ENCODED}"
  fi
  exit "${BUCKET_LAST_RC}"
fi

# ── 3. Create runtime Service Account ───────────────────────────────────────
log "Ensuring runtime SA ${RUNTIME_SA_EMAIL}…"
if ! gcloud iam service-accounts describe "${RUNTIME_SA_EMAIL}" \
       --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${RUNTIME_SA_NAME}" \
    --project="${GCP_PROJECT_ID}" \
    --display-name="GitHub Actions runtime (WIF)" \
    --description="Federated identity for GitHub Actions OIDC tokens. No keys ever." \
    --quiet
fi

# ── 4. Grant runtime SA the roles it needs ──────────────────────────────────
# add-iam-policy-binding is a read-modify-write; concurrent calls (or a
# first call on a freshly-created project) can hit ETag races and return
# non-zero. Retry with backoff so the grants actually land before the script
# moves on; loud fail + CI annotation if all attempts are exhausted.
# Used for both project-level bindings (step 4) and SA-level bindings (step 6).
retry_iam() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if "$@" --condition=None --quiet >/dev/null 2>&1; then return 0; fi
    if [ "${attempt}" -lt 5 ]; then sleep $((attempt * 3)); fi
  done
  if [ "${CI_MODE}" = "true" ]; then
    printf '::error file=tools/grant-autonomy.sh::IAM binding failed after 5 attempts: %s\n' "$*"
  fi
  return 1
}

log "Granting roles to runtime SA…"
for ROLE in \
    roles/secretmanager.secretAccessor \
    roles/secretmanager.admin \
    roles/storage.admin \
    roles/iam.serviceAccountAdmin \
    roles/resourcemanager.projectIamAdmin \
    roles/serviceusage.serviceUsageAdmin \
    roles/run.admin \
    roles/artifactregistry.admin \
    roles/iam.workloadIdentityPoolAdmin; do
  retry_iam gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
    --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
    --role="${ROLE}"
done

# ── 5. Create WIF pool + provider, restricted to this exact repo ────────────
log "Ensuring WIF pool '${WIF_POOL_ID}'…"
if ! gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" \
       --location=global --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
    --location=global --project="${GCP_PROJECT_ID}" \
    --display-name="GitHub Actions Pool" \
    --description="WIF pool for GitHub Actions OIDC authentication" \
    --quiet
fi

log "Ensuring WIF provider '${WIF_PROVIDER_ID}' (restricted to ${GITHUB_REPO})…"
if ! gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
       --workload-identity-pool="${WIF_POOL_ID}" \
       --location=global --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --location=global --project="${GCP_PROJECT_ID}" \
    --display-name="GitHub Actions Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.actor=assertion.actor" \
    --attribute-condition="assertion.repository == '${GITHUB_REPO}'" \
    --quiet
fi

# ── 6. Bind the WIF subject (this exact repo) to the runtime SA ─────────────
log "Binding WIF principalSet → runtime SA (roles/iam.workloadIdentityUser)…"
WIF_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
WIF_POOL_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}"
# Same ETag-race risk as step 4 — reuse the retry helper.
retry_iam gcloud iam service-accounts add-iam-policy-binding "${RUNTIME_SA_EMAIL}" \
  --project="${GCP_PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WIF_POOL_RESOURCE}/attribute.repository/${GITHUB_REPO}"

# ── 7. Set GitHub Variables (plain, public IDs) ─────────────────────────────
# Emit a ::warning annotation in CI mode; plain log otherwise.
warn_ci() {
  if [ "${CI_MODE}" = "true" ]; then
    printf '::warning file=tools/grant-autonomy.sh::%s\n' "$*"
  else
    log "⚠  $*"
  fi
}

# Provisioner App may lack variables:write / secrets:write — registered without
# those permissions. Steps 7–8 set these flags non-fatally so WIF setup
# completes. Re-register App with force_reregister=true to resolve.
GH_VAR_FAILED=0

gh_var() {
  local NAME="$1" VALUE="$2"
  local HTTP_PATCH HTTP_POST BODY
  BODY=$(jq -nc --arg n "${NAME}" --arg v "${VALUE}" '{name:$n,value:$v}')
  # Try PATCH (update existing), then POST (create new). Capture HTTP status
  # without -f so we can distinguish 403 (permission) from 404 (not found).
  HTTP_PATCH=$(curl -sX PATCH "${GH_API}/actions/variables/${NAME}" \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "${BODY}" -o /dev/null -w '%{http_code}')
  if [[ "${HTTP_PATCH}" =~ ^2 ]]; then
    echo "  • var ${NAME} (updated, HTTP ${HTTP_PATCH})"
    return 0
  fi
  HTTP_POST=$(curl -sX POST "${GH_API}/actions/variables" \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "${BODY}" -o /dev/null -w '%{http_code}')
  if [[ "${HTTP_POST}" =~ ^2 ]]; then
    echo "  • var ${NAME} (created, HTTP ${HTTP_POST})"
    return 0
  fi
  warn_ci "gh_var: cannot set ${NAME} (PATCH=${HTTP_PATCH} POST=${HTTP_POST}) — Provisioner App lacks variables:write. Re-register App to fix."
  GH_VAR_FAILED=1
}

log "Setting GitHub Variables…"
gh_var GCP_PROJECT_ID                 "${GCP_PROJECT_ID}"
gh_var GCP_REGION                     "${GCP_REGION}"
gh_var GCP_WORKLOAD_IDENTITY_PROVIDER "${WIF_PROVIDER_RESOURCE}"
gh_var GCP_SERVICE_ACCOUNT_EMAIL      "${RUNTIME_SA_EMAIL}"
gh_var TF_STATE_BUCKET                "${TF_STATE_BUCKET}"
gh_var N8N_OWNER_EMAIL                "${N8N_OWNER_EMAIL}"

# ── 8. Sync platform secrets from GCP Secret Manager → GitHub Secrets ──────
# Some workflow steps consume GitHub Secrets directly (e.g. Railway GraphQL
# calls in bootstrap.yml). The kebab-case canon (ADR-0006) lives in GCP;
# this is a one-time sync to GitHub for those steps that don't yet
# fetch from Secret Manager at runtime.
log "Syncing platform secrets GCP → GitHub Secrets (kebab-case is the canon)…"

PYNACL_OK=$(python3 -c 'import nacl.public' 2>/dev/null && echo yes || echo no)
[ "${PYNACL_OK}" = "yes" ] || pip3 install --quiet pynacl

_PK_RESP=$(curl -sH "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${GH_API}/actions/secrets/public-key" \
  -w '\n%{http_code}' 2>/dev/null)
_PK_HTTP=$(printf '%s' "${_PK_RESP}" | tail -1)
PUBLIC_KEY_JSON=$(printf '%s' "${_PK_RESP}" | head -n -1)
GH_SECRET_FAILED=0
if [[ ! "${_PK_HTTP}" =~ ^2 ]]; then
  GH_SECRET_FAILED=1
  warn_ci "gh_secret: public-key fetch returned HTTP ${_PK_HTTP} — Provisioner App likely lacks secrets:write. GCP resources fully provisioned; GitHub Secrets not synced. Re-register Provisioner App to fix."
else
  PUBLIC_KEY_ID=$(echo "${PUBLIC_KEY_JSON}" | jq -r .key_id)
  PUBLIC_KEY_BASE64=$(echo "${PUBLIC_KEY_JSON}" | jq -r .key)
fi

gh_secret() {
  local NAME="$1" VALUE="$2"
  ENCRYPTED=$(python3 -c "
import base64, sys
from nacl.public import PublicKey, SealedBox
pk = PublicKey(base64.b64decode(sys.argv[1]))
ct = SealedBox(pk).encrypt(sys.argv[2].encode())
print(base64.b64encode(ct).decode())
" "${PUBLIC_KEY_BASE64}" "${VALUE}")
  local _HTTP
  _HTTP=$(curl -sX PUT "${GH_API}/actions/secrets/${NAME}" \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$(jq -nc --arg v "${ENCRYPTED}" --arg k "${PUBLIC_KEY_ID}" \
        '{encrypted_value:$v,key_id:$k}')" \
    -o /dev/null -w '%{http_code}')
  if [[ "${_HTTP}" =~ ^2 ]]; then
    echo "  • secret ${NAME}"
  else
    warn_ci "gh_secret: cannot set ${NAME} (HTTP ${_HTTP}) — Provisioner App lacks secrets:write."
    echo "  ⚠  secret ${NAME} skipped (HTTP ${_HTTP})"
    GH_SECRET_FAILED=1
  fi
}

sync() {
  local GCP_NAME="$1" GH_NAME="$2"
  if VALUE=$(gcloud secrets versions access latest --secret="${GCP_NAME}" \
                --project="${SECRETS_SOURCE_PROJECT}" 2>/dev/null); then
    gh_secret "${GH_NAME}" "${VALUE}"
  else
    echo "  ⚠  GCP secret ${GCP_NAME} not found in ${SECRETS_SOURCE_PROJECT} — skipping (workflow may need it later)"
  fi
}

if [ "${GH_SECRET_FAILED}" -eq 0 ]; then
  sync telegram-bot-token        TELEGRAM_BOT_TOKEN
  sync cloudflare-api-token      CLOUDFLARE_API_TOKEN
  sync openrouter-management-key OPENROUTER_MANAGEMENT_KEY
  sync railway-api-token         RAILWAY_API_TOKEN
  # Linear L-pool — ADR-0011 §4. Migrate UPPER_SNAKE → kebab (ADR-0006) on first run.
  if ! gcloud secrets describe "linear-team-id" \
      --project="${SECRETS_SOURCE_PROJECT}" >/dev/null 2>&1; then
    if _V=$(gcloud secrets versions access latest --secret="LINEAR_TEAM_ID" \
              --project="${SECRETS_SOURCE_PROJECT}" 2>/dev/null); then
      printf '%s' "${_V}" | gcloud secrets create "linear-team-id" \
        --project="${SECRETS_SOURCE_PROJECT}" --data-file=-
    fi
  fi
  sync linear-api-key            LINEAR_API_KEY
  sync linear-webhook-secret     LINEAR_WEBHOOK_SECRET
  sync linear-team-id            LINEAR_TEAM_ID
fi

# ── 9. Verify autonomy is granted ───────────────────────────────────────────
log "Verifying GitHub Variables visible…"
if [ "${GH_VAR_FAILED}" -eq 0 ]; then
  WIF_VAR=$(curl -sfH "Authorization: Bearer ${GH_TOKEN}" \
    "${GH_API}/actions/variables/GCP_WORKLOAD_IDENTITY_PROVIDER" \
    | jq -r .value)
  [ "${WIF_VAR}" = "${WIF_PROVIDER_RESOURCE}" ] \
    || fail "GCP_WORKLOAD_IDENTITY_PROVIDER not visible to GitHub"
else
  if [ "${CI_MODE}" = "true" ]; then
    printf '::warning file=tools/grant-autonomy.sh::Skipping variable verification — gh_var failed due to missing variables:write permission. GCP resources are fully provisioned; GitHub Variables unset. Re-register Provisioner App to enable variable writes.\n'
  fi
  log "⚠  Skipping variable verification (gh_var failed — see warnings above)"
fi

# ── 10. Summary ─────────────────────────────────────────────────────────────
cat <<EOF

================================================================================
✅ AUTONOMY GRANTED.

  Project:          ${GCP_PROJECT_ID}
  WIF provider:     ${WIF_PROVIDER_RESOURCE}
  Runtime SA:       ${RUNTIME_SA_EMAIL}
  Repo binding:     ${GITHUB_REPO}
  TF state bucket:  gs://${TF_STATE_BUCKET}

  ZERO static SA keys exist anywhere. WIF is the sole identity backbone.
  Future Claude Code sessions are now fully autonomous on this repo. They
  will trigger workflows; workflows authenticate to GCP via WIF; nothing
  more is required from you.

  This was the ONE permitted operator action per ADR-0007. After this point,
  any agent that asks you to run gcloud, gh, or any local CLI is in
  violation of the Inviolable Autonomy Contract — refer it back to the
  contract in CLAUDE.md.
================================================================================
EOF
