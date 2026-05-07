#!/usr/bin/env bash
# DEPRECATED — For desktop/local environments only.
#
# If you are using Claude Code on the web (no local CLI), use the GitHub
# Actions bootstrap workflow instead:
#
#   .github/workflows/bootstrap.yml
#   → Actions → Bootstrap → Run workflow
#
# See docs/runbooks/bootstrap.md for the web-native setup guide.
#
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap.sh — Automated bootstrap with minimal HITL gates (local CLI)
#
# This script automates everything technically possible:
#   - Random secret generation (password, bcrypt hash, encryption keys)
#   - GCP Secret Manager creation and injection
#   - Railway environment variable injection via GraphQL API
#   - Terraform plan + apply
#
# Human action required ONLY for these one-time platform steps (truly impossible
# to automate — see docs/runbooks/bootstrap.md for exact instructions):
#   1. GCP project creation + billing activation (credit card verification)
#   2. GitHub App registration + org installation (OAuth browser consent)
#   3. Railway account creation + initial project + API token (Stripe billing)
#   4. Cloudflare account + first API token (dashboard, chicken-and-egg)
#   5. OpenRouter account + billing + Management API key (credit card)
#   6. Telegram @BotFather /newbot (technically impossible to automate)
#
# Usage:
#   ./tools/bootstrap.sh                     # full run
#   ./tools/bootstrap.sh --dry-run           # print what would happen, no changes
#   ./tools/bootstrap.sh --check-secrets     # verify all secrets exist
#   ./tools/bootstrap.sh --skip-terraform    # skip terraform apply
#   ./tools/bootstrap.sh --skip-railway      # skip Railway variable injection

set -euo pipefail

# ── Flags ────────────────────────────────────────────────────────────────────

DRY_RUN=false
CHECK_SECRETS_ONLY=false
SKIP_TERRAFORM=false
SKIP_RAILWAY=false

for arg in "$@"; do
  case $arg in
    --dry-run)        DRY_RUN=true ;;
    --check-secrets)  CHECK_SECRETS_ONLY=true ;;
    --skip-terraform) SKIP_TERRAFORM=true ;;
    --skip-railway)   SKIP_RAILWAY=true ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

require_env() {
  if [[ -z "${!1:-}" ]]; then
    error "Required variable \$$1 is not set."
    error "Export it before running this script: export $1=..."
    exit 1
  fi
}

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would run: $*"
  else
    "$@"
  fi
}

hitl_gate() {
  local step="$1"; local platform="$2"; local instructions="$3"
  echo ""
  echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}${BOLD}║  HUMAN ACTION REQUIRED — Step ${step}: ${platform}${NC}"
  echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
  echo -e "${YELLOW}${instructions}${NC}"
  echo ""
  read -r -p "Press ENTER when complete (Ctrl+C to abort): "
}

secret_exists() {
  gcloud secrets versions access latest --secret="$1" --project="${GCP_PROJECT_ID}" &>/dev/null 2>&1
}

create_or_update_secret() {
  local name="$1"; local value="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would inject secret: ${name}"
    return
  fi
  if gcloud secrets describe "${name}" --project="${GCP_PROJECT_ID}" &>/dev/null 2>&1; then
    echo -n "${value}" | gcloud secrets versions add "${name}" \
      --project="${GCP_PROJECT_ID}" --data-file=-
  else
    gcloud secrets create "${name}" \
      --project="${GCP_PROJECT_ID}" --replication-policy=automatic
    echo -n "${value}" | gcloud secrets versions add "${name}" \
      --project="${GCP_PROJECT_ID}" --data-file=-
  fi
  success "Secret stored: ${name}"
}

generate_bcrypt_hash() {
  local password="$1"
  if command -v htpasswd &>/dev/null; then
    htpasswd -bnBC 10 "" "${password}" | tr -d ':\n'
  elif python3 -c "import bcrypt" 2>/dev/null; then
    python3 -c "import bcrypt; print(bcrypt.hashpw(b'${password}', bcrypt.gensalt(10)).decode())"
  else
    info "Installing python3 bcrypt..."
    pip3 install bcrypt -q
    python3 -c "import bcrypt; print(bcrypt.hashpw(b'${password}', bcrypt.gensalt(10)).decode())"
  fi
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

info "Checking prerequisites..."
for cmd in gcloud python3 git; do
  command -v "${cmd}" &>/dev/null || { error "Missing required command: ${cmd}"; exit 1; }
done

require_env GCP_PROJECT_ID

# ── Secret Check Mode ─────────────────────────────────────────────────────────

check_all_secrets() {
  local required=(
    github-app-id github-app-installation-id github-app-private-key
    cloudflare-api-token cloudflare-account-id
    n8n-encryption-key n8n-admin-password-hash
    telegram-bot-token openrouter-management-key
  )
  local missing=()
  for s in "${required[@]}"; do
    if secret_exists "${s}"; then
      success "Secret exists: ${s}"
    else
      error "Missing: ${s}"; missing+=("${s}")
    fi
  done
  [[ ${#missing[@]} -eq 0 ]] || { error "${#missing[@]} secret(s) missing."; exit 1; }
  success "All required secrets are present."
}

if [[ "${CHECK_SECRETS_ONLY}" == "true" ]]; then
  check_all_secrets; exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 1 — Human-gated one-time platform setup
# Each gate is a hard platform boundary that cannot be bypassed programmatically.
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}━━━ PHASE 1: One-time platform setup (human-gated) ━━━${NC}"
echo "These steps require a human once. After completion, everything else runs automatically."
echo ""

# Gate 1 — GCP billing (truly cannot be automated — requires credit card verification)
if ! gcloud billing projects describe "${GCP_PROJECT_ID}" --format="value(billingEnabled)" 2>/dev/null | grep -q "True"; then
  hitl_gate "1" "GCP Billing" \
"GCP project '${GCP_PROJECT_ID}' has no billing account linked.

1. Go to: https://console.cloud.google.com/billing/projects
2. Link a billing account to project: ${GCP_PROJECT_ID}
3. Run: gcloud services enable iam.googleapis.com iamcredentials.googleapis.com \\
     secretmanager.googleapis.com sts.googleapis.com cloudresourcemanager.googleapis.com \\
     --project=${GCP_PROJECT_ID}"
else
  success "GCP billing is active."
fi

# Gate 2 — GitHub App (manifest flow requires browser click — no curl path)
if ! secret_exists "github-app-id"; then
  hitl_gate "2" "GitHub App" \
"Create the GitHub App (one-time browser step — no API alternative exists for standard orgs):

1. Open: https://github.com/organizations/${GITHUB_ORG:-YOUR_ORG}/settings/apps/new
2. Set permissions: Contents R/W, Pull requests R/W, Workflows R/W, Secrets R/W
3. Generate + download the private key (.pem)
4. Install the app on your repo
5. Note: App ID, Installation ID, path to .pem file
6. Export before continuing:
   export GITHUB_APP_ID=...
   export GITHUB_APP_INSTALLATION_ID=...
   export GITHUB_APP_PRIVATE_KEY_PATH=/path/to/key.pem"
  require_env GITHUB_APP_ID
  require_env GITHUB_APP_INSTALLATION_ID
  require_env GITHUB_APP_PRIVATE_KEY_PATH
else
  success "GitHub App secrets already in Secret Manager."
  GITHUB_APP_ID=""
  GITHUB_APP_INSTALLATION_ID=""
  GITHUB_APP_PRIVATE_KEY_PATH=""
fi

# Gate 3 — Railway account (Stripe billing — cannot be bypassed)
if ! secret_exists "railway-api-token"; then
  hitl_gate "3" "Railway" \
"Create Railway account + project + API token (one-time, Stripe required):

1. Sign up at https://railway.app (GitHub OAuth)
2. Create project: your-agent-project
3. Link to your GitHub repo
4. Account Settings → Tokens → New Token (use Account token, not Project token)
5. Export before continuing:
   export RAILWAY_API_TOKEN=...
   export RAILWAY_PROJECT_ID=...
   export RAILWAY_ENVIRONMENT_ID=...  (from project settings)
   export RAILWAY_N8N_SERVICE_ID=...  (from service settings)
   export RAILWAY_AGENT_SERVICE_ID=... (from service settings)"
  require_env RAILWAY_API_TOKEN
  require_env RAILWAY_PROJECT_ID
  require_env RAILWAY_ENVIRONMENT_ID
else
  success "Railway token already in Secret Manager."
  RAILWAY_API_TOKEN="$(gcloud secrets versions access latest --secret=railway-api-token --project="${GCP_PROJECT_ID}")"
fi

# Gate 4 — Cloudflare first token (chicken-and-egg: need a token to create tokens)
if ! secret_exists "cloudflare-api-token"; then
  hitl_gate "4" "Cloudflare" \
"Generate Cloudflare API token (one-time dashboard step — R-01):

1. Log in at https://cloudflare.com
2. Profile → API Tokens → Create Token
3. Template: Edit Cloudflare Workers
4. Scope: your specific zone + Worker only
5. Copy token immediately (shown once only)
6. Export before continuing:
   export CLOUDFLARE_API_TOKEN=...
   export CLOUDFLARE_ACCOUNT_ID=...
   export CLOUDFLARE_ZONE_ID=..."
  require_env CLOUDFLARE_API_TOKEN
  require_env CLOUDFLARE_ACCOUNT_ID
  require_env CLOUDFLARE_ZONE_ID
else
  success "Cloudflare token already in Secret Manager."
fi

# Gate 5 — OpenRouter account (credit card required)
if ! secret_exists "openrouter-management-key"; then
  hitl_gate "5" "OpenRouter" \
"Create OpenRouter account + Management API key (credit card required):

1. Sign up at https://openrouter.ai
2. Add billing credits (\$20+ recommended)
3. Settings → API Keys → Create Management Key
4. Export before continuing:
   export OPENROUTER_MANAGEMENT_KEY=..."
  require_env OPENROUTER_MANAGEMENT_KEY
else
  success "OpenRouter key already in Secret Manager."
fi

# Gate 6 — Telegram (technically impossible to automate)
if ! secret_exists "telegram-bot-token"; then
  hitl_gate "6" "Telegram — DO NOT AUTOMATE" \
"Telegram bot creation cannot be automated. @BotFather requires human Telegram client:

1. Open Telegram → find @BotFather
2. Send: /newbot
3. Name: Your Agent Bot
4. Username: your_agent_bot  (must end in 'bot', globally unique)
5. Copy the HTTP API Token
6. Export before continuing:
   export TELEGRAM_BOT_TOKEN=...
   export TELEGRAM_CHAT_ID=...  (send a msg to your bot, then GET /getUpdates)"
  require_env TELEGRAM_BOT_TOKEN
  require_env TELEGRAM_CHAT_ID
else
  success "Telegram token already in Secret Manager."
fi

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 2 — Fully automated secret generation and injection
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}━━━ PHASE 2: Automated secret generation ━━━${NC}"

# Generate n8n encryption key
if ! secret_exists "n8n-encryption-key"; then
  info "Generating n8n encryption key (CSPRNG)..."
  N8N_ENCRYPTION_KEY="$(python3 -c "import secrets; print(secrets.token_hex(32))")"
  create_or_update_secret "n8n-encryption-key" "${N8N_ENCRYPTION_KEY}"
else
  success "n8n encryption key already exists."
fi

# Generate n8n admin password + bcrypt hash
if ! secret_exists "n8n-admin-password-hash"; then
  info "Generating n8n admin password and bcrypt hash..."
  N8N_ADMIN_PASSWORD="$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")"
  info "Hashing with bcrypt (this takes ~1s)..."
  N8N_ADMIN_PASSWORD_HASH="$(generate_bcrypt_hash "${N8N_ADMIN_PASSWORD}")"
  create_or_update_secret "n8n-admin-password-hash" "${N8N_ADMIN_PASSWORD_HASH}"
  # Store plaintext separately so the operator can retrieve it if needed
  create_or_update_secret "n8n-admin-password-plaintext" "${N8N_ADMIN_PASSWORD}"
  success "n8n password generated and hashed. Retrieve plaintext: gcloud secrets versions access latest --secret=n8n-admin-password-plaintext --project=${GCP_PROJECT_ID}"
else
  success "n8n admin password hash already exists."
fi

# Inject human-provided secrets (from Phase 1 exports)
[[ -n "${GITHUB_APP_ID:-}" ]]                && create_or_update_secret "github-app-id"              "${GITHUB_APP_ID}"
[[ -n "${GITHUB_APP_INSTALLATION_ID:-}" ]]   && create_or_update_secret "github-app-installation-id" "${GITHUB_APP_INSTALLATION_ID}"
[[ -n "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]]  && run_or_dry gcloud secrets create "github-app-private-key" \
  --project="${GCP_PROJECT_ID}" --replication-policy=automatic 2>/dev/null || true && \
  run_or_dry gcloud secrets versions add "github-app-private-key" \
  --project="${GCP_PROJECT_ID}" --data-file="${GITHUB_APP_PRIVATE_KEY_PATH}"
[[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]         && create_or_update_secret "cloudflare-api-token"       "${CLOUDFLARE_API_TOKEN}"
[[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]]        && create_or_update_secret "cloudflare-account-id"      "${CLOUDFLARE_ACCOUNT_ID}"
[[ -n "${OPENROUTER_MANAGEMENT_KEY:-}" ]]    && create_or_update_secret "openrouter-management-key"  "${OPENROUTER_MANAGEMENT_KEY}"
[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]           && create_or_update_secret "telegram-bot-token"         "${TELEGRAM_BOT_TOKEN}"
[[ -n "${RAILWAY_API_TOKEN:-}" ]]            && create_or_update_secret "railway-api-token"          "${RAILWAY_API_TOKEN}"

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 3 — Terraform apply
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}━━━ PHASE 3: Terraform apply ━━━${NC}"

if [[ "${SKIP_TERRAFORM}" == "true" ]]; then
  warn "Skipping Terraform (--skip-terraform). Run manually: cd terraform && terraform apply"
elif ! command -v terraform &>/dev/null; then
  warn "terraform not installed. Install it and run: cd terraform && terraform init && terraform apply"
else
  info "Running terraform init..."
  run_or_dry terraform -chdir=terraform init -input=false

  info "Running terraform plan..."
  run_or_dry terraform -chdir=terraform plan \
    -var="gcp_project_id=${GCP_PROJECT_ID}" \
    -var="github_repo=${GITHUB_REPO:-}" \
    -var="terraform_state_bucket=${TF_STATE_BUCKET:-${GCP_PROJECT_ID}-tfstate}" \
    -out=tfplan

  if [[ "${DRY_RUN}" != "true" ]]; then
    echo ""
    warn "Review the plan above carefully."
    read -r -p "Apply? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" == "yes" ]]; then
      terraform -chdir=terraform apply tfplan
      success "Terraform apply complete."
    else
      warn "Terraform apply skipped. Run manually when ready: terraform -chdir=terraform apply tfplan"
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 4 — Railway environment variable injection (fully automated)
# Uses variableCollectionUpsert GraphQL mutation — atomic bulk update.
# Source: https://docs.railway.com/integrations/api/manage-variables
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}━━━ PHASE 4: Railway environment variable injection ━━━${NC}"

if [[ "${SKIP_RAILWAY}" == "true" ]]; then
  warn "Skipping Railway injection (--skip-railway)."
elif [[ -z "${RAILWAY_PROJECT_ID:-}" ]] || [[ -z "${RAILWAY_ENVIRONMENT_ID:-}" ]]; then
  warn "RAILWAY_PROJECT_ID or RAILWAY_ENVIRONMENT_ID not set — skipping Railway injection."
  warn "Set them and re-run with Railway variables exported."
else
  RAIL_TOKEN="$(gcloud secrets versions access latest --secret=railway-api-token --project="${GCP_PROJECT_ID}" 2>/dev/null || echo "${RAILWAY_API_TOKEN:-}")"
  N8N_ENC_KEY="$(gcloud secrets versions access latest --secret=n8n-encryption-key --project="${GCP_PROJECT_ID}" 2>/dev/null || echo "")"
  N8N_PWD_HASH="$(gcloud secrets versions access latest --secret=n8n-admin-password-hash --project="${GCP_PROJECT_ID}" 2>/dev/null || echo "")"
  TG_TOKEN="$(gcloud secrets versions access latest --secret=telegram-bot-token --project="${GCP_PROJECT_ID}" 2>/dev/null || echo "")"
  OR_KEY="$(gcloud secrets versions access latest --secret=openrouter-management-key --project="${GCP_PROJECT_ID}" 2>/dev/null || echo "")"

  inject_railway_variables() {
    local service_id="$1"
    local -n vars_ref=$2

    # Build JSON variables object
    local vars_json="{}"
    for key in "${!vars_ref[@]}"; do
      vars_json="$(python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
obj[sys.argv[2]] = sys.argv[3]
print(json.dumps(obj))
" "${vars_json}" "${key}" "${vars_ref[$key]}")"
    done

    local payload
    payload="$(python3 -c "
import json
mutation = 'mutation variableCollectionUpsert(\$input: VariableCollectionUpsertInput!) { variableCollectionUpsert(input: \$input) }'
variables = {
  'input': {
    'projectId': '${RAILWAY_PROJECT_ID}',
    'environmentId': '${RAILWAY_ENVIRONMENT_ID}',
    'serviceId': '${service_id}',
    'variables': json.loads('${vars_json}')
  }
}
print(json.dumps({'query': mutation, 'variables': variables}))
")"

    if [[ "${DRY_RUN}" == "true" ]]; then
      echo -e "${YELLOW}[DRY-RUN]${NC} Would inject Railway variables for service: ${service_id}"
      return
    fi

    local result
    result="$(curl -sS -X POST 'https://backboard.railway.app/graphql/v2' \
      -H "Authorization: Bearer ${RAIL_TOKEN}" \
      -H "Content-Type: application/json" \
      --data-binary "${payload}")"

    if echo "${result}" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('data',{}).get('variableCollectionUpsert') else 1)" 2>/dev/null; then
      success "Railway variables injected for service: ${service_id}"
    else
      error "Railway injection failed for service: ${service_id}"
      echo "${result}"
    fi
  }

  # n8n service variables
  if [[ -n "${RAILWAY_N8N_SERVICE_ID:-}" ]]; then
    declare -A N8N_VARS=(
      ["N8N_ENCRYPTION_KEY"]="${N8N_ENC_KEY}"
      ["N8N_INSTANCE_OWNER_MANAGED_BY_ENV"]="true"
      ["N8N_INSTANCE_OWNER_EMAIL"]="${N8N_OWNER_EMAIL:-ops@example.com}"
      ["N8N_INSTANCE_OWNER_FIRST_NAME"]="Instance"
      ["N8N_INSTANCE_OWNER_LAST_NAME"]="Owner"
      ["N8N_INSTANCE_OWNER_PASSWORD_HASH"]="${N8N_PWD_HASH}"
      ["N8N_RUNNERS_ENABLED"]="false"
      ["N8N_PROTOCOL"]="https"
      ["N8N_PORT"]="5678"
    )
    inject_railway_variables "${RAILWAY_N8N_SERVICE_ID}" N8N_VARS
  fi

  # Agent (TS router) service variables
  if [[ -n "${RAILWAY_AGENT_SERVICE_ID:-}" ]]; then
    declare -A AGENT_VARS=(
      ["GCP_PROJECT_ID"]="${GCP_PROJECT_ID}"
      ["OPENROUTER_BASE_URL"]="https://openrouter.ai/api/v1"
      ["OPENROUTER_DAILY_BUDGET_USD"]="10"
      ["TELEGRAM_WEBHOOK_PATH"]="/webhook/telegram"
      ["TELEGRAM_CHAT_ID"]="${TELEGRAM_CHAT_ID:-}"
    )
    inject_railway_variables "${RAILWAY_AGENT_SERVICE_ID}" AGENT_VARS
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 5 — Final validation
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}━━━ PHASE 5: Validation ━━━${NC}"

check_all_secrets

if command -v npm &>/dev/null && [[ -d node_modules ]]; then
  run_or_dry npm run build
  run_or_dry npm run test
fi

echo ""
success "Bootstrap complete!"
echo ""
info "Next steps:"
info "  1. Push to main to trigger the deploy workflow: git push origin main"
info "  2. Monitor deployment: railway status"
info "  3. Validate n8n: curl https://YOUR_N8N_URL/healthz"
info "  4. Set GitHub repository variables (GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT_EMAIL)"
info "     Values available in Terraform outputs: terraform -chdir=terraform output"
