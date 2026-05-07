# ADR-0011: Adopt the silo isolation pattern (Project Factory + Cloudflare parameterization + Telegram Managed Bots)

**Date:** 2026-05-01
**Status:** Accepted. §1 (Phase C, PR #32), §2 (Phase B, PR #31), §4 + §5 (Phase A, PR #30) — shipped. **§3 (Phase D) deferred** — Telegram's Bot API 9.6 vendor floor still requires a per-clone confirmation tap; deferred until vendor surfaces a fully programmatic path. See "Implementation phases" below.
**Deciders:** Operator, Claude Code (build agent), session `claude/adr-0011-silo-isolation-docs`
**Supersedes parts of:** ADR-0010 §1 (operator-brought GCP project) once §1 implementation lands
**Extends:** ADR-0007 (Inviolable Autonomy Contract) — interpretation only, contract spirit preserved

## Context and Problem Statement

The operator's stated architectural goal: **every project created from this template is fully self-contained — its own GitHub repo, its own Railway project, its own GCP Secret Manager (i.e., its own GCP project), its own domain. No cross-clone dependencies.**

The codebase implements this only partially. ADR-0009 + ADR-0010 closed the GCP-project-as-namespace-boundary contract on paper, but the per-clone *creation* of that boundary, the per-clone *naming* of Cloudflare resources, and the per-clone *minting* of a Telegram bot all remain manual or unaddressed. Without these gaps closed, two clones deployed against the same operator account silently overwrite kebab-case secrets in GCP Secret Manager (`telegram-bot-token`, `n8n-encryption-key`, `railway-project-id`, …), collide on Cloudflare account-level Worker names (`autonomous-agent-edge`), collide on hardcoded subdomains (`api`, `n8n`), and share the same Telegram bot's chat traffic.

The standard tenant-isolation taxonomy (AWS SaaS Lens, [silo-pool-bridge](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/silo-pool-and-bridge-models.html)) classifies the operator's stated goal as **silo isolation** — dedicated resources per tenant, strongest blast-radius separation, recommended for "products in regulated space" or "tenants who demand strict data isolation". This ADR adopts the silo pattern across all auto-soluble resources.

## Decision Drivers

- **Operator demand for full isolation per clone** (verbatim, prior session): "כל פרויקט שנוצר מהטמפלט - מקבל: ריפו משלו, פרוייקט בריילוואי משלו, פרוייקט בסיקרט מנג'ר משלו, כתובת דומיין משלו… כל פרוייקט הוא עצמאי פני עצמו ללא תלות בשום פרוייקט אחר."
- **Industry-canonical patterns exist for every resource we need to isolate.** Each of GCP, Cloudflare, and Telegram has a published, vendor-blessed mechanism for the silo pattern; we are not inventing anything.
- **ADR-0007 inviolability.** The "single permitted operator action" must be preserved at *per-clone* granularity. One-time global setup (org-level grants, manager-bot creation, Cloudflare zone creation) falls under "pre-existing operator state" already covered by ADR-0007 §Decision Drivers / line 17.
- **ADR-0006 kebab-case canon.** Secret names stay un-prefixed; isolation comes from the GCP project boundary, not from name prefixes. This is the lesson of ADR-0010 §3 (rejected per-secret prefix option) and remains binding.
- **Linear is vendor-blocked.** The Linear GraphQL API has no `createWorkspace` mutation ([Linear API docs](https://linear.app/developers/graphql)). This is the only resource in the inventory that cannot be auto-isolated; documented explicitly in §4.

## Considered Options

1. **Option A — Pool model (shared GCP project, per-secret prefix).** Reject. Already analyzed and rejected in ADR-0010 §3: breaks ADR-0006 kebab-case canon, complicates every consumer, weakens IAM blast-radius.
2. **Option B — Bridge model (some resources silo, some pool).** Pragmatic but ambiguous; would require a per-resource policy that drifts. Reject in favor of explicit silo-everywhere with one named vendor exception (Linear).
3. **Option C — Full silo (chosen).** Adopt the canonical per-vendor isolation mechanism for each resource, document Linear as the lone exception.

## Decision Outcome

**Chosen option:** C. The four sections below are each independently accepted decisions; the implementation phases (A/B/C/D below) determine merge order.

### §1 — GCP Project Factory adoption (Status: Accepted, Implementation: shipped in Phase C PR)

**Decision:** `tools/grant-autonomy.sh` extends to auto-create the GCP project for each clone. The operator no longer creates projects in the GCP Console.

**Implementation note (Phase C):** instead of invoking the `terraform-google-modules/terraform-google-project-factory` module, the script calls `gcloud projects create` + `gcloud billing projects link` directly in bash. This avoids the chicken-and-egg of "create the project" vs. "create the GCS Terraform state bucket inside the project" (the script also creates the state bucket, then `terraform init` later in `bootstrap.yml` Phase 2 reads from it). The bash equivalent is functionally the same as the module — both end with a project that has billing linked and APIs enabled. The terraform-google-project-factory module remains the recommended path for org-level multi-project scaffolding, which is out of scope for this template.

**Mode contract:**
- If `GCP_PROJECT_ID` already exists in GCP → use it (back-compat with ADR-0010 manual mode; non-destructive).
- If not → require `GCP_BILLING_ACCOUNT` plus one of `GCP_PARENT_FOLDER` / `GCP_PARENT_ORG`; the script creates the project under the specified parent and links the billing account.
- Idempotent: re-running on an already-created project is a no-op.

**Required one-time operator pre-grant** (NOT per clone):
- `roles/resourcemanager.projectCreator` on parent org/folder
- `roles/billing.user` on the billing account
- `roles/resourcemanager.organizationViewer` (org level)
- `roles/resourcemanager.folderViewer` (if using a folder)

These permissions are granted once to the operator's user account or to a "factory SA" that owns clone-creation across the operator's org. Per ADR-0007 §Decision Drivers / line 17, this is "pre-existing operator state" — the operator already has `roles/owner` on the parent org/folder; granting these specific sub-roles to a factory SA is the same class of action as creating a Cloudflare zone.

**Files in Phase C PR:** `tools/grant-autonomy.sh`, new `terraform/project-factory.tf`, `terraform/variables.tf`, `terraform/gcp.tf`, `docs/runbooks/bootstrap.md`.

### §2 — Cloudflare parameterization (Status: Accepted, Implementation: shipped in Phase B PR #31)

**Decision:** Every clone gets unique Cloudflare resource names — its own subdomains, its own Worker name — within the operator's shared Cloudflare zone. No upgrade to Cloudflare for SaaS / Workers for Platforms is required for the MVP; the parameterization closes the collision risk.

**Naming contract:**
- DNS records: `${var.clone_slug}-api.<zone>` and `${var.clone_slug}-n8n.<zone>`.
- Worker: `${var.clone_slug}-edge`.
- `clone_slug` is derived from `${{ github.event.repository.name }}` and passed as a Terraform variable + as `CLONE_SLUG` env var to `wrangler` via `envsubst`.

**Optional future upgrade (not in this ADR):** migrate to [Cloudflare for SaaS Custom Hostnames API](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/create-custom-hostnames/) when per-clone certificate isolation becomes a requirement.

**Files in Phase B PR:** `terraform/cloudflare.tf`, `terraform/variables.tf`, `wrangler.toml`, `.github/workflows/deploy.yml`, `.github/workflows/bootstrap.yml`.

### §3 — Telegram Managed Bots migration (Status: Deferred — vendor floor)

**Phase A draft framing (now superseded):** auto-mint a per-clone Telegram child bot via [Bot API 9.6 Managed Bots](https://core.telegram.org/bots/api-changelog) (`getManagedBotToken`), framed as fully programmatic.

**Live re-research (Phase D session, 2026-05-01) overturned the "fully programmatic" framing.** The actual Telegram flow is:

1. Manager-bot owner constructs `https://t.me/newbot/{manager_bot}/{suggested_username}`.
2. **Recipient must tap the link, then tap "Create"** in the pre-filled Telegram dialog.
3. Telegram sends a `managed_bot` webhook update; manager bot then calls `getManagedBotToken` to retrieve the new bot's token.

Per Telegram's stated policy ([core.telegram.org/bots/api-changelog](https://core.telegram.org/bots/api-changelog), [aiia.ro summary](https://aiia.ro/blog/telegram-managed-bots-create-ai-agents-two-taps/)): *"Telegram requires explicit approval before any managed bot is created — anti-abuse."* The tap is non-removable.

**Implication.** "Per-clone bot creation" reduces from a multi-step @BotFather conversation to **one tap per clone**, but does not become fully autonomous. This contradicts the silo-isolation goal of "operator action = once globally, never per clone".

**Decision: defer Phase D.** Treat Telegram bot creation the same way ADR-0011 §4 treats Linear workspace creation — vendor-blocked silo isolation. R-04's status remains "the API feature exists and is real" but its classification reverts from `AUTOMATABLE_VIA_BOT_API_9.6` (Phase A's over-claim) to `HITL_TAP_REQUIRED_PER_CLONE`.

**What stays valid:**

- The current operator-provided `telegram-bot-token` flow (ADR-0010 contract) remains the working path. No code changes in this deferral PR.
- Any future implementation can scaffold the 1-tap flow (deep link + poll for `getManagedBotToken`) — outline preserved below for the eventual unblocking ADR.
- n8n workflows (`src/n8n/workflows/*.json`) need ZERO changes either way — they read `TELEGRAM_BOT_TOKEN` env var; the value source (manual today vs. 1-tap-managed in the future) is invisible to the workflow logic.

**Future implementation outline (preserved for the eventual unblocking ADR):**

1. Operator creates one manager bot via @BotFather, enables Bot Management Mode (`can_manage_bots: true`), exports `TELEGRAM_MANAGER_BOT_TOKEN`.
2. `grant-autonomy.sh` (when `TELEGRAM_MANAGER_BOT_TOKEN` is set AND `telegram-bot-token` is missing in GCP) prints a deep link `t.me/newbot/{manager_bot}/{repo_slug}-bot` and polls `getManagedBotToken` until the operator taps Create.
3. Captured token is written to `telegram-bot-token` in GCP (kebab-case canon, ADR-0006 preserved).
4. Same back-compat fallback as today: if no manager bot configured → operator pre-provides `telegram-bot-token`.

**Unblocking trigger:** Telegram surfaces a vendor-API path that mints child bots without a per-bot user tap (e.g., a SaaS-platform-level pre-authorization flow). When this lands, supersede the deferral with a new ADR.

### §4 — Linear gap acknowledgment (Status: Accepted, Implementation: docs in this PR)

**Decision:** Linear has no `createWorkspace` GraphQL mutation. Two acceptable contracts:

- **L-pool (default).** `linear-api-key` is the operator's single workspace key, shared across clones. Acceptable for trust-isolated single-org operators.
- **L-silo (opt-in).** Operator creates a fresh Linear workspace + API key per clone (manually via Linear UI), exports `LINEAR_API_KEY` to `tools/grant-autonomy.sh`. Parallel to the original ADR-0010 GCP contract (now superseded by ADR-0011 §1 for GCP only — Linear retains operator-brought-per-clone semantics).

L-silo is **not** automated in this template; the workspace-create step is irreducibly manual per Linear's vendor surface.

**Net effect:** Linear is the only resource where ADR-0011 does not deliver full silo isolation autonomously. Documented as risk R-10 (this PR).

### §5 — Documentation reconciliation (Status: Accepted, Implementation: docs in this PR)

- ADR-0010 gets a header banner: "Partially superseded by ADR-0011 §1 (Phase C: auto-creation in `grant-autonomy.sh`)." The deferred collision-detection check in ADR-0010 §2 **remains relevant** as a future enhancement: the bash auto-create path of Phase C uses operator-specified project IDs (no random suffix), so a typo or accidental ID reuse across clones can still produce a no-op-then-overwrite race. A safety check in `grant-autonomy.sh` that aborts when the project exists but its `bootstrap-state.md` snapshot belongs to a different repo would close that gap; deferred to a future ADR.
- ADR-0007 interpretation note (this ADR's links section): the "single permitted operator action" stays single **per clone**. The one-time org-level grant + manager-bot creation + Cloudflare zone creation are "pre-existing operator state" (already covered by ADR-0007 line 17).
- R-04 in `docs/risk-register.md` is revised from `DO_NOT_AUTOMATE` to `AUTOMATABLE_VIA_BOT_API_9.6` with status "Implementation pending ADR-0011 §3".
- R-10 (new) — "Linear has no `createWorkspace` API; vendor-blocked silo isolation".

## Implementation phases

| Phase | Sections | PR Branch | Risk | Notes |
|-------|----------|-----------|------|-------|
| A (PR #30, merged) | §4, §5 (docs only) | `claude/adr-0011-silo-isolation-docs` | Trivial | Pure docs: ADR-0011, R-04 status revision, R-10 add, ADR-0010 banner, JOURNEY entry. |
| B (PR #31, merged) | §2 (Cloudflare) | `claude/adr-0011-phase-b-cloudflare` | Low | Self-contained TF + wrangler change. |
| C (PR #32, merged) | §1 (GCP Project Factory) | `claude/adr-0011-phase-c-project-factory` | Medium | `grant-autonomy.sh` extension (`gcloud projects create` + `billing projects link`); ADR-0010 supersession banner update; README + CLAUDE.md HITL row 1 + runbook env-var docs. No new TF module needed (bash equivalent suffices for per-clone single-project path). |
| **D (this PR — deferral)** | §3 (Telegram Managed Bots) | `claude/adr-0011-phase-d-defer` | Docs only | **Deferred — vendor floor**. Phase D session re-research showed Telegram's API 9.6 still requires a per-clone confirmation tap (anti-abuse policy). §3 amended to deferred status; R-04 reclassified to `HITL_TAP_REQUIRED_PER_CLONE`; future-implementation outline preserved for the eventual unblocking ADR. No code changes; existing operator-provided `telegram-bot-token` flow remains the contract. |

Each phase merges independently. The ordering above is by ascending blast radius.

## Consequences

**Good:**
- Full silo isolation achievable autonomously for GCP, Cloudflare, Telegram, Railway, OpenRouter, GitHub App, n8n.
- Aligns with industry-canonical patterns (AWS Account Vending Machine, GCP Project Factory, Cloudflare for SaaS, Telegram Managed Bots).
- ADR-0007 contract preserved at per-clone granularity; org-level pre-grants are one-time global, not per-clone.
- Two clones can coexist on the same operator GCP+Cloudflare+Telegram footprint with zero collision.

**Bad / accepted trade-offs:**
- Operator must perform one-time global pre-grants (org-level GCP roles + manager bot + Cloudflare zone). This is more setup than ADR-0010's "operator brings the project" model, but it amortizes across every future clone.
- Linear remains operator-managed-per-clone for any silo-mode user. No vendor mechanism exists to automate this.
- ADR-0010 §1 is partially superseded once Phase C lands; the deferred safety check there is obsolete (no longer needed since Project Factory generates unique IDs). ADR-0010 banner clarifies this.
- The Cloudflare zone is shared across clones (subdomain-per-clone). Zone-per-clone would require registrar interaction — out of scope; deferred to a future ADR if the operator escalates the requirement.

## Validation

End-to-end test: **create a second clone of the template and run `tools/grant-autonomy.sh` on it.** Expected:

1. New clone's `tools/grant-autonomy.sh` (with §1 + §3 env vars set):
   - Creates a fresh GCP project via Project Factory, links billing.
   - Mints a Telegram child bot via the manager bot's `getManagedBotToken`, writes token to `telegram-bot-token`.
   - WIF pool / SA created in the new project.
   - GitHub Variables set on the new repo.
2. New clone's `bootstrap.yml` dispatch:
   - All ~9 secrets land in the new project's Secret Manager (no collision with original clone's `or-infra-templet-admin`).
   - Phase 3 injects env vars into the new clone's Railway services.
3. New clone's `apply-railway-provision.yml` dispatch:
   - state=C → `projectCreate` on Railway with `workspaceId`, captures new IDs, writes to the new project's `railway-*-id` secrets.
4. New clone's `deploy.yml` dispatch:
   - `envsubst` renders `wrangler.toml` with `name = "<new-clone-slug>-edge"`.
   - Wrangler deploys to Cloudflare under that unique name.
   - DNS records `<new-clone-slug>-api`, `<new-clone-slug>-n8n` appear in the operator's Cloudflare zone.
5. Original clone (`autonomous-agent-template-builder`) is untouched — its secrets, Railway project, Cloudflare records, Worker, Telegram bot all unchanged.

**Acceptance criterion:** both clones operate independently. Killing one (e.g., `gcloud projects delete <new-clone>`) has zero effect on the other.

This PR (Phase A) ships docs only; the validation above kicks in incrementally as Phases B/C/D land. Phase A's own validation: `markdownlint`, `markdown-invariants` Jest, OPA, internal-link checks, all pass on the new + edited markdown.

## Links

- ADR-0006 — Secret naming convention (kebab-case canon, preserved un-prefixed by §1).
- ADR-0007 — Inviolable Autonomy Contract (interpretation note: "single action" = per clone; org-level pre-grants are pre-existing operator state).
- ADR-0009 — Railway mutation workflow (already silo-isolated; consumer of `railway-*-id` secrets that this ADR's GCP-project boundary namespaces).
- ADR-0010 — Clone GCP project isolation (partially superseded by §1 once Phase C lands).
- [AWS SaaS Tenant Isolation Strategies whitepaper](https://d1.awsstatic.com/whitepapers/saas-tenant-isolation-strategies.pdf)
- [AWS Well-Architected SaaS Lens — Silo, Pool, Bridge Models](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/silo-pool-and-bridge-models.html)
- [AWS Control Tower — Account Factory ("vending machine")](https://docs.aws.amazon.com/controltower/latest/userguide/terminology.html)
- [terraform-google-modules/terraform-google-project-factory (Google-official)](https://github.com/terraform-google-modules/terraform-google-project-factory)
- [Cloudflare for SaaS](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/)
- [Cloudflare Custom Hostnames API](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/create-custom-hostnames/)
- [Telegram Bot API changelog (9.6 — Managed Bots, April 2026)](https://core.telegram.org/bots/api-changelog)
- [Linear API GraphQL docs](https://linear.app/developers/graphql) — no `createWorkspace` mutation.
- [oneuptime — Project-per-tenant on GCP (Feb 2026)](https://oneuptime.com/blog/post/2026-02-17-how-to-implement-project-per-tenant-multi-tenancy-on-google-cloud-platform/view)
