#!/usr/bin/env bash
# validate.sh — Local validation runner
#
# Runs all local validation commands in sequence.
# Safe to run repeatedly. Never mutates remote state.
#
# Usage: ./tools/validate.sh [--skip-terraform] [--skip-tests]

set -euo pipefail

SKIP_TERRAFORM=false
SKIP_TESTS=false
FAIL_FAST=false

for arg in "$@"; do
  case $arg in
    --skip-terraform) SKIP_TERRAFORM=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    --fail-fast) FAIL_FAST=true ;;
  esac
done

# ── Helpers ─────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((PASS++)) || true; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ((FAIL++)) || true; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }

run_check() {
  local name="$1"
  shift
  info "Running: ${name}"
  if "$@" 2>&1; then
    pass "${name}"
  else
    fail "${name}"
    if [[ "${FAIL_FAST}" == "true" ]]; then
      echo ""
      echo -e "${RED}Validation failed at: ${name}${NC}"
      echo -e "${RED}Fix the issue and re-run ./tools/validate.sh${NC}"
      exit 1
    fi
  fi
}

# ── Validation Steps ─────────────────────────────────────────────────────────

echo ""
info "Autonomous Agent Template — Local Validation"
echo "============================================"
echo ""

# 1. Git status — no uncommitted secrets
info "Checking for secrets in git staging area..."
if git diff --cached --name-only | grep -E '\.(env|pem|key|p12|pfx|json)$' | grep -v 'example\|template\|package'; then
  fail "Staged files may contain secrets — review before committing"
else
  pass "No secret file patterns detected in staging area"
fi

# 2. .gitignore sanity check
run_check ".gitignore covers .env files" \
  bash -c 'echo "test" > /tmp/test.env && git check-ignore /tmp/test.env 2>/dev/null | grep -q test || echo ".env not in .gitignore" && rm /tmp/test.env'

# 3. TypeScript build
if [[ "${SKIP_TESTS}" != "true" ]]; then
  if [[ -d "node_modules" ]]; then
    run_check "TypeScript compilation (tsc --noEmit)" \
      npm run build
  else
    warn "node_modules not found — run 'npm install' first"
    skip "TypeScript compilation"
  fi
fi

# 4. Jest tests
if [[ "${SKIP_TESTS}" != "true" ]]; then
  if [[ -d "node_modules" ]]; then
    run_check "Jest unit tests" \
      npm run test
  else
    skip "Jest tests (node_modules not installed)"
  fi
fi

# 5. Terraform format check
if [[ "${SKIP_TERRAFORM}" != "true" ]]; then
  if command -v terraform &>/dev/null; then
    run_check "Terraform format" \
      terraform -chdir=terraform fmt -check -recursive

    run_check "Terraform validate" \
      bash -c 'cd terraform && terraform init -backend=false -input=false && terraform validate'
  else
    skip "Terraform not installed — skipping IaC validation"
  fi
fi

# 6. OPA/Rego syntax check
if command -v opa &>/dev/null; then
  run_check "OPA policy syntax (adr.rego)" \
    opa check policy/adr.rego

  run_check "OPA policy syntax (context_sync.rego)" \
    opa check policy/context_sync.rego
else
  skip "OPA not installed — skipping Rego syntax check (CI will validate)"
fi

# 7. Dockerfile lint
if command -v hadolint &>/dev/null; then
  run_check "Dockerfile lint" \
    hadolint Dockerfile
else
  skip "hadolint not installed — skipping Dockerfile lint"
fi

# 8. File structure check
info "Checking required file structure..."
REQUIRED_FILES=(
  "CLAUDE.md"
  "README.md"
  "SECURITY.md"
  "AGENTS.md"
  ".gitignore"
  "package.json"
  "tsconfig.json"
  ".env.example"
  "railway.toml"
  ".claude/settings.json"
  ".github/workflows/documentation-enforcement.yml"
  ".github/workflows/terraform-plan.yml"
  ".github/workflows/deploy.yml"
  "docs/JOURNEY.md"
  "docs/CLAUDE.md"
  "docs/adr/0001-initial-architecture.md"
  "docs/adr/template.md"
  "docs/runbooks/bootstrap.md"
  "docs/runbooks/rollback.md"
  "docs/autonomy/build-agent-autonomy.md"
  "docs/autonomy/runtime-system-autonomy.md"
  "policy/adr.rego"
  "policy/context_sync.rego"
  "src/agent/index.ts"
  "src/agent/skills/SKILL.md"
  "src/agent/tests/router.test.ts"
  "terraform/gcp.tf"
  "terraform/cloudflare.tf"
  "terraform/variables.tf"
  "terraform/outputs.tf"
  "terraform/backend.tf"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "${f}" ]]; then
    pass "File exists: ${f}"
  else
    fail "Missing required file: ${f}"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "============================================"
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "============================================"
echo ""

if [[ ${FAIL} -gt 0 ]]; then
  echo -e "${RED}Validation failed. Fix the issues above before committing.${NC}"
  echo ""
  echo "If failures persist after 3 attempts, stop and document in docs/risk-register.md"
  echo "(Per Claude Code operating contract — build-agent autonomy contract Section A)"
  exit 1
else
  echo -e "${GREEN}All checks passed. Safe to commit and push.${NC}"
fi
