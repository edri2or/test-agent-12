#!/usr/bin/env bash
#
# provision-openrouter-runtime-key.sh — idempotent bootstrap of the daily-capped
# OpenRouter runtime key (ADR-0004).
#
# Reads the management key from GCP Secret Manager, calls
# `POST https://openrouter.ai/api/v1/keys` with `limit=10, limit_reset=daily`,
# and stores the resulting downstream key in the `openrouter-runtime-key`
# Secret Manager container. n8n workflows use *this* key — never the management
# key — so OpenRouter enforces the cap server-side.
#
# Required env: GCP_PROJECT_ID
# Side effects: adds a new version to `openrouter-runtime-key` (no-op if a
# version already exists).
#
# Designed to run inside the bootstrap.yml job; emits ::add-mask:: so secrets
# never appear in logs.

set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID required}"

SECRET_MGMT="openrouter-management-key"
SECRET_RUNTIME="openrouter-runtime-key"
DAILY_CAP_USD="${OPENROUTER_DAILY_CAP_USD:-10}"

log() { printf '%s\n' "$*" >&2; }

# 1. Idempotency: skip if the runtime secret already has a version.
if gcloud secrets versions describe latest \
     --secret="${SECRET_RUNTIME}" \
     --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  log "✅ ${SECRET_RUNTIME} already populated — skipping (idempotent)"
  exit 0
fi

# 2. Fetch management key.
MGMT_KEY="$(gcloud secrets versions access latest \
  --secret="${SECRET_MGMT}" \
  --project="${GCP_PROJECT_ID}")"

if [[ -z "${MGMT_KEY}" ]]; then
  log "❌ ${SECRET_MGMT} is empty in Secret Manager"
  exit 1
fi

echo "::add-mask::${MGMT_KEY}"

# 3. Create downstream runtime key with daily cap.
log "→ Creating OpenRouter runtime key (limit=\$${DAILY_CAP_USD}, limit_reset=daily)…"
RESP="$(curl -fsS -X POST https://openrouter.ai/api/v1/keys \
  -H "Authorization: Bearer ${MGMT_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(printf '{"name":"runtime-agent-daily-cap","limit":%s,"limit_reset":"daily"}' "${DAILY_CAP_USD}")")"

# OpenRouter returns the actual key ONCE under `.key` (or `.data.key`).
RUNTIME_KEY="$(printf '%s' "${RESP}" | python3 -c 'import json,sys; o=json.load(sys.stdin); print(o.get("key") or o.get("data",{}).get("key",""))')"

if [[ -z "${RUNTIME_KEY}" ]]; then
  log "❌ OpenRouter response did not contain a key. Body (redacted):"
  printf '%s' "${RESP}" | python3 -c 'import json,sys; o=json.load(sys.stdin); o.pop("key",None); o.get("data",{}).pop("key",None); print(json.dumps(o))' >&2 || true
  exit 1
fi

echo "::add-mask::${RUNTIME_KEY}"

# 4. Write to Secret Manager. Create the container on first run; gcloud
# returns ALREADY_EXISTS (non-zero) on duplicates, which we swallow.
gcloud secrets create "${SECRET_RUNTIME}" \
  --project="${GCP_PROJECT_ID}" \
  --replication-policy=automatic 2>/dev/null || true

printf '%s' "${RUNTIME_KEY}" | gcloud secrets versions add "${SECRET_RUNTIME}" \
  --project="${GCP_PROJECT_ID}" \
  --data-file=-

log "✅ ${SECRET_RUNTIME} populated. Daily cap: \$${DAILY_CAP_USD} (resets midnight UTC)."
