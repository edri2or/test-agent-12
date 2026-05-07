# Postmortem: Session Autonomy Failures — 2026-05-03

**Session:** `claude/fix-app-automation-viXXj` → `claude/session-postmortem-autonomy-fixes`
**Agent:** Claude Code (claude-sonnet-4-6)
**Severity:** HIGH — agent repeatedly delegated work back to the operator that it was contractually obligated (ADR-0007) to handle autonomously, and caused direct infrastructure damage.

---

## Executive Summary

This session fixed two real bugs (n8n crash from `N8N_PROTOCOL=https`, encryption key rotation on re-runs) and shipped three PRs. It also introduced a **new infrastructure bug** by running `apply-railway-provision.yml` against `or-test-agent-02` without validating that the account-level Railway token could actually see the project — the workflow saw state-C, created a new Railway project, and overwrote correct Secret Manager IDs with incorrect ones.

Beyond the infrastructure damage, the agent violated ADR-0007's autonomy contract in three systematic and recurring patterns: asking the operator to report run completion status, asking for screenshots to learn service state, and directing the operator to read workflow logs. Each of these represents work the agent can and must do via API. None of them required human action.

---

## Incident Timeline

| Time | Event |
|------|-------|
| Session start | n8n CRASHED in Railway — `N8N_PROTOCOL=https` root cause found, PR #95 opened |
| PR #95 merged | n8n ACTIVE — but agent service offline |
| PR #96 opened | Phase 5 auto-deploy + idempotency fix for encryption key |
| `/simplify` run | PR #96 cleaned, merged |
| First redispatch | bootstrap on test-agent-02 with **old** `bootstrap.yml` — succeeded, but rotated key |
| Fix applied | New `bootstrap.yml` pushed to test-agent-02 |
| Second redispatch | Failed at "Inject n8n service variables" — Railway API rejected call |
| `apply-railway-provision` dispatched | **Agent error:** created new Railway project over existing valid one; corrupted Secret Manager IDs |
| Third + fourth redispatch | Failed — project token now mismatches new IDs |
| Diagnosis | `railway-project-token` (for original project) + new `railway-project-id` = mismatch |
| Session end | or-test-agent-02 abandoned; postmortem written |

---

## Autonomy Failure Analysis

### Failure 1: "תודיע לי כשמסתיים" — Polling delegated to operator

**Instances:** Occurred after every `workflow_dispatch` call this session (at least 6 times).

**What happened:** After dispatching a workflow via the GitHub API, the agent wrote "tell me when it's done" and waited for the operator to report completion.

**Why this is wrong:** The GitHub REST API has a complete polling surface. The agent dispatched the workflow, so it has the timestamp and can retrieve the run. Since February 2026, the GitHub API supports `return_run_details=true` on the dispatch endpoint, which returns the `run_id` immediately with no race condition. Without it, the agent can filter runs by `event=workflow_dispatch&created=>{timestamp}` to find the right run, then poll `GET /actions/runs/{id}` until `status=completed`. This is a solved problem. The operator should never be the polling mechanism.

**Research finding:** GitHub Changelog 2026-02-19: POST `.../dispatches` with `return_run_details: true` returns `{"id": <run_id>, "api_url": "...", "workflow_url": "..."}` with 200 instead of 204. Eliminates the race condition entirely.

**Fix:** All `workflow_dispatch` calls in `redispatch-bootstrap.yml` and `bootstrap.yml` Phase 5 must use `return_run_details: true`, capture the run ID, and poll to completion with a timeout. The agent must report status autonomously — never ask the operator.

---

### Failure 2: "שלח לי צילום מסך" — Service state delegated to operator

**Instances:** At least twice — once for n8n ACTIVE/CRASHED state, once for agent service state.

**What happened:** The agent asked the operator to send a Railway dashboard screenshot to determine whether n8n was ACTIVE or CRASHED.

**Why this is wrong:** Railway exposes a GraphQL API. The `probe-railway.yml` workflow exists precisely to query Railway state autonomously. The agent can also dispatch `probe-railway.yml` directly on the target clone and read its annotations via `GET /repos/{owner}/{repo}/check-runs/{id}/annotations`. Service health is also checkable via HTTP: `curl -sS https://<n8n-domain>/healthz` returns 200 when n8n is up. The operator's eyes are not an API.

**Fix:** After any bootstrap run that modifies Railway services, the agent must autonomously verify service health: (1) dispatch probe-railway.yml on the clone, (2) read annotations, (3) if n8n domain is known, curl `/healthz`. Report result directly. Never ask for a screenshot.

---

### Failure 3: "כנס ללוגים" — Log diagnosis delegated to operator

**Instances:** Multiple — most critically during the `variableCollectionUpsert` failure investigation.

**What happened:** The "Inject n8n service variables" step failed. The agent tried `GET /actions/jobs/{id}/logs`, got `Host not in allowlist` (the signed S3 redirect URL is blocked from the sandbox), and then indicated to the operator to check the logs manually.

**Why this is wrong:** There are three fully autonomous alternatives to raw log access:

1. **GITHUB_STEP_SUMMARY** — scripts write structured output to `$GITHUB_STEP_SUMMARY`. Content is accessible via the Checks API: `GET /repos/{owner}/{repo}/check-runs/{id}` returns `output.summary`. No S3 redirect involved.
2. **Annotations** — `echo "::error::message"` / `echo "::notice::message"` emit structured annotations visible at `GET /repos/{owner}/{repo}/check-runs/{id}/annotations`. These work from the sandbox. Already confirmed — the probe-railway.yml pattern uses this successfully.
3. **Embedded diagnostic output in script** — the inject step's Python script already calls `print("❌ Injection failed:", result)`, but this goes to stdout → raw logs only. Writing the same output to `GITHUB_STEP_SUMMARY` with `open(os.environ["GITHUB_STEP_SUMMARY"], "a")` makes it API-accessible without raw logs.

**The inject step already had `print("❌ Injection failed:", result)` — adding one line to also write to GITHUB_STEP_SUMMARY would have made the Railway response fully readable via the Checks API, with zero operator involvement.**

**Fix:** Every workflow step that can produce a diagnostic failure must write its error output to both stdout AND `$GITHUB_STEP_SUMMARY`. The agent must never surface a "logs blocked" situation to the operator — it must design workflows to be readable via the Checks API.

---

## Infrastructure Damage Analysis

### `apply-railway-provision` — Destructive overwrite of valid Secret Manager IDs

**What happened:** The agent ran `apply-railway-provision.yml` on `or-test-agent-02` as a diagnostic step. The workflow probes Railway using `secrets.RAILWAY_API_TOKEN` (account-level). This token could not see the Railway project for test-agent-02 (the project was provisioned by `apply-railway-spec.yml` using a project-scoped token, possibly in a workspace). The workflow classified state-C (0 projects), created a new Railway project, and wrote new IDs to Secret Manager — overwriting the correct `railway-project-id`, `railway-environment-id`, `railway-n8n-service-id`, and `railway-agent-service-id` with IDs for a project the original `railway-project-token` can't reach.

**Root cause:** `apply-railway-provision.yml` treats state-C as "no project exists" and proceeds to create one. But state-C via an account-level token does NOT mean no project exists — it may mean the project exists in a workspace not visible to that token.

**Guard that was missing:** Before creating a new Railway project under state-C, check whether `railway-project-token` already exists in Secret Manager. If it does, attempt to probe Railway using that token. If successful, the project exists — do NOT create a new one.

**Fix:** Add a pre-creation guard to `apply-railway-provision.yml`:
```python
# Before state-C project creation:
existing_project_token = fetch_optional_secret("railway-project-token")
if existing_project_token:
    ok, body = gql_raw(probe_query, token=existing_project_token)
    if ok and body.get("data", {}).get("me", {}).get("projects", {}).get("edges"):
        annotate_error("Blocked: project-token can reach existing project — account-level token has limited scope. Not creating new project.")
        sys.exit(1)
```

**Additional guard:** Validate that the token being used for the probe query actually matches the scope of the target project before treating a null result as "no project."

---

## Required Fixes — Prioritized

### P0 — Workflow log observability (blocks autonomous diagnosis)

**File:** `bootstrap.yml`, `apply-railway-provision.yml`, all inject/mutate steps  
**Fix:** Every step with a `print("❌ ...")` must also write to `$GITHUB_STEP_SUMMARY` so the Checks API can return the error without raw log access.  
**Code pattern:**
```python
def fail(msg, detail=None):
    print(f"❌ {msg}", detail or "")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
        f.write(f"## ❌ {msg}\n\n```json\n{json.dumps(detail, indent=2) if detail else ''}\n```\n")
    sys.exit(1)
```

### P0 — `apply-railway-provision.yml` project-token guard

**File:** `apply-railway-provision.yml`  
**Fix:** Before state-C project creation, check `railway-project-token` in Secret Manager and probe Railway with it. If reachable → abort creation, annotate with reason.  
**Prevents:** Destructive overwrite of valid IDs when account-level token has limited scope.

### P1 — Autonomous polling after `workflow_dispatch`

**Files:** `redispatch-bootstrap.yml`, `bootstrap.yml` Phase 5 (`trigger-first-deploy`)  
**Fix:** Use `return_run_details: true` in the dispatch API call (GitHub feature since 2026-02-19). Capture `run_id` from the 200 response. Poll `GET /actions/runs/{run_id}` until `status=completed`. Write conclusion to `$GITHUB_STEP_SUMMARY`. Agent reports result autonomously.  
**Eliminates:** "Tell me when it's done" — the agent knows when it's done.

### P1 — Autonomous service health check after bootstrap

**File:** `redispatch-bootstrap.yml` (add post-run health check step)  
**Fix:** After bootstrap completes, dispatch `probe-railway.yml` on the clone repo, poll to completion, read annotations via Checks API, report n8n domain health via `curl /healthz`.  
**Eliminates:** "Send me a screenshot" — the agent checks service state via API.

### P2 — `bootstrap.yml` inject step: GITHUB_STEP_SUMMARY error output

**File:** `bootstrap.yml` lines 523–529 (inject n8n) and lines ~590-595 (inject agent)  
**Fix:** Add `$GITHUB_STEP_SUMMARY` write to the failure branch of `variableCollectionUpsert` check.

---

## CLAUDE.md Additions Required

The following rules must be added to the Forbidden agent outputs section of CLAUDE.md:

- `"Tell me when [workflow] is done"` / `"Let me know when it finishes"` — use `return_run_details: true` + autonomous polling
- `"Send me a screenshot of [service status]"` — use probe workflow + Checks API annotations  
- `"Check the logs for [workflow run]"` — design workflows to write errors to `$GITHUB_STEP_SUMMARY`; read via Checks API
- Running any mutating workflow (`apply-railway-provision`, `terraform apply`, etc.) against a clone without first verifying current state with a read-only probe and checking for conflicting signals (e.g., existing project token)

---

## Research Sources Applied

| Finding | Applied to |
|---------|-----------|
| GitHub `return_run_details: true` (2026-02-19 changelog) | P1 polling fix |
| GITHUB_STEP_SUMMARY accessible via Checks API without raw log redirect | P0 observability fix |
| GCP Secret Manager: `versions list` before `versions add` as guard pattern | P0 apply-railway guard |
| Railway GraphQL: no public return-type docs → must emit response to GITHUB_STEP_SUMMARY | P0 + P2 inject fix |
| OWASP Agentic Top 10: "Visibility over delegation" — human oversight via logs/summaries, not polling humans for status | ADR-0007 reinforcement |

---

## What Would Have Prevented Every Failure

1. **Autonomous polling**: one `return_run_details: true` parameter on every dispatch call.  
2. **GITHUB_STEP_SUMMARY on every failure branch**: the inject step failure would have been diagnosed in one API call.  
3. **Project-token guard on apply-railway-provision**: the destructive overwrite would have been blocked before execution.  

None of these require operator involvement. All are implementable in the same sessions that introduced the bugs. The pattern of delegating status, logs, and health checks to the operator is not a UX choice — it is a contract violation (ADR-0007 §Forbidden agent outputs).
