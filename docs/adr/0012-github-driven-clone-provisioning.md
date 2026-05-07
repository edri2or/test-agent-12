# ADR-0012: GitHub-driven clone provisioning (ADR-0011 Phase E)

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Build agent (Claude Code, claude-opus-4-7), operator

## Context and Problem Statement

[ADR-0011 §1](0011-silo-isolation-pattern.md) (Phase C, PR #32) shipped auto-create of per-clone GCP projects via `tools/grant-autonomy.sh` Step 0. The Q-Path live validation on 2026-05-01 (see `docs/JOURNEY.md` "ADR-0011 §1 live validation (Q-Path)") proved the auto-create path end-to-end: a brand-new clone `edri2or/autonomous-agent-test-clone` got its own GCP project, WIF pool/provider, runtime SA, state bucket, and isolated GitHub Variables — with zero spillover into the source project's 36 secrets.

Q-Path required the operator to run 4–5 lines in GCP Cloud Shell. The next step is to lift the trigger surface from Cloud Shell to GitHub `workflow_dispatch`, leaving the per-clone operator surface at zero.

## Decision Drivers

- **ADR-0007 Inviolable Autonomy Contract** — minimize operator touch points to the absolute minimum the platform allows.
- **No regression on isolation guarantees** — silo isolation (ADR-0010, ADR-0011 §1) must hold.
- **Reuse, don't reinvent** — `grant-autonomy.sh` already encodes the full bootstrap; the workflow should drive it unchanged in CI mode.
- **Audit trail** — every project creation must appear in this repo's GitHub Actions history.

## Considered Options

1. **Lift trigger surface to `workflow_dispatch` on the template-builder repo (Phase E)** — one new workflow `provision-new-clone.yml` calls the existing `grant-autonomy.sh` end-to-end against a new project, after a one-time-global operator setup of org-level SA bindings and a stored PAT.
2. **Keep Cloud Shell as the only path** — operator runs ~5 lines per clone forever.
3. **Hosted SaaS provisioner** — outsource clone bootstrap to a third-party platform.

## Decision Outcome

**Chosen option:** Option 1 (Phase E), because it eliminates per-clone operator action while preserving full transparency (every project creation is a workflow run on this repo) and reusing the validated `grant-autonomy.sh` script verbatim. Option 2 imposes an indefinite operator tax. Option 3 introduces a new trust boundary and contradicts the "self-hosted control plane" property.

### Consequences

**Good:**

- Per-clone operator surface drops to zero after the §E.1 one-time-global setup.
- The same `grant-autonomy.sh` runs in both Cloud Shell mode and CI-WIF mode (no parallel implementation to maintain).
- Workflow run history is the audit trail; no separate logging required.
- WIF `attributeCondition` remains `assertion.repository == 'edri2or/autonomous-agent-template-builder'` — only this repo's CI can impersonate the runtime SA, even after org-level role expansion.

**Bad / accepted trade-offs:**

- The runtime SA gains org-level `projectCreator` + `billing.user`. Mitigated by the repo-scoped WIF; tracked as R-11 in `docs/risk-register.md`.
- ~~A PAT (`gh-admin-token`) must be stored once globally in `or-infra-templet-admin` Secret Manager.~~ **Superseded by [ADR-0014](0014-provisioner-github-app.md)** — `gh-admin-token` is being replaced by a dedicated Provisioner GitHub App.
- The Cloud Shell path is preserved for the chicken-egg case (the very first clone, before the template-builder itself exists).

### Required one-time-global operator pre-grants (§E.1)

Performed once for the entire org's clone-provisioning lifecycle, NOT per clone. Authoritative executable commands: `docs/runbooks/bootstrap.md` Path C.

1. **Sub-step 1a (org-level):** `roles/resourcemanager.projectCreator` + `roles/resourcemanager.organizationViewer` + `roles/billing.user` on the **org** → runtime SA. Run from the workspace admin.
2. **Sub-step 1b (billing-account-level — required, can NOT be done from the workspace account):** `roles/billing.user` **and** `roles/billing.viewer` on the billing account directly → same SA. Both bindings are required; `billing.user` permits link/unlink (the create flow) while `billing.viewer` permits `gcloud billing projects list` (needed by `probe-billing-projects.yml` to diagnose the 5/10-project soft-cap before it blocks a future apply-system-spec dispatch). Both must be run from the gmail account that originally created the billing account before the Workspace org existed. Per [Cloud Billing IAM docs](https://cloud.google.com/billing/docs/how-to/billing-access), org-level `billing.admin` only propagates to billing accounts "owned by or transferred to" the organization; for billing accounts created from a personal Google account before the Workspace existed, the gmail account remains the sole admin. `billing.viewer` was added 2026-05-02 after live diagnostic on apply-system-spec runs 25253910937 / 25254068938 / 25254227982.
3. **Sub-step 2:** ~~`gh-admin-token` PAT in the template-builder's GCP Secret Manager.~~ **Superseded by [ADR-0014](0014-provisioner-github-app.md)** — register the Provisioner GitHub App instead via `register-provisioner-app.yml`.
4. **Sub-step 3:** `is_template=true` on the source template repo (already done in Q-Path).
5. **Sub-step 4 (factory-folder OrgPolicy override — required if the org enforces `iam.allowedPolicyMemberDomains`):** override the constraint at the **factory folder** to `allowAll`. Inherited by every current and future clone project under that folder; no per-clone work. Required for `bootstrap.yml` Phase 4 to grant `allUsers run.invoker` on the Cloud Run receiver so GitHub OAuth callbacks can reach it (R-07). Run from the **workspace-admin account** (the folder lives in the Workspace org). Validated end-to-end 2026-05-02 on `folders/667201164106`:

```bash
gcloud auth login <workspace-admin-account>
gcloud services enable orgpolicy.googleapis.com   # on Cloud Shell's billing project
cat > /tmp/policy.yaml <<'EOF'
name: folders/<FACTORY_FOLDER_ID>/policies/iam.allowedPolicyMemberDomains
spec:
  rules:
    - allowAll: true
EOF
gcloud org-policies set-policy /tmp/policy.yaml
```

If the org doesn't enforce `iam.allowedPolicyMemberDomains` (default GCP setup), this sub-step is unnecessary.

**Three iterations during live debug (lesson learned):**

- **v1 (original plan):** prescribed billing-account-level binding from the workspace account. Failed — workspace user lacks `billing.accounts.setIamPolicy`.
- **v2:** switched to org-level `roles/billing.user` only. Failed — org-level doesn't propagate to billing accounts not owned by the org.
- **v3 (current):** sub-step 1b adds direct billing-account binding from the gmail account. Validated end-to-end (see JOURNEY entry).

**Cleaner long-term alternative (not done here):** transfer the billing account to the org from the gmail account (Cloud Console → Billing → "Change organization"). After transfer, sub-step 1b becomes unnecessary for any future SA.

## Validation

1. **Pre-merge:** `markdownlint`, `markdown-invariants`, `lychee --offline`, OPA/Conftest — all green.
2. **Post-merge dispatch:** trigger `provision-new-clone.yml` with `new_repo_name=autonomous-agent-test-clone-2`, `new_project_id=or-test-clone-002`. Step summary shows the new clone's IDs.
3. **Acceptance:** all three clones (`autonomous-agent-template-builder`, `autonomous-agent-test-clone`, `autonomous-agent-test-clone-2`) operate independently. Verifying via `gcloud projects describe`, `gh variable list`, and `gcloud secrets list --project=or-infra-templet-admin | wc -l` (expect: still 36 — silo isolation holds).
4. **Q-Path supersession:** Q-Path is preserved as the binding "first ever live test of §1". Phase E builds on it; it does NOT replace it.

## Links

- [ADR-0007: Inviolable Autonomy Contract](0007-inviolable-autonomy-contract.md)
- [ADR-0010: Per-clone GCP project isolation](0010-clone-gcp-project-isolation.md)
- [ADR-0011: Silo isolation pattern](0011-silo-isolation-pattern.md) §1 (the foundation Phase E builds on)
- `docs/plans/adr-0012-phase-e-github-driven-clone.md` (full implementation plan)
- `docs/JOURNEY.md` "ADR-0011 §1 live validation (Q-Path)" entry (binding proof of §1)
- [GitHub REST: Create a repository using a template](https://docs.github.com/en/rest/repos/repos#create-a-repository-using-a-template)
- [google-github-actions/auth v2 (WIF)](https://github.com/google-github-actions/auth)
