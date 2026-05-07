# ADR-0009: Railway mutation workflow — autonomous projectCreate / serviceCreate / serviceConnect

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Claude Code (build agent), session `claude/adr-0009-railway-mutation`

## Context and Problem Statement

ADR-0008 split Railway provisioning into a read-only probe (state A/B/C classification) and a deferred mutation workflow. The probe ran live on 2026-05-01 (run id `25214901719`) and confirmed **state = C** for the operator's account: authenticated, zero projects. `bootstrap.yml` Phase 3 (`inject-railway-variables`, `bootstrap.yml:303-460`) is therefore stuck — its `variableCollectionUpsert` calls are gated on four GitHub Variables (`RAILWAY_PROJECT_ID`, `RAILWAY_ENVIRONMENT_ID`, `RAILWAY_N8N_SERVICE_ID`, `RAILWAY_AGENT_SERVICE_ID`) that nothing in the repo currently produces.

ADR-0007 forbids any operator action beyond the one-time `tools/grant-autonomy.sh`, so the build agent must own the mutation path end-to-end: create the project, capture the auto-generated `defaultEnvironment.id`, create both services, connect them to this repo, poll for service domains, and finally write the four Variables back to GitHub.

## Decision Drivers

- **ADR-0007 inviolability** — zero new operator asks. The four GitHub Variables that gate Phase 3 must be written by a workflow, not by hand.
- **Idempotency** — re-running the workflow on a working system (state A) must be a no-op except for re-asserting the Variables. State B must only fill in the missing services, not duplicate the project.
- **No destruction** — if `projectCreate` returns a duplicate-name error, the workflow must surface the diagnostic and stop. Never delete-and-retry.
- **Cloudflare 1010 immunity** — every Railway API call must send `User-Agent: autonomous-agent-template-builder/1.0` plus `Accept: application/json`. Proven live by the probe; the bootstrap.yml Phase-3 calls were patched in ADR-0008's PR for the same reason.
- **Two-step service creation** — Railway's inline `source.repo` field on `serviceCreate` is unreliable (per ADR-0008 research). The supported pattern is `serviceCreate(input: { projectId, name })` followed by `serviceConnect(id, repo, branch)`.
- **GitHub Variables write authority** — the same `GH_ADMIN_TOKEN` secret already used by `bootstrap.yml:271-302` is the only existing token with `actions:write` scope. Reuse it; do not introduce a new credential.

## Considered Options

1. **Option A — Inline state-C-only flow.** Hard-code the full-provision path; refuse to run if the probe reports A or B.
   *Rejected* because state B is the natural mid-recovery case (e.g. project create succeeded, first service create failed) and the workflow must be safely re-runnable from any partial state.
2. **Option B — Probe-then-mutate, in-process classification (chosen).** A single workflow runs the same `me` query the probe runs, classifies into A/B/C, and dispatches the right mutations from the same Python script. The probe workflow remains as a standalone diagnostic.
   *Chosen* because it eliminates inter-workflow state plumbing, keeps the mutation path idempotent, and reuses the proven probe code.
3. **Option C — Terraform Railway provider.** Adopt `terraform-community-providers/railway` and let `terraform apply` own the resource graph.
   *Rejected* for now: the provider is community-maintained, requires a Railway token in tfstate, and adds a new authentication path. The 60-line Python script we already trust (probe) is closer to the system's spine. Reconsider once Railway publishes a first-party provider.

## Decision Outcome

**Chosen option:** Option B (probe-then-mutate, single workflow).

### Workflow contract — `apply-railway-provision.yml`

- Trigger: `workflow_dispatch` (mutate) + `pull_request` on the workflow file (probe-only self-register).
- Inputs: none. Idempotent re-run is the recovery model.
- Auth: `secrets.RAILWAY_API_TOKEN` (account token) + WIF (`vars.GCP_WORKLOAD_IDENTITY_PROVIDER`) for Secret Manager writes.
- Permissions block: `contents: read` + `id-token: write` (WIF token exchange). No `actions: write` because the storage backend moved off GitHub Variables — see "Live drift" amendment below.

### Execution sequence

1. Run `me { projects { id name services { edges { node { id name } } } environments { edges { node { id name } } } } }` to classify state.
2. Branch on classification:
   - **State C (zero projects, or no project named `${RAILWAY_PROJECT_NAME:-autonomous-agent}`):**
     a. `projectCreate(input: { name: "autonomous-agent" })`. Capture `id`, `defaultEnvironment.id`.
     b. For each of `n8n`, `agent`: `serviceCreate(input: { projectId, name })`. Capture `id`.
     c. For each created service: `serviceConnect(id, input: { repo: "edri2or/autonomous-agent-template-builder", branch: "main" })`.
     d. Poll `service { id serviceInstances { edges { node { domains { serviceDomains { domain } } } } } }` for each service, up to 5 minutes (10 attempts, 30s spacing). Surface what we observe; absence of a domain is **not** a hard failure (env vars haven't been injected yet, so the first deploy may legitimately fail to expose a domain).
   - **State B (project exists, services missing):** Skip step (a). Run (b)–(d) only for services not present in `project.services`.
   - **State A (both services exist):** Skip (a)–(c). Adopt the existing IDs.
3. Write four IDs to GCP Secret Manager (kebab-case canon, ADR-0006): `railway-project-id`, `railway-environment-id`, `railway-n8n-service-id`, `railway-agent-service-id`. `gcloud secrets create … || true` (create-or-swallow) followed by `gcloud secrets versions add …`. (Was: GitHub Variables. See "Live drift" amendment below for the why.)
4. Append a structured outcome to `$GITHUB_STEP_SUMMARY`: starting state, mutations performed, IDs captured, polling result. Mirror the same JSON to a `::notice::` annotation so it surfaces via the check-runs API even when the step-summary blob is unreachable (lesson from ADR-0008).

### Failure semantics

| Failure | Workflow behaviour |
|---------|--------------------|
| HTTP 4xx from `me` (auth) | Hard fail with the response body in `::error::` and step summary. |
| `projectCreate` returns a duplicate-name error | Hard fail. Do **not** delete; surface IDs of the existing project. Manual ADR amendment required to override. |
| `serviceCreate` partial success (one of two) | Continue. The next run picks up state B and creates only the missing one. |
| `serviceConnect` failure | Hard fail for that service. The service exists; manual diagnosis required (likely repo permission). The next run will see the service but no domain — re-attempting `serviceConnect` is safe per Railway docs. |
| `serviceDomain` polling timeout | Soft fail. Log the diagnostic; still write the IDs. Phase 3 of `bootstrap.yml` will redeploy after env vars land. |
| GitHub Variable write fails | Hard fail. The whole point is to set those Variables; no fallback. |

### HTTP header contract (binding)

Every Railway GraphQL call from this workflow MUST send:

```
Authorization: Bearer ${RAILWAY_API_TOKEN}
Content-Type:  application/json
Accept:        application/json
User-Agent:    autonomous-agent-template-builder/1.0 (+apply-railway-provision.yml)
```

Cloudflare 1010 is the first thing the workflow would hit otherwise (proven live, ADR-0008).

### Consequences

**Good:**

- Closes the Phase 3 gap in `bootstrap.yml` autonomously. After this workflow runs once on a fresh clone, `bootstrap.yml` is fully self-bootstrapping end-to-end.
- Idempotent across A/B/C; safe to re-run on partial failure without operator triage.
- Surfaces every diagnostic via both step summary and workflow annotation, so a sandbox without blob-storage access can still see what happened.
- No new credentials introduced. Reuses `RAILWAY_API_TOKEN` + `GH_ADMIN_TOKEN`.

**Bad / accepted trade-offs:**

- The classification is re-run inside the mutation workflow rather than passed as an input from `probe-railway.yml`. This duplicates the `me` query but keeps the probe a pure read-only tool and avoids inter-workflow state plumbing.
- `serviceConnect` triggers an immediate Railway deploy that will fail because env vars are not yet present. This is benign — Railway re-deploys automatically once `bootstrap.yml` Phase 3 injects them.
- The workflow holds a Railway account token at runtime (already true for `bootstrap.yml`), so the secret-exfil blast radius is unchanged. Mitigation: GitHub Actions log masking via `::add-mask::` is unnecessary here because the script never echoes `RAILWAY_API_TOKEN`.

### Live drift discovered post-merge — classifier + storage backend pivot

Two compounding problems surfaced across runs `25215551564` and `25215937519`
that drove a significant amendment:

**1. `me.projects` is personal-scope only.**
`projectCreate(input: { workspaceId, ... })` creates a project under the
workspace, NOT under the user's personal scope. The classifier was reading
only `me.projects` and so missed every project it had just created — each
re-run classified `state=C` and called `projectCreate` again. After two runs
we had two `autonomous-agent` orphans (`d6564477-…`, `ff709798-…`) plus the
post-fix project. **Fix:** the classifier now queries both `me.projects`
AND `me.workspaces[*].projects { edges { node {…} } }`, dedupes by `id`,
and disambiguates duplicate `autonomous-agent` candidates by picking the one
with the most services (recovery from the orphans created during this very
debugging cycle, no destructive cleanup per the failure-semantics table).

**2. GitHub Variables write is not autonomous.**
The endpoint `PATCH /repos/.../actions/variables/{name}` returns
`Resource not accessible by integration` (403) for `GITHUB_TOKEN`, even with
`actions: write`. The required permission is `Variables: write` (a
fine-grained PAT permission) or `actions_variables:write` (a GitHub App
permission); neither is grantable to `GITHUB_TOKEN` via the workflow
`permissions:` block. Since ADR-0007 forbids asking the operator to
provision a PAT, **storage moves from GitHub Variables to GCP Secret
Manager** under kebab-case canon (ADR-0006). The runtime SA already has
`secretmanager.admin`. New secret containers:

- `railway-project-id`
- `railway-environment-id`
- `railway-n8n-service-id`
- `railway-agent-service-id`

**3. Polling re-runs were wasted.**
The original implementation polled `serviceDomain` for every adopted
service. On state-A runs that's 10 minutes of polling for services we know
will still lack a domain (env vars only land via Phase 3). Fix: only poll
newly-created services.

`bootstrap.yml` Phase 3 now reads the four IDs from Secret Manager
alongside `n8n-encryption-key` etc., gates `inject-railway-variables` on
`steps.secrets.outputs.railway_*_service_id != ''`, and removes the
`vars.RAILWAY_*` references entirely.

The two orphan projects created during debugging remain in Railway
indefinitely — non-destructive per ADR-0009 failure semantics. They have
no env vars and so cannot deploy successfully, so they consume zero
Railway credits.

### Live success of state-C path + `GH_ADMIN_TOKEN` fallback (post-merge run 25215551564)

The second post-merge dispatch (commit `7f5cc9d`) succeeded on every Railway
mutation: `projectCreate` returned id `d6564477-8b64-4efd-a7ed-6ee9e5a3abe5`;
`serviceCreate` returned ids `beba6729-206f-479a-8d4f-8bf042cfc815` (n8n) and
`b1fa2044-fd47-4f34-8855-149247c4268c` (agent); both `serviceConnect` calls
succeeded. The `serviceDomain` polling soft-failed as expected — Phase 3 has
not injected env vars yet, so the first deploy can't surface a domain.

The run hard-failed at the GitHub Variable write step: `secrets.GH_ADMIN_TOKEN`
is not provisioned in this repo. ADR-0007 forbids asking the operator to set
it. The workflow now falls back to `github.token` (with `actions: write`
permission added to the job) — this is sufficient for the
`/repos/.../actions/variables` endpoint per GitHub's docs and keeps the
provisioning fully autonomous.

Re-running the workflow now classifies `state=A` (both services present) and
writes the four Variables without any further mutations.

### Live drift discovered post-merge — `workspaceId` required

First post-merge dispatch (run id `25215413434` on commit `d24b4e3`) failed with:

```
{"errors":[{"message":"You must specify a workspaceId to create a project",
"path":["projectCreate"],"extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}
```

`projectCreate(input: { name })` is no longer sufficient — Railway's GraphQL
schema now requires `workspaceId` on the `ProjectCreateInput`. The personal
account exposes its workspace via `me.workspaces`, which is a plain
`[Workspace!]!` list (not the Relay Connection shape `me.projects` uses —
validated against the live schema in run `25215473224`, which 400'd on
`Cannot query field "edges" on type "Workspace"`). The workflow now
(a) fetches `me.workspaces { id name }` in the same probe query,
(b) hard-fails with a diagnostic if no workspace is present, and
(c) passes `workspaceId: workspaces[0].id` to `projectCreate`.

This is the same class of vendor-side drift as the Cloudflare 1010 UA
lesson from ADR-0008 — the fix lands as a follow-up commit on the
`apply-railway-provision.yml` mutation path; no schema change to the rest
of the workflow.

## Validation

The workflow self-validates by writing the four GitHub Variables and surfacing them in the step summary. Acceptance test sequence:

1. `mcp__github__update_pull_request` / `gh workflow run apply-railway-provision.yml` on `main` (after PR merge).
2. Inspect `$GITHUB_STEP_SUMMARY`: must contain a `Result: state=C` line, four `::notice::` lines confirming each Variable upsert, and the captured IDs.
3. Inspect `gh api /repos/edri2or/autonomous-agent-template-builder/actions/variables`: the four `RAILWAY_*` Variables must be present with non-empty values.
4. Re-run the workflow: must report `state=A`, no mutations, idempotent re-write of the Variables.
5. Dispatch `bootstrap.yml` with `skip_terraform=true`, `skip_railway=false`, `dry_run=false`. The `inject-railway-variables` job must complete with both `Inject n8n service variables` and `Inject agent service variables` reporting `✅ … injected (atomic variableCollectionUpsert)`.

## Links

- ADR-0007 — Inviolable Autonomy Contract (`docs/adr/0007-inviolable-autonomy-contract.md`)
- ADR-0008 — Railway provisioning (probe-then-provision) (`docs/adr/0008-railway-provisioning.md`)
- `.github/workflows/probe-railway.yml` — read-only probe (state classifier)
- `.github/workflows/bootstrap.yml:303-460` — Phase 3 consumer of the IDs
- [Railway docs — Manage Services](https://docs.railway.com/integrations/api/manage-services)
- [Railway docs — Manage Projects](https://docs.railway.com/integrations/api/manage-projects)
- [Railway Help Station — `serviceCreate` "Problem processing request"](https://station.railway.com/questions/help-problem-processing-request-when-ecb49af7)
