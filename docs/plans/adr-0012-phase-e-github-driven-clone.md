# Plan: ADR-0012 (ADR-0011 Phase E) — GitHub-driven clone provisioning

**Status:** READY TO IMPLEMENT. This plan is self-contained — a fresh Claude Code session can pick it up cold by reading CLAUDE.md → JOURNEY.md → this file.
**Author:** Claude Code (claude-opus-4-7), session `claude/q-path-validation-and-phase-e-plan`
**Prerequisite ADRs:** ADR-0007 (autonomy contract), ADR-0010 (per-clone GCP project), ADR-0011 (silo isolation pattern, all 4 sections merged).

## Context — why Phase E

ADR-0011 §1 (Phase C, PR #32) shipped auto-create of GCP projects via `tools/grant-autonomy.sh` Step 0. **Validated live in Q-Path on 2026-05-01** (see JOURNEY.md entry "ADR-0011 §1 live validation (Q-Path)"): a brand-new clone `edri2or/autonomous-agent-test-clone` got its own GCP project `or-test-clone-001` (number `995534842856`), under folder `667201164106`, billing-linked, with WIF + SA + state bucket — and zero spillover into `or-infra-templet-admin` (still 36 secrets, untouched).

The Q-Path validation required the operator to run 4–5 lines in Cloud Shell. The user's stated goal: **eliminate Cloud Shell touches for future clones — drive everything through a workflow_dispatch on the existing `template-builder` repo.** That is Phase E.

After Phase E lands, the per-clone operator surface is:
- (Once globally, already-completed setup) A few org-level role grants and a PAT in GCP Secret Manager (details in §E.1).
- (Per clone) Zero. Claude Code triggers `provision-new-clone.yml` via `workflow_dispatch` and the new clone is fully bootstrapped.

## Recommended approach

A single new workflow `provision-new-clone.yml` on the **template-builder repo**, triggered by `workflow_dispatch` with inputs (`new_repo_name`, `new_project_id`, `parent_folder_id`, `billing_account_id`). The workflow:

1. Authenticates to GCP via the **existing** WIF on `template-builder` (no new WIF setup — just role expansion on the existing runtime SA, see §E.1).
2. Reads a stored PAT (`gh-admin-token`) from GCP Secret Manager (synced once-globally per §E.1).
3. Creates the new GitHub repo from the template via `gh api` with that PAT.
4. Runs the existing `tools/grant-autonomy.sh` end-to-end against the new project — same script that ran in Q-Path.
5. Reports success in a step summary with the new clone's IDs.

`grant-autonomy.sh` itself needs only a **small CI-mode tweak** (§E.2) — skip the Cloud-Shell-specific check `gcloud auth list --filter=status:ACTIVE | grep -q .` when running under WIF (the WIF principal is the active gcloud auth in CI; the existing check is a Cloud Shell sanity guard).

## §E.1 — Required one-time operator pre-grants (BEFORE Phase E lands)

These are **one-time global** actions the operator must do once, ever, for the entire org. They should be documented in the runbook so the operator can do them when they're ready to test Phase E. **They do NOT block the PR landing — only its post-merge validation.**

### Sub-step 1: extend the existing runtime SA's role bindings to org level

The existing runtime SA `github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com` currently has roles bound at project level (per `bootstrap-state.md`). For Phase E, it needs `projectCreator` + `billing.user` at org/billing-account level so it can create new projects from a workflow.

```bash
SA="github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com"
ORG_ID=905978345393                        # or-infra.com
BILLING=014D0F-AC8E0F-5A7EE7

gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:$SA" \
  --role="roles/resourcemanager.projectCreator" --condition=None

gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:$SA" \
  --role="roles/resourcemanager.organizationViewer" --condition=None

gcloud billing accounts add-iam-policy-binding "$BILLING" \
  --member="serviceAccount:$SA" \
  --role="roles/billing.user"
```

**Security note:** the existing WIF provider has `attributeCondition: assertion.repository == 'edri2or/autonomous-agent-template-builder'` — only workflows running on this exact repo can impersonate this SA. The org-level bindings only become exercisable when an attacker compromises this specific repo's CI. Acceptable blast radius given the audit trail (every new project creation appears in this repo's workflow run history).

### Sub-step 2: store a PAT in GCP Secret Manager as `gh-admin-token`

Phase E's workflow needs to create new GitHub repos and write Variables into them. `GITHUB_TOKEN` from a workflow can't do cross-repo operations. A stored PAT solves it.

```bash
read -rsp "Paste PAT (scopes: repo, workflow, admin:org): " PAT; echo
printf '%s' "$PAT" | gcloud secrets create gh-admin-token \
  --data-file=- \
  --replication-policy=automatic \
  --project=or-infra-templet-admin
unset PAT
```

The PAT is stored in the same `or-infra-templet-admin` project (the template-builder's GCP project) — synced into the new clone's GCP project on demand by the workflow. The PAT can be a fine-grained token scoped only to the `edri2or` org (preferred), or a classic with `repo + workflow + admin:org`.

### Sub-step 3: enable the `is_template` flag on the source repo

This is a one-time API call (no UI). Doable via `gh api` with the operator's existing PAT. **This is also a Q-Path follow-up — already done as of 2026-05-01.**

```bash
gh api -X PATCH repos/edri2or/autonomous-agent-template-builder -F is_template=true
```

Status as of this plan's writing: ✅ done.

## §E.2 — `tools/grant-autonomy.sh` modifications

**Goal:** the script must run unmodified in BOTH operator-Cloud-Shell mode AND CI-WIF mode.

**File:** `tools/grant-autonomy.sh`

**Change 1 (around `set -euo pipefail` near the top):** detect CI mode early.

```bash
# CI mode detection — when CI=true, the gcloud auth is provided by
# google-github-actions/auth@v2 (WIF). The Cloud-Shell-specific
# `gcloud auth list` sanity check below would still pass (it would
# show the impersonated SA), so technically no change is needed here
# UNLESS we add CI-only behavior. The flag is preserved as documentation
# for any future CI-only branches.
CI_MODE="${CI:-false}"
```

**Change 2 (the `sync()` helper, currently around the secret-sync block):** in CI mode, the source GCP project for secret-sync must be `or-infra-templet-admin` (where the platform tokens live), NOT the new clone's project. Today the script uses `${GCP_PROJECT_ID}` — which in Phase E is the new project, where secrets don't exist yet.

```bash
# Operator-mode: GCP_PROJECT_ID is the new clone's project.
# CI-mode: secrets live in the template-builder's project (where this
# workflow runs), so source from there. The secret destination in CI
# mode is still GitHub Secrets on ${GITHUB_REPO}, which is the new clone.
SECRETS_SOURCE_PROJECT="${SECRETS_SOURCE_PROJECT:-${GCP_PROJECT_ID}}"

sync() {
  local GCP_NAME="$1" GH_NAME="$2"
  if VALUE=$(gcloud secrets versions access latest --secret="${GCP_NAME}" \
                --project="${SECRETS_SOURCE_PROJECT}" 2>/dev/null); then
    gh_secret "${GH_NAME}" "${VALUE}"
  else
    echo "  ⚠  GCP secret ${GCP_NAME} not found in ${SECRETS_SOURCE_PROJECT} — skipping"
  fi
}
```

**Change 3 (the `gcloud storage buckets describe/create/update` block, fix the bucket-versioning idempotency bug):** Q-Path surfaced a bucket-versioning eventual-consistency race. Split the create+update into independent idempotent calls.

```bash
# Old: create AND update inside the same `if ! describe` gate.
# New: separate gates.

# 2a. Ensure bucket exists (create-if-missing).
if ! gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" \
       --project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --project="${GCP_PROJECT_ID}" \
    --location="${GCP_REGION}" \
    --uniform-bucket-level-access \
    --quiet
fi

# 2b. Ensure versioning is on (idempotent — runs even if bucket pre-existed).
# A bare-create flake on `--versioning` (Q-Path GcsApiError race) is recovered
# automatically on the next invocation — the create skips, this still runs.
gcloud storage buckets update "gs://${TF_STATE_BUCKET}" \
  --versioning --project="${GCP_PROJECT_ID}" --quiet
```

## §E.3 — `provision-new-clone.yml` workflow scaffold

**File:** `.github/workflows/provision-new-clone.yml` (NEW)

```yaml
name: Provision new clone (ADR-0012)

on:
  workflow_dispatch:
    inputs:
      new_repo_name:
        description: 'New repo name (e.g. autonomous-agent-foo)'
        required: true
      new_project_id:
        description: 'New GCP project ID (must be globally unique, ≤30 chars)'
        required: true
      parent_folder_id:
        description: 'GCP folder ID where the new project will be created'
        required: true
        default: '667201164106'    # operator's "factory" folder
      billing_account_id:
        description: 'GCP billing account to link'
        required: true
        default: '014D0F-AC8E0F-5A7EE7'
      github_owner:
        description: 'GitHub org/user that will own the new repo'
        required: true
        default: 'edri2or'

permissions:
  contents: read
  id-token: write   # WIF token exchange

jobs:
  provision:
    name: Provision new clone
    runs-on: ubuntu-latest
    steps:
      - name: Checkout template-builder
        uses: actions/checkout@v4

      - name: Authenticate to GCP (WIF)
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account:            ${{ vars.GCP_SERVICE_ACCOUNT_EMAIL }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Retrieve gh-admin-token from GCP Secret Manager
        id: ghpat
        uses: google-github-actions/get-secretmanager-secrets@v2
        with:
          secrets: |-
            gh-admin-token:${{ vars.GCP_PROJECT_ID }}/gh-admin-token

      - name: Create new GitHub repo from template
        env:
          GH_TOKEN: ${{ steps.ghpat.outputs.gh-admin-token }}
        run: |
          # The source template lives at github.repository (the workflow's
          # own repo, i.e. autonomous-agent-template-builder). The new repo
          # owner is operator-supplied via inputs.github_owner.
          gh api -X POST "repos/${{ github.repository }}/generate" \
            -f name="${{ inputs.new_repo_name }}" \
            -f owner="${{ inputs.github_owner }}" \
            -F private=false \
            -f description="Auto-provisioned by ADR-0012 from autonomous-agent-template-builder"

      - name: Run grant-autonomy.sh against the new project (CI-WIF mode)
        env:
          CI: 'true'
          GH_TOKEN: ${{ steps.ghpat.outputs.gh-admin-token }}
          GITHUB_REPO: ${{ inputs.github_owner }}/${{ inputs.new_repo_name }}
          GCP_PROJECT_ID: ${{ inputs.new_project_id }}
          GCP_PARENT_FOLDER: ${{ inputs.parent_folder_id }}
          GCP_BILLING_ACCOUNT: ${{ inputs.billing_account_id }}
          # Source secrets from this template-builder's GCP project, sync
          # into the new repo's GitHub Secrets — see §E.2 Change 2.
          SECRETS_SOURCE_PROJECT: ${{ vars.GCP_PROJECT_ID }}
        run: bash tools/grant-autonomy.sh

      - name: Summary
        run: |
          {
            echo "## ✅ Clone provisioned"
            echo
            echo "- New repo: \`${{ inputs.github_owner }}/${{ inputs.new_repo_name }}\`"
            echo "- New GCP project: \`${{ inputs.new_project_id }}\`"
            echo "- Parent folder: \`${{ inputs.parent_folder_id }}\`"
            echo "- Billing account: \`${{ inputs.billing_account_id }}\`"
            echo
            echo "Next step: dispatch \`bootstrap.yml\` on the new repo to inject env vars + register GitHub App."
          } >> "$GITHUB_STEP_SUMMARY"
```

## §E.4 — ADR-0012 + supersession of Q-Path

**File:** `docs/adr/0012-github-driven-clone-provisioning.md` (NEW MADR)

Status: Accepted. Implementation: shipped in Phase E PR. Cite the Q-Path JOURNEY entry as the binding proof that ADR-0011 §1's auto-create is sound; this ADR builds on it by lifting the trigger surface from Cloud Shell to GitHub workflow_dispatch.

Marks Q-Path as the canonical "first ever live test of §1" — preserved for non-repudiation.

## §E.5 — Documentation reconciliation

- **`README.md`** "Single bootstrap action": add a "GitHub-only path (ADR-0012)" callout above the Cloud-Shell path — for new operators, dispatching `provision-new-clone.yml` is now the recommended path; Cloud Shell remains supported for first-clone-ever (chicken-egg before template-builder itself exists).
- **`CLAUDE.md`** HITL row 1: clarify that for clones-after-the-first, no Cloud Shell action is required; the operator only set up §E.1 once, ever.
- **`docs/runbooks/bootstrap.md`**: add Path C — "GitHub-driven (post-Phase E)".
- **`docs/risk-register.md`** R-XX (new, Phase E): "Runtime SA org-level role expansion — blast radius mitigated by repo-scoped WIF".

## Critical files (precise paths)

| File | Action | Reason |
|------|--------|--------|
| `tools/grant-autonomy.sh` | Edit (3 small changes per §E.2) | CI-mode + secrets source project + bucket idempotency |
| `.github/workflows/provision-new-clone.yml` | NEW | The workflow itself |
| `docs/adr/0012-github-driven-clone-provisioning.md` | NEW | The ADR |
| `docs/risk-register.md` | Add R-XX | SA org-level role expansion risk |
| `README.md`, `CLAUDE.md`, `docs/runbooks/bootstrap.md` | Edit | Document Path C, update HITL row 1 |
| `docs/JOURNEY.md` | Append | Phase E session entry |

## Existing utilities to reuse (do NOT reimplement)

- **`tools/grant-autonomy.sh`** — its existing 10 sub-steps (API enable, bucket, SA, roles, WIF pool, WIF provider, WIF binding, GitHub Variables, GitHub Secrets sync, verify) all stay. Only Steps 0/2/sync are touched per §E.2.
- **`google-github-actions/auth@v2` + `setup-gcloud@v2`** — already used by `bootstrap.yml`, `apply-railway-provision.yml`, `deploy.yml`, `terraform-plan.yml`. Same pattern applies in `provision-new-clone.yml`.
- **`google-github-actions/get-secretmanager-secrets@v2`** — already used by `deploy.yml` (`cloudflare-api-token`) and the Telegram-notify step. Same pattern for `gh-admin-token`.
- **`gh api -X POST .../generate`** — official GitHub REST endpoint to create a repo from a template; documented at <https://docs.github.com/en/rest/repos/repos#create-a-repository-using-a-template>. No new tooling.

## Verification

1. **Pre-merge:** `markdownlint`, `markdown-invariants`, `OPA`, `lychee --offline` — all expected green (no anchors renamed).
2. **Operator one-time setup (§E.1)** before post-merge validation. Document the 3 sub-steps for the operator; do NOT auto-execute them.
3. **Post-merge dispatch:** Claude Code dispatches `provision-new-clone.yml` with inputs:
   - `new_repo_name=autonomous-agent-test-clone-2`
   - `new_project_id=or-test-clone-002`
   - `parent_folder_id=667201164106`
   - `billing_account_id=014D0F-AC8E0F-5A7EE7`
4. Workflow runs to green. Step summary shows the new clone's IDs.
5. **Verification commands** (run from this repo's Cloud Shell or via a one-shot read-only workflow — same shape as Q-Path):
   ```bash
   gcloud projects describe or-test-clone-002 --format='value(projectNumber,parent.id)'
   gcloud iam workload-identity-pools providers describe github \
     --workload-identity-pool=github --location=global \
     --project=or-test-clone-002 --format='value(attributeCondition)'
   # Expect: assertion.repository == 'edri2or/autonomous-agent-test-clone-2'
   gh variable list --repo edri2or/autonomous-agent-test-clone-2
   gcloud secrets list --project=or-infra-templet-admin --format='value(name)' | wc -l
   # Expect: still 36, unchanged.
   ```
6. **Acceptance criterion:** all three clones (`autonomous-agent-template-builder`, `autonomous-agent-test-clone`, `autonomous-agent-test-clone-2`) operate independently. Killing project `or-test-clone-002` (`gcloud projects delete`) has zero effect on the other two.

## Out of scope (Phase E does NOT change)

- Cloudflare per-clone domain naming (Phase B, ADR-0011 §2 — already shipped).
- Telegram per-clone bot (Phase D — deferred per ADR-0011 §3).
- Linear per-clone workspace (ADR-0011 §4 — vendor-blocked).
- The pre-existing `bootstrap.yml` Phase 2 terraform-apply chicken-egg (separate ADR-required follow-up).

## Sources / references

- ADR-0007: Inviolable Autonomy Contract.
- ADR-0010: Per-clone GCP project isolation.
- ADR-0011 §1 (Phase C, PR #32): Project Factory adoption — the foundation Phase E builds on.
- JOURNEY entry "ADR-0011 §1 live validation (Q-Path)" — proof that §1 works end-to-end; Phase E lifts it from Cloud Shell to workflow_dispatch.
- [GitHub REST: Create a repository using a template](https://docs.github.com/en/rest/repos/repos#create-a-repository-using-a-template).
- [google-github-actions/auth v2 (WIF)](https://github.com/google-github-actions/auth).
