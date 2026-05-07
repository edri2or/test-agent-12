# ADR-0007: Inviolable Autonomy Contract

**Date:** 2026-05-01
**Status:** Accepted (amended 2026-05-01 — honest-scope amendment after operator audit)
**Deciders:** Operator (`edriorp38@or-infra.com`), Claude Code (build agent)
**Supersedes parts of:** `CLAUDE.md` Build-Agent Autonomy section A (extended, not replaced)
**Amended by:** This ADR's own §"Honest scope amendment" added 2026-05-01 after the operator audit surfaced a contradiction between §Decision-Outcome bullet 1 ("the one and only operator action this repository will ever require") and §Context-and-Problem-Statement bullet 18 (which lists two irreducibly-human vendor floors). The amendment reconciles the two without weakening the GCP scope.

## Honest scope amendment (2026-05-01)

The original Decision-Outcome §1 stated: *"The one and only operator action this repository will ever require: Run `tools/grant-autonomy.sh` once."* This wording is **literally accurate for the GCP trust handshake** but was repeatedly mis-quoted across subsequent sessions to mean "the operator never touches anything again, including platform UIs". That over-reading conflicts with bullet 18 of the same ADR ("Two operations are irreducibly human per third-party policy"). The conflict is now formally resolved as follows.

**Three contract scopes, all binding:**

1. **GCP-only one-time scope.** `bash tools/grant-autonomy.sh` is the **single GCP trust handshake** — once per template-builder repo, never re-asked. ✓ binding.
2. **One-time-global setup scope (per organization, not per clone).** ADR-0012 §E.1 introduces three org-level role bindings + one PAT in Secret Manager. Performed **once for the org's entire clone-provisioning lifecycle**, never re-asked. ✓ binding. *(A residual CI-WIF failure on the first dispatch of `provision-new-clone.yml` is under empirical investigation via a diagnostic probe workflow; any additional pre-grants this surfaces will be added to §E.1 only after measurement, not hypothesis.)*
3. **Per-clone vendor-floor scope.** Three vendor floors are immovable by any future ADR:
   - **GitHub App registration (R-07):** 2 browser clicks ("Create" + "Install") + 1 paste of `installation-id` to GitHub Variables, per child instance. (1 click on GHEC preview API.)
   - **Telegram bot (R-04):** 1 tap per clone (Bot API 9.6 Managed Bots dialog), per child instance.
   - **Linear workspace (R-10):** UI workspace creation per clone if L-silo isolation is desired (or use L-pool — share one workspace across clones).

The phrase "the operator is finished forever" was inaccurate as a blanket statement — it is accurate only within scope (1). Within scope (3), the operator retains a per-clone surface that is **not removable** without vendor cooperation. Future Claude Code sessions MUST distinguish the three scopes and never frame scope (1)'s completion as covering (2) or (3).

**What this amendment does NOT change:**
- The GCP one-time handshake is still single-action, still permanent.
- §E.1 pre-grants are still one-time-global, never re-asked once in place.
- Forbidden agent outputs still apply to anything OUTSIDE the documented scopes (1)-(3) above.

**What this amendment changes:**
- `CLAUDE.md` "Forever / no clicks / no `gcloud` commands" framing is replaced with explicit per-scope language (commit on this date).
- Future ADRs proposing new operator surface MUST cite which scope they fall into; ad-hoc "one more click" requests outside the documented scopes are contract violations.

---

## Context and Problem Statement

Sessions of Claude Code working on this repository have repeatedly regressed into requesting manual operator actions ("run this in Cloud Shell", "set this GitHub Secret", "click this button") even though the architecture is designed for full agent autonomy after a one-time trust handshake. The operator has explicitly rejected this drip-feed pattern: they want **one** action, performed once, after which every future session operates without involving the operator in any platform glue, account creation, or CLI invocation.

This ADR formalizes the contract. It is the canonical reference any future session must consult before making a request to the operator.

## Decision Drivers

- **Operator demand.** Verbatim: "אני פותח את האוטונומיה ל-GCP וזהו. אני לא נודע יותר בכלום. לא ריילוואי, לא n8n, לא יצירת חשבונות ולא כלום." ("I open up GCP autonomy and that's it. I'm not informed of anything else. No Railway, no n8n, no creating accounts, none of it.")
- **Pre-existing operator state.** All platform accounts (Railway, Telegram bot via @BotFather, Cloudflare, OpenRouter, Linear) are already created. All credentials are in GCP Secret Manager (per `docs/bootstrap-state.md`).
- **Vendor policy floors.** Two operations are irreducibly human per third-party policy:
  1. Initial GCP trust handshake — Google Workload Identity Federation requires at least one bootstrapping identity to set up the pool/provider/SA/bindings (no Google "auto-bootstrap" exists; per https://docs.cloud.google.com/iam/docs/workload-identity-federation).
  2. GitHub App registration via manifest flow — requires two browser clicks ("Create" + "Install") on github.com (1-click only on GHEC preview API per https://github.blog/changelog/2025-07-01-enterprise-level-access-for-github-apps-and-installation-automation-apis/, https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest).
- **Industry precedent.** The "ONE OIDC trust + ONE IAM binding then full autonomy" pattern is the consensus across Spacelift, Atlantis, Terraform Cloud (https://docs.spacelift.io/integrations/cloud-providers/aws, https://www.runatlantis.io/docs/provider-credentials).
- **OWASP Agentic Top 10 (2025-12-09).** Kill switches must remain HITL for ASI02 (destructive ops) and ASI03 (IAM elevation, billing changes) at *runtime*, but bootstrap is not a kill-switch category (https://genai.owasp.org/2025/12/09/owasp-top-10-for-agentic-applications-the-benchmark-for-agentic-security-in-the-age-of-autonomous-ai/).

## Considered Options

1. **Drip-feed checklists.** What sessions have been doing — multiple discrete operator tasks across multiple sessions. **Rejected** — the regression pattern the operator demands be eliminated.
2. **Full autonomy with no operator action ever.** Impossible — vendor policy requires at least the GCP trust handshake.
3. **One canonical operator script + ADR-codified contract.** Chosen.

## Decision Outcome

**Chosen option:** Option 3.

### The contract

1. **The one and only operator action this repository will ever require:**
   - Run `tools/grant-autonomy.sh` once in GCP Cloud Shell with `GH_TOKEN` exported. Not in any future session.
2. **Every future session must operate under these rules.** Verbatim text inserted into `CLAUDE.md` `## ⚠️ Inviolable Autonomy Contract` section.
3. **Forbidden agent outputs** (any of these in agent text = contract violation):
   - "Run this command in Cloud Shell"
   - "Manually set this GitHub Secret/Variable"
   - "Go to the GitHub UI / GCP Console / Cloudflare dashboard"
   - "Click [any button] in [any UI]"
   - "Ask your operator to..."
   - Any local CLI invocation: `gcloud`, `terraform apply`, `gh secret set`, `railway`, `wrangler`
   - Account creation requests for any platform
4. **Permitted agent operations** (full autonomy on this repo):
   - All GitHub MCP operations: push, PR, comment, merge, workflow_dispatch, secret/variable writes
   - Workflow log inspection
   - Triggering `bootstrap.yml`, `deploy.yml`, and any other workflow
   - Reading from / writing to GCP via workflows authenticated by WIF
   - Pushing code that triggers Railway / Cloudflare deploys
5. **Runtime HITL exceptions** (ASI02/ASI03 categories — these are not bootstrap blockers, they govern the *deployed* agent's runtime behavior):
   - Destructive operations (`destroy-resource.json` Telegram approval, ADR-0005)
   - IAM elevation requests
   - Billing changes
   - Branch protection mutation
6. **Session-start verification ritual.** Before any other action, every session reads `vars.GCP_WORKLOAD_IDENTITY_PROVIDER`. If empty → halt with: "GCP autonomy not yet granted. Operator runs `tools/grant-autonomy.sh` once. This is the SINGLE permitted operator action."

### Consequences

**Good:**
- Operator is touched exactly once in the lifetime of the repository (plus `destroy-resource.json` runtime approvals — separate concern).
- Future sessions cannot regress into checklist mode without violating an explicit, citable contract.
- Aligns with industry best practice (Spacelift / Atlantis pattern) and OWASP Agentic Top 10 (2025).

**Bad / accepted trade-offs:**
- The one operator script (`tools/grant-autonomy.sh`) is non-trivial (~250 lines bash). Maintenance burden falls on us, not the operator.
- The script duplicates some logic that lives in `terraform/gcp.tf` (WIF pool/provider/SA), because Terraform's GCS backend has a chicken-and-egg with its own state bucket. We accept the duplication; the script is the source of truth for the trust handshake, terraform manages the data plane afterwards.
- The "Forbidden Words" list is rigid; future legitimate exceptions (e.g., a vendor adds a new mandatory consent flow) would require an ADR amendment.

## Validation

1. The script must be **idempotent** — running it twice produces the same end-state with no errors.
2. After the script runs, every GitHub Actions workflow in this repo must authenticate to GCP via WIF only — zero references to `secrets.GOOGLE_CREDENTIALS` should be hit. Verify by inspecting workflow logs after the next bootstrap.yml run.
3. CLAUDE.md must contain the verbatim Inviolable Autonomy Contract section with the Forbidden Words list. Drift is detectable by `policy/context_sync.rego`.
4. Self-test: a future session reading CLAUDE.md and `bootstrap-state.md` must be able to determine, without operator input, whether autonomy has been granted (by checking `GCP_WORKLOAD_IDENTITY_PROVIDER`).

## Links

- [Google Workload Identity Federation docs](https://docs.cloud.google.com/iam/docs/workload-identity-federation)
- [GCP WIF best practices](https://docs.cloud.google.com/iam/docs/best-practices-for-using-workload-identity-federation)
- [Google keyless-auth blog](https://cloud.google.com/blog/products/identity-security/enabling-keyless-authentication-from-github-actions)
- [GitHub OIDC for GCP](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-google-cloud-platform)
- [GitHub App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
- [GHEC enterprise installation automation, July 2025](https://github.blog/changelog/2025-07-01-enterprise-level-access-for-github-apps-and-installation-automation-apis/)
- [OWASP Top 10 for Agentic Applications 2025-12-09](https://genai.owasp.org/2025/12/09/owasp-top-10-for-agentic-applications-the-benchmark-for-agentic-security-in-the-age-of-autonomous-ai/)
- [Spacelift cloud provider integrations](https://docs.spacelift.io/integrations/cloud-providers/aws)
- ADR-0006 (Secret naming convention) — establishes kebab-case canon used by `grant-autonomy.sh` sync step.
- `tools/grant-autonomy.sh` — the script itself.
- `docs/bootstrap-state.md` — current handshake state.
