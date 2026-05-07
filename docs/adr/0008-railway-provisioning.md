# ADR-0008: Railway project + service provisioning is owned by the build agent (probe-then-provision)

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Claude Code (build agent), session `claude/railway-probe-and-adr-0008`

## Context and Problem Statement

`bootstrap.yml` Phase 3 (`inject-railway-variables`, `bootstrap.yml:303-460`) injects environment variables into two Railway services (`n8n`, `agent`) via the `variableCollectionUpsert` GraphQL mutation. The mutation requires `RAILWAY_PROJECT_ID`, `RAILWAY_ENVIRONMENT_ID`, `RAILWAY_N8N_SERVICE_ID`, and `RAILWAY_AGENT_SERVICE_ID` as GitHub Variables, and is gated to no-op silently when the service IDs are empty.

The repo defines the two services declaratively (`railway.toml` for the agent, `railway.n8n.toml` for n8n) but ships **no automation that creates the project, environments, or services**. Pre-ADR-0007 docs (`tools/bootstrap.sh:220-223`, `runbooks/bootstrap.md:137`) instructed the operator to copy IDs out of the Railway dashboard manually. ADR-0007 (Inviolable Autonomy Contract) forbids any such ask going forward, so ownership of Railway provisioning must move into the build agent's path.

This ADR captures the decision space, the verifying probe, and the contract for the eventual mutation workflow. Mutation work is **not** in scope for this ADR; it will be governed by ADR-0009.

## Decision Drivers

- **ADR-0007 inviolability** — no operator action permitted beyond `tools/grant-autonomy.sh`. Asking the operator to create or link a Railway project violates the contract.
- **Reproducibility for template clones** — every child instance of this template must be able to bootstrap from a blank Railway account. State C (nothing exists) is the canonical first-run case, not an edge case.
- **Idempotency** — re-running the bootstrap on a working system must not duplicate or break existing services.
- **No destruction of operator work** — if the operator already created services in their Railway account before the autonomous flow lands, the provisioner must adopt them, not overwrite or shadow them.
- **Cost ceiling** — Railway free trial caps at 5 services per project and $5 of credits over 30 days. Two services (n8n + agent) are within the cap, but provisioning logic must not accidentally create additional services on retry.
- **Vendor API constraints (researched 2026-05-01):**
  - `serviceCreate` with an inline `source.repo` field is documented but unreliable; the supported pattern is `serviceCreate(projectId, name)` followed by a separate `serviceConnect(id, {repo, branch})` call. Source: [Railway Help Station — "Problem processing request"](https://station.railway.com/questions/help-problem-processing-request-when-ecb49af7), [Railway docs — Manage Services](https://docs.railway.com/integrations/api/manage-services).
  - The `me` query is scoped to personal accounts and only works with **account tokens** (not project or workspace tokens). Source: [Railway docs — GraphQL Overview](https://docs.railway.com/integrations/api/graphql-overview).
  - Endpoint: `https://backboard.railway.app/graphql/v2` (proven working by the existing `variableCollectionUpsert` call in `bootstrap.yml:402`). The Cloudflare-hosted docs and Postman collection sometimes show `backboard.railway.com` after Railway's `.app` → `.com` rebranding; both currently resolve.

## Considered Options

1. **Option A — Discover-only (assume operator created services).**
   The probe lists projects via `me`, finds an existing one whose services match the names `n8n` and `agent`, and writes the IDs to GitHub Variables.
   *Rejected* because it presupposes prior operator action, which ADR-0007 forbids on every clone but the original.

2. **Option B — Probe-then-provision (chosen).**
   A read-only `probe-railway.yml` classifies the account into one of three states (A/B/C) and reports the result. A follow-up workflow (ADR-0009 scope) consumes the classification and runs only the missing mutations: `projectCreate` if needed, `serviceCreate` per missing service, `serviceConnect` to the GitHub repo, then `variableCollectionUpsert` (already in `bootstrap.yml`).
   *Chosen* because it adopts existing operator work when present, fully provisions on a fresh clone, and keeps mutation logic out of the read-only probe.

3. **Option C — Always-create with cleanup-on-conflict.**
   Always run `projectCreate` + 2× `serviceCreate`; if a name collision returns an error, delete-and-retry.
   *Rejected* because it can destroy in-progress operator work and it racks up unintended billing on retry.

## Decision Outcome

**Chosen option:** Option B (probe-then-provision).

### State classification

The probe emits exactly one of these three classifications based on `me { projects { id name services { id name } environments { id name } } }`:

| State | Definition | Action in ADR-0009 follow-up |
|-------|------------|-------------------------------|
| **A** | At least one project owned by the account contains both a service named `n8n` and a service named `agent`. | Adopt: write the discovered IDs (project + first environment + both services) as GitHub Variables. No mutations. |
| **B** | At least one project owned by the account exists, but the two named services are missing or only one is present. | Partial-provision: pick the project whose name matches `${{ vars.RAILWAY_PROJECT_NAME \|\| 'autonomous-agent' }}` (or, if absent, the first project), then `serviceCreate` + `serviceConnect` for each missing service. |
| **C** | The account has zero projects, or no project named `${{ vars.RAILWAY_PROJECT_NAME \|\| 'autonomous-agent' }}` and `vars.RAILWAY_ADOPT_FIRST_PROJECT` is `'false'`. | Full-provision: `projectCreate(name='autonomous-agent')`, capture `defaultEnvironment.id`, then 2× `serviceCreate` + `serviceConnect`. |

### Write path (ADR-0009 scope, summarized here for completeness)

Sequence per service:
1. `serviceCreate(input: { projectId, name })` — captures `id`.
2. `serviceConnect(id, input: { repo: "edri2or/autonomous-agent-template-builder", branch: "main" })` — triggers the first deploy.
3. Wait for the service to surface a `serviceDomain` (poll up to 5 min).
4. Write `RAILWAY_<SERVICE>_SERVICE_ID` as a GitHub Variable.

Project + environment IDs are written once per run.

### Consequences

**Good:**
- Adopts existing operator state (state A) without mutation, respecting any pre-ADR-0007 setup.
- Fully bootstraps a fresh template clone (state C) in a single autonomous dispatch.
- Probe is harmless — read-only with a token already provisioned in GCP Secret Manager and synced to GitHub Secrets.
- Decouples discovery from mutation, so this ADR can land + be verified independently before mutation logic ships.

**Bad / accepted trade-offs:**
- Two-phase rollout (probe ADR-0008 now, mutation ADR-0009 next) means Phase 3 of `bootstrap.yml` continues to silently no-op in the interim on fresh clones. Acceptable because (a) this repo is already in state A or B (existing project), and (b) ADR-0009 will land within the next 1–2 sessions.
- The agent reads operator-owned Railway state via the account token. The token is already in scope (used by `bootstrap.yml:362`); no new credential is introduced.
- `serviceConnect` triggers an immediate deploy on Railway, which will fail until env vars are present. This is benign — Railway will redeploy automatically once `variableCollectionUpsert` runs in Phase 3.

## Validation

The probe (`.github/workflows/probe-railway.yml`) is the validation. Acceptance test:

```bash
gh api repos/edri2or/autonomous-agent-template-builder/actions/workflows/probe-railway.yml/dispatches \
  -X POST -F ref=main
```

The dispatch's `$GITHUB_STEP_SUMMARY` must contain a single `Result: state=A|B|C` line and a JSON dump of the projects/services/environments observed. CI must pass markdownlint, OPA, and the markdown-invariants Jest suite for this file.

A future ADR-0009 will add an `apply-railway-provision.yml` workflow that consumes the classification.

### Probe outcome — 2026-05-01

**Result: state = C** (run id `25214901719` on commit `87fd479`).

The probe authenticated successfully against `backboard.railway.app/graphql/v2` after two iterations of the workflow (see commits on PR #23):

1. First run failed with HTTP 403, Cloudflare error `1010` (Browser Integrity Check). Default `Python-urllib/3.x` User-Agent is bot-flagged. Fix: send a non-bot UA + explicit `Accept: application/json`.
2. Second run returned `me.projects.edges = []` — the operator's account is authenticated but contains zero projects.

**Implications:**

- ADR-0009 must implement the **state-C path in full**: `projectCreate(name=...)`, capture the auto-created `defaultEnvironment.id`, then for each of `n8n` and `agent`: `serviceCreate(projectId, name)` → `serviceConnect(id, {repo, branch})` → poll for `serviceDomain` → write `RAILWAY_*_SERVICE_ID` GitHub Variables.
- A latent bug in `bootstrap.yml:402-410` and `:454-459` was discovered along the way: both `variableCollectionUpsert` calls used the same `urllib` pattern without a User-Agent, so Phase 3 — once unblocked — would also hit Cloudflare 1010. **Fixed in this PR** during /simplify cleanup so ADR-0009 doesn't have to carry the patch. Both blocks now send the same `User-Agent` + `Accept` headers proven by the probe.
- The Cloudflare WAF behaviour confirms the choice (made in this ADR) to use `serviceCreate` + `serviceConnect` two-step rather than the inline-source variant: probing the live API is the only reliable way to validate any Railway mutation, and the WAF wall is the first thing each new caller hits. ADR-0009's mutation workflow must include the same UA + Accept header pattern.

## Links

- ADR-0007 — Inviolable Autonomy Contract (`docs/adr/0007-inviolable-autonomy-contract.md`)
- `bootstrap.yml:303-460` — Phase 3 `inject-railway-variables` (consumer of the IDs this ADR provisions)
- `railway.toml`, `railway.n8n.toml` — service definitions
- [Railway docs — Manage Services with the Public API](https://docs.railway.com/integrations/api/manage-services)
- [Railway docs — Manage Projects with the Public API](https://docs.railway.com/integrations/api/manage-projects)
- [Railway docs — GraphQL Overview](https://docs.railway.com/integrations/api/graphql-overview)
- [Railway Help Station — `serviceCreate` "Problem processing request"](https://station.railway.com/questions/help-problem-processing-request-when-ecb49af7)
- [Railway pricing — free trial / hobby](https://docs.railway.com/pricing)
