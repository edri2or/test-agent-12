# CLAUDE.md — Autonomous Agent Template Builder

## Project Identity

**Repository:** `autonomous-agent-template-builder`
**Template produces:** `autonomous-agent-template`
**Purpose:** Scaffold a secure, autonomous software orchestration platform from this GitHub Template Repository.

### End-state goal (ב)

This template's terminal form is a **runtime agent that accepts a natural-language build spec** ("build me system X") **and provisions every required resource from scratch** under the autonomy contract below — goal **(ב)** in the operator taxonomy: *arbitrary-system provisioning from spec*, distinct from goal (א) *self-cloning of this template*. Goal (א) is operational (ADR-0012 Phase E). Goal (ב) has its scoping ADR ([ADR-0013](docs/adr/0013-spec-language-and-generic-provisioner.md), `Status: Proposed` as of 2026-05-02); the live next step lives in the pinned `current-focus` GitHub Issue.

### Operator communication channel

**Rule:** when the agent legitimately needs an operator decision, the question goes in the **Claude Code chat session** — nowhere else. Issue bodies, JOURNEY entries, and PRs are *audit-trail bookkeeping* (the agent writes to them for the record, including updating issue bodies after a decision lands); they are never the channel through which the agent asks for the next decision.

Never via: GitHub issue threads, PR review comments, repo files, or any other side-channel. Captured 2026-05-02 from explicit operator instruction.

Additive to the ADR-0007 contract — does not loosen it. The agent still avoids asking *anything that should be autonomous* (vendor floors aside); this rule only governs the channel for questions that legitimately reach the operator. See also: §Forbidden agent outputs (the channel-violating phrasings explicitly listed there).

---

## ⚠️ Inviolable Autonomy Contract (ADR-0007)

**Read this section before doing anything else.** It governs every Claude Code session on this repository, without exception. Drift is a contract violation.

### Honest scope (READ FIRST — supersedes the historical "Forever / no clicks" framing)

This contract has a **literal scope** — the GCP trust handshake — and a **broader aspiration** that has been repeatedly mis-framed across sessions. The aspiration is "the operator never touches anything again". That aspiration is **structurally impossible** for a non-trivial subset of the system due to vendor floors documented below. Past sessions promised "Forever / no further setup / no clicks" and then surfaced residuals; that pattern is the contract violation, not the residuals themselves.

**What is genuinely one-time, never asked again on the template-builder repo:**
- `bash tools/grant-autonomy.sh` (the GCP trust handshake — WIF pool/provider/SA).

**What is one-time-global per organization (NOT per clone) — needed only if you adopt ADR-0012's autonomous multi-clone provisioning:**
- §E.1 pre-grants on the runtime SA (one-time-global): three org-level role bindings + **two** billing-account-level direct grants (`billing.user` + `billing.viewer`) + register the **Provisioner GitHub App** via `register-provisioner-app.yml` (supersedes the `gh-admin-token` PAT — see ADR-0014). The billing-account bindings must be performed from the original billing-account-creator's account (the gmail account, not the workspace account) — see ADR-0012 §E.1 for why and `docs/runbooks/bootstrap.md` Path C for the executable commands. `billing.viewer` was added 2026-05-02 after `apply-system-spec.yml` runs 25253910937 / 25254068938 / 25254227982 hit `Cloud billing quota exceeded` and the operator could not see which projects were consuming the quota slots; `billing.user` alone permits link/unlink but NOT `billing.projects.list`. Validated end-to-end 2026-05-01 / 2026-05-02.
- §E.1 OrgPolicy override on the factory folder (one-time-global): `iam.allowedPolicyMemberDomains` set to `allowAll` on the folder containing all clone projects. Required for the Cloud Run receiver (R-07) to grant `allUsers run.invoker` so GitHub OAuth callbacks can reach it. Inherits to all current and future clones. Must be performed from the workspace-admin account (the `or-infra.com` account, not the gmail account) since the folder lives in the Workspace org. Validated end-to-end 2026-05-02 on `folders/667201164106` (factory folder for `autonomous-agent-test-clone-N` clones). See ADR-0012 §E.1.

**What remains forever per child instance — vendor floors, NOT removable by any future ADR:**

| # | Resource | Per-clone operator surface | Vendor source of the floor |
|---|----------|---------------------------|---------------------------|
| 1 | GitHub App | 2 browser clicks ("Create" + "Install") — `installation_id` auto-captured via `/install-callback` redirect; `APP_INSTALLATION_ID` variable updated automatically via Provisioner App token (1 click on GHEC preview) | GitHub policy — manifest flow + OAuth install (ADR-0007 §Two-irreducibly-human; R-07) |
| 2 | Telegram bot | 1 tap per clone (Managed Bots dialog) | Telegram anti-abuse policy (ADR-0011 §3 deferred; R-04) |
| 3 | Linear workspace | UI workspace creation per clone (or use L-pool — share one workspace across clones) | Linear has no `createWorkspace` GraphQL mutation (ADR-0011 §4; R-10) |

**The scope distinction matters.** "Run grant-autonomy.sh once" is the GCP-only handshake — accurate. "The operator is finished forever" is **false** for any clone that uses GitHub App + Telegram + dedicated Linear workspace. Past framings of this contract conflated the two and that drift has cost operator trust. Future sessions MUST distinguish.

### The single one-time GCP trust handshake — for the lifetime of this repo

`bash tools/grant-autonomy.sh` (run once, in GCP Cloud Shell, with `GH_TOKEN` exported). After it succeeds, **the GCP/WIF identity backbone is in place**. Future Claude Code sessions on this repo never request another `grant-autonomy.sh` run.

This does **not** mean the operator is "finished forever" — see the vendor-floor table above. The accurate framing: future Claude sessions may surface vendor-floor touches per child instance (R-04, R-07, R-10), but **never re-ask for the GCP handshake or any of the §E.1 one-time-global pre-grants** once they are in place.

Pre-existing operator state — **never ask the operator to recreate any of these:**
- Telegram bot per clone (R-04 — Bot API 9.6 reduces operator action to 1 tap per clone via Managed Bots, but the tap is non-removable per Telegram's anti-abuse policy. ADR-0011 §3 deferred until vendor surfaces fully programmatic path; existing operator-provided `telegram-bot-token` flow remains the contract.)
- Railway / Cloudflare / OpenRouter / Linear / GCP project / GitHub repo
- All credentials are stored in GCP Secret Manager (kebab-case canon, ADR-0006).

### Session-start verification ritual (mandatory)

Every session, before the first user-visible action, must:
1. Read `docs/bootstrap-state.md` — confirm `GCP_WORKLOAD_IDENTITY_PROVIDER` is non-empty (or check via GitHub MCP `mcp__github__get_file_contents` on `.github/workflows/bootstrap.yml` and the variables endpoint). **Note:** `bootstrap-state.md` is hand-maintained and may drift. The canonical source-of-truth for "what secrets exist in `or-infra-templet-admin`" is the `probe-source-secrets.yml` workflow (autonomy primitive — runs nightly + on-demand). To discover an exact secret name without asking the operator: dispatch `probe-source-secrets.yml` (optionally with a `filter` substring) and read the resulting annotations / step summary. Operators must never be asked "what's the name of secret X?" — the probe answers it autonomously.
2. If granted → proceed with full autonomy (next subsection).
3. If not granted → output exactly: *"GCP autonomy not yet granted. The operator must run `bash tools/grant-autonomy.sh` once. This is the single permitted operator action per ADR-0007."* — then stop.
4. **Clone-side activation check.** If `github.repository != 'edri2or/autonomous-agent-template-builder'`, this is a child clone provisioned via Path C (ADR-0012). Read `docs/runbooks/bootstrap.md` Path D before proceeding to runtime tasks — the clone may need GitHub App registration (R-07), Telegram bot (R-04), and a Linear pool/silo decision (R-10) before it is "activated" per Path D's success criteria. Activation status is detectable via `gcloud secrets list --project=$GCP_PROJECT_ID --filter='name:github-app-id'` (empty → activation pending).
5. **Read the `current-focus` issue (mandatory orientation).** Use `mcp__github__list_issues` with `labels: ["current-focus"]` and `state: "open"`. Treat its **Next Concrete Step** as your default task absent operator override. If zero issues are returned → halt and ask the operator which phase to work on (do NOT invent one). Before session end, if state changed, update the issue body via `mcp__github__issue_write` (method `update`), bumping the **Updated By** line. **Enforced** by the `Stop` hook at `.claude/hooks/enforce-current-focus-fresh.sh` (registered in `.claude/settings.json`): if the most recent local commit is newer than the issue's `updated_at` when the agent tries to stop, the hook returns `decision: "block"` with a reason that forces the agent to update the issue before the session can end. Soft-skip philosophy: the hook respects `stop_hook_active=true` to prevent infinite loops and exits gracefully (no block) when GH_TOKEN / git remote / GNU `date -d` / open `current-focus` issue are unavailable — enforcement is best-effort on non-GNU systems. Hook never wedges a session.
6. **Check for open `workflow-failure` issues.** Use `mcp__github__list_issues` with `labels: ["workflow-failure"]` and `state: "open"`. Each issue was opened automatically by `open-failure-issue.yml` when a monitored workflow failed on `main`. If any are open: investigate the linked run URL, fix the root cause, then close the issue via `mcp__github__issue_write` (method `update`, `state: "closed"`). Treat these as blocking — a broken main pipeline takes priority over feature work unless the operator explicitly overrides. If multiple are open, address the oldest first.

### Permitted agent operations (full autonomy after handshake)

- All GitHub MCP / `gh` CLI: push commits, open PRs, comment, merge, `workflow_dispatch`, write/update repo Secrets and Variables.
- Inspect workflow logs and CI status.
- Trigger `bootstrap.yml`, `deploy.yml`, and any other workflow.
- Mutate GCP, Cloudflare, Railway, n8n, OpenRouter, Linear, Telegram only via workflows that authenticate using WIF or via tokens already stored in GCP Secret Manager. Never via local CLI in your sandbox.
- Edit any file under `src/`, `terraform/`, `policy/`, `.github/workflows/`, `docs/`, `tools/`.

### Forbidden agent outputs (zero tolerance — these are contract violations)

You MUST NEVER emit any of:
- "Run this in Cloud Shell" (except for the one-time GCP handshake or the documented one-time-global §E.1 setup, both of which are pre-merged contracts, not new asks)
- "Manually set this GitHub Secret/Variable" (R-07 `APP_INSTALLATION_ID` is now auto-set by the receiver's `/install-callback` — no manual paste needed)
- "Go to the GitHub UI / GCP Console / Cloudflare dashboard" (except R-07 GitHub App 2-click manifest flow)
- "Click [any button] in [any UI]" (except the documented vendor floors R-04 / R-07)
- "Ask your operator to..." / "Please provide..."
- "Answer in issue X" / "Reply in PR comment Y" / any non-chat response channel (per §Operator communication channel — operator decisions go in the chat session, never in issues / PR comments / files)
- Any local CLI invocation directed at the operator beyond the documented one-time setups
- Account-creation requests for any platform
- Diagnostic Cloud Shell commands ("can you check...", "please run gcloud..."). Use a workflow, an annotation, or a probe instead.
- **"Tell me when it finishes" / "Let me know when it's done"** — after any `workflow_dispatch`, capture the run ID via `return_run_details: true` (GitHub API 2026-02-19) and poll `GET /actions/runs/{id}` to completion autonomously. The operator is never the polling mechanism.
- **"Send me a screenshot of [service status]"** — dispatch the relevant probe workflow (e.g. `probe-railway.yml`) and read its annotations via `GET /check-runs/{id}/annotations`. Service health is checkable via HTTP (`curl /healthz`). The operator's eyes are not an API.
- **"Check the logs for [workflow run]"** — design all failure branches to write to `$GITHUB_STEP_SUMMARY` (readable via Checks API: `GET /check-runs/{id}` `.output.summary`) in addition to stdout. Raw log access via `GET /actions/jobs/{id}/logs` redirects to a signed S3 URL that may be blocked from the sandbox — never depend on it.

### Operational autonomy standards (postmortem 2026-05-03)

These rules were established after session `claude/fix-app-automation-viXXj` violated the autonomy contract multiple times in a single session.

**Workflow dispatch and polling:** Use `POST .../dispatches` with `{"return_run_details": true}` to get `run_id` immediately (no race condition). Poll `GET /actions/runs/{run_id}` every 15 s until `status == "completed"`. Write conclusion to `$GITHUB_STEP_SUMMARY`. Maximum timeout: 20 min for bootstrap-class workflows, 15 min for deploy-class.

**Post-merge verification:** After any merge to `main`, do not declare the merge healthy based solely on pre-merge PR checks. `pull_request` checks run against a synthetic merge ref (`refs/pull/N/merge`) — a different commit from what actually lands on `main`. After merging: (1) immediately check `mcp__github__list_issues` with `labels: ["workflow-failure"]` for any new issues opened since the merge (instant signal — faster than polling); (2) poll `GET /actions/runs?head_sha=<merge_commit_sha>` every 15 s (up to 20 min) until all `on: push`-triggered workflows on `main` reach a terminal status (`success`/`failure`/`cancelled`) — exclude `workflow_run`-triggered meta-workflows such as `notify-on-workflow-failure.yml` from this check. Only after both checks are clean declare the merge healthy.

**Service state verification:** After any bootstrap or deploy workflow, verify Railway service health autonomously: (1) dispatch `probe-railway.yml` on the clone and read its `::notice::Railway deployment status:` annotation — it reports per-service `DeploymentStatus` (SUCCESS/CRASHED/FAILED/BUILDING) via Railway's `deployments` GraphQL API, the same source the Railway dashboard reads; (2) `apply-railway-spec.yml` and `apply-railway-provision.yml` include a post-provisioning deployment health gate that polls `deployments` every 30 s (up to 10 min) and hard-fails on CRASHED/FAILED. **Never use `curl /healthz` HTTP response codes as a sole health signal** — Railway's proxy/CDN layer returns HTTP 403/200 regardless of container state; a 403 from a public domain means the proxy is alive, not the service.

**`probe-railway.yml` job conclusion is NOT a health signal (postmortem 2026-05-06):** `conclusion=success` means the probe script exited 0 — which happens even when all services are CRASHED. The probe emits `::error::` annotations for CRASHED/FAILED services but does not call `sys.exit(1)`, so the job concludes `success` regardless. The **only** authoritative health signal is the annotation text `::notice::Railway deployment status: svc=SUCCESS`. Binding rules:
1. Never equate `probe-railway.yml conclusion=success` with "services are healthy". They are unrelated.
2. Read probe annotations via GraphQL (`statusCheckRollup → checkRuns → annotations`) — REST `/check-runs/{id}/annotations` requires the job ID (sub-endpoint) and is subject to secondary rate limits. GraphQL has a separate 5000-point quota and returns the same annotation data.
3. A service that shows SUCCESS at T+0 may crash by T+8 min. Stability requires ≥2 annotation reads ≥5 min apart both showing `svc=SUCCESS` before declaring stable.
4. When annotation reads are blocked by rate limits: say "I cannot verify the annotation — API is rate limited" rather than inferring from `conclusion`. Do not fill the evidence gap with an inference.

**Workflow observability:** Every step with a failure path (`raise SystemExit(1)`, `exit 1`) must write its diagnostic output to `$GITHUB_STEP_SUMMARY` before exiting — in addition to stdout. GITHUB_STEP_SUMMARY content is API-accessible without raw log redirection. Stdout alone is not accessible from the sandbox.

**Mutating workflow guard protocol:** Before running any workflow that writes to GCP Secret Manager (`apply-railway-provision`, `terraform apply`, bootstrap Phase 1), first read the existing values to confirm the write is safe. For `apply-railway-provision` specifically: if `railway-project-token` exists in Secret Manager, probe Railway with it before classifying state-C — a token that can reach a project proves the project exists regardless of what the account-level token sees.

**Success declaration standard (postmortem 2026-05-06):** A task is declared complete only when end-to-end evidence exists — not when an individual step passes. The critical distinction:

- **Step passed** → "The `set_var()` call returned HTTP 204." (scoped, verifiable, honest)
- **System verified** → "The workflow ran to terminal `success`, the Railway service is `SUCCESS`, and the variable is readable by the downstream consumer." (requires evidence from all affected layers)

Binding rules:
1. Never say "everything works", "it's fixed", or "done" based on a sub-step result alone. State exactly what was observed and what has not yet been verified.
2. If end-to-end verification is not feasible in the current context (e.g., a full workflow run has not completed), say so explicitly: "Step X confirmed. Full system not yet verified."
3. Use calibrated language: "confirmed by [specific evidence]" vs "I believe" vs "I have not verified". Never collapse these into a single confident assertion.
4. After any `workflow_dispatch`, do not declare the outcome until the run reaches terminal status and the downstream artifact (Secret Manager entry, Railway `DeploymentStatus`, GitHub variable) is confirmed readable via the API — not inferred from the workflow's exit code alone.
5. When evidence is absent or ambiguous — say so. An explicit "I don't know the current state" is more trustworthy than a confident inference. This applies even when the operator is waiting for an answer.
6. An AI that can reliably say "I don't know" is more trustworthy than one that confidently fills the gap. Silence on confidence is not an option; calibration is required.

If you find yourself wanting to produce any of the above outside the explicitly-documented vendor-floor exceptions — pause, re-read this section, and find the autonomous path instead (a workflow you can trigger, a file you can edit, a `gh` MCP call you can make on the operator's behalf).

### Hard-coded HITL kill switches (per OWASP Agentic Top 10, ASI02/ASI03)

These remain HITL at *runtime* (deployed agent), not at *bootstrap*. They do not override the contract above:
- Destructive operations (delete repo, drop database, mass-deletion) → already gated via `src/n8n/workflows/destroy-resource.json` Telegram approval (ADR-0005).
- IAM elevation, branch protection mutation, billing changes.

### What broke the old "STOP and ask" rules

Earlier guidance in this file said: *"On missing secrets: STOP. Print the gcloud command. Await human confirmation."* — that is **revoked**. Replace with: identify which workflow can resolve the missing secret, edit/trigger it, and verify autonomously. The `tools/grant-autonomy.sh` handshake is the only place humans are involved.

---

## Autonomy Separation

This file governs **two distinct autonomy contexts**. Never conflate them.

### A. Build-Agent Autonomy (Claude Code working on this repo)

Operates under the **Inviolable Autonomy Contract above** — that is the binding section. The table below summarizes capabilities; the contract above governs conflicts.

| Permitted | Forbidden |
|-----------|-----------|
| Edit files in `src/`, `terraform/`, `policy/`, `.github/workflows/`, `docs/`, `tools/` | Commit plaintext secrets, tokens, or API keys |
| Create ADRs, skills, unit tests, config templates | `terraform apply` directly from sandbox (must flow through CI/WIF) |
| Push changes to trigger GitHub Actions CI/CD | Auto-register GitHub Apps from sandbox (R-07 manifest flow stays operator-initiated) |
| Append to `JOURNEY.md` every session | Alter branch protection rules |
| Trigger workflow_dispatch via GitHub MCP / `gh` CLI | Download/execute unverified external binaries |
| Read/write GitHub Secrets and Variables via API | Request **any** manual operator action besides ADR-0007's one-time handshake |

**Deployment environment:** Claude Code on the web. No local `gcloud`/`terraform`/`railway` CLI in the sandbox. All cloud mutation goes through GitHub Actions workflows authenticated via WIF.

**On missing secrets:** identify the workflow path that creates them; trigger it. Do not interrupt the operator.

**On failed validation (3x):** open a tracking issue or PR with the diagnosis; continue or halt the specific task — but never escalate to manual operator action outside ADR-0007's perimeter.

**On conflicting evidence:** defer to official vendor documentation; cite URLs in the JOURNEY entry.

**Doc-lint CI (`.github/workflows/doc-lint.yml`):** every PR touching `**/*.md` runs `markdownlint-cli2`, lychee internal-link check, and the Jest `markdown-invariants` suite. The invariants suite enforces "claim N items, table must have N rows" patterns (see `src/agent/tests/markdown-invariants.test.ts`). Add a new test there when introducing a new claim/count pattern in any doc; the cosmetic markdownlint rules are intentionally relaxed, only structural / heading-hierarchy / link-validity issues fail CI.

### B. Runtime-System Autonomy (deployed agent after template instantiation)

The deployed n8n + TypeScript Skills Router cluster operates within these bounds:

| Permitted autonomously | Requires human approval |
|------------------------|------------------------|
| Route Telegram intents to skills | Destructive operations (drop DB, delete repo) |
| Read repository state | Net-new cloud environment provisioning |
| Open pull requests, comment on Linear issues | Merging generated code to `main` |
| Query OpenRouter for inference (≤ $10/day cap) | IAM policy alterations |
| Transition Linear issue states | Any action exceeding OpenRouter budget threshold |
| Create branches from main trunk | |

**Allowed external calls (runtime):** Linear GraphQL, Telegram HTTP API, OpenRouter API, authenticated GitHub API only.

**Rate limits:** OpenRouter capped at $10/day — enforced server-side by OpenRouter on the `openrouter-runtime-key` (`limit_reset: "daily"`, ADR-0004) and pre-flight HITL-gated at the Skills Router via the `/credits` probe (R-08). n8n webhooks rate-limited to 20 req/min at the Skills Router (in-process sliding window, R-02 fail-closed). Knobs: `RATE_LIMIT_MAX`, `RATE_LIMIT_WINDOW_MS`, `OPENROUTER_BUDGET_THRESHOLD_USD`, `OPENROUTER_BUDGET_FAIL_OPEN`.

**Kill switches:** Revoke Telegram Bot token OR delete the GCP WIF provider to immediately paralyze the runtime agent.

**Error containment:** Unhandled exceptions → fail-closed, drop payload, log stack trace, alert operator via Telegram. No automated recovery.

---

## System Architecture

```
GitHub (source of truth)
  │
  ├─► GitHub Actions (CI/CD)
  │     ├─ OPA/Conftest policy checks
  │     ├─ Terraform plan (WIF/OIDC auth → GCP)
  │     └─ Deploy (WIF → Railway + Cloudflare)
  │
  ├─► Railway (runtime)
  │     ├─ TypeScript Skills Router (zero-dep)
  │     └─ n8n orchestrator
  │           └─ GCP Secret Manager (secrets at runtime)
  │
  ├─► Cloudflare (edge routing + DNS)
  │
  └─► External integrations
        ├─ OpenRouter (LLM inference gateway)
        ├─ Linear (project state + MCP server)
        └─ Telegram (HITL communication)
```

**WIF is the identity backbone.** GitHub Actions tokens are exchanged for short-lived GCP credentials. No static service account keys exist in any repository.

---

## Human-Gated Operations (HITL) — historical inventory, not active asks

**All items in this section have already been completed by the operator.** The credentials live in GCP Secret Manager. **Never request the operator to recreate any of them** — see ADR-0007 (Inviolable Autonomy Contract). This list exists only as a historical reference for what platforms the system depends on.

| # | Platform | One-time setup state | Where credentials live |
|---|----------|----------------------|------------------------|
| 1 | GCP project + billing — **fresh per child instance** (ADR-0010 + ADR-0011 §1 Phase C + ADR-0012 Phase E) | DONE for this template-builder clone — operator has `roles/owner` on `or-infra-templet-admin`. For future clones the recommended path is **ADR-0012 (Phase E, GitHub-driven)**: Claude Code dispatches `provision-new-clone.yml` and zero Cloud Shell action is needed per clone — the operator's only contribution is the §E.1 one-time-global pre-grants (org-level SA roles, Provisioner GitHub App registration via `register-provisioner-app.yml` — see ADR-0014) performed once, ever. The original ADR-0011 §1 Cloud-Shell path remains supported for the chicken-egg case (the very first clone, before the template-builder itself exists): export `GCP_BILLING_ACCOUNT` + one of `GCP_PARENT_FOLDER`/`GCP_PARENT_ORG` and `grant-autonomy.sh` auto-creates the project. ADR-0010 manual mode (operator pre-creates the project) is still the fallback. | n/a (live binding) |
| 2 | GCP WIF pool/provider/SA | DONE — created by `tools/grant-autonomy.sh` | GitHub Variables `GCP_WORKLOAD_IDENTITY_PROVIDER` + `GCP_SERVICE_ACCOUNT_EMAIL` |
| 3 | Railway account + token | DONE | `railway-api-token` (kebab) + `RAILWAY_TOKEN` (legacy UPPER) |
| 4 | Cloudflare account + API token | DONE | `cloudflare-api-token`, `cloudflare-account-id` |
| 5 | OpenRouter account + Management key | DONE | `openrouter-management-key` (Provisioning verified — ADR-0006/JOURNEY 2026-05-01) |
| 6 | Telegram bot — **per-clone, vendor floor: 1 tap per clone** (R-04, ADR-0011 §3 deferred). Bot API 9.6 Managed Bots reduces the per-clone manual surface from a multi-step @BotFather conversation to one tap (Telegram anti-abuse policy makes the tap non-removable), but full automation is not currently possible. Existing operator-provided `telegram-bot-token` flow remains the working contract. | DONE for `telegram-bot-token` (current operator-provided bot) | `telegram-bot-token` |
| 7 | Linear workspace + API key | DONE | `linear-api-key`, `linear-webhook-secret` |
| 8 | n8n encryption key + admin owner | AUTO — generated each run by `bootstrap.yml:106-131` | `n8n-encryption-key`, `n8n-admin-password-hash`, `-plaintext` |
| 9 | GitHub App registration (R-07) | When first triggered: 2-click manifest flow (1-click on GHEC). Per GitHub policy this is the only future operator touch and it happens once per child instance, not on this repo. `installation_id` now auto-captured by receiver `/install-callback`. | `github-app-id`, `github-app-private-key`, `github-app-webhook-secret`, `github-app-installation-id` (all auto-injected by Cloud Run receiver — PR #92) |
| 10 | MCP server trust | Runtime HITL approval per session (ADR-0005 destroy-resource pattern) | n/a (runtime decision) |

---

## Active Risks

| ID | Component | Status | Mitigation |
|----|-----------|--------|------------|
| R-01 | Cloudflare OIDC | NEEDS_EXPERIMENT | Use API token via GCP Secret Manager |
| R-02 | Webhook fail-open | Open | HMAC-SHA256 validation, fail-closed |
| R-03 | n8n port collision | NEEDS_EXPERIMENT | `N8N_RUNNERS_ENABLED=false`, unique ports |
| R-04 | Telegram automation | HITL_TAP_REQUIRED_PER_CLONE (re-classified by ADR-0011 §3 Phase D session — supersedes Phase A's over-claim of `AUTOMATABLE_VIA_BOT_API_9.6`) | Bot API 9.6 Managed Bots reduces per-clone surface from multi-step @BotFather to 1 tap; tap itself is non-removable per Telegram anti-abuse policy. ADR-0011 §3 deferred until vendor improvement. |
| R-05 | MCP prompt injection | Open | Sandboxed Railway container, HITL approval |
| R-06 | n8n owner on restart | Validated (Docker) | `tools/staging/test-r06-n8n-owner.sh` asserts hash + createdAt unchanged across restart; Railway re-validation deferred |
| R-07 | GitHub App Cloud Run receiver | Lifecycle validated; **manifest-content coverage gap closed 2026-05-02** (PR #47); **install 404 + installation_id auto-capture fixed 2026-05-02** (PR #92); **SM-failure resilience + recovery UX added 2026-05-03** (PR #100); **SM secret create URL bug fixed 2026-05-03** (PR #105) | PR #92: fixed install URL (org settings path, not public Marketplace); added `setup_url` → receiver captures `installation_id` automatically via `/install-callback`; bootstrap.yml now polls for both `github-app-id` and `github-app-installation-id` before tearing down receiver. PR #100: `_handle_install_callback` now wraps SM write independently — on SM failure returns HTTP 200 + `install_partial_html` (recovery instructions with `write-clone-secret.yml` dispatch steps + `APP_INSTALLATION_ID` variable set command) instead of HTTP 500; app installation succeeds on GitHub's side regardless of SM state. PR #105: `write_secret()` create call now includes `?secretId={name}` query param (was missing, causing 400 when creating new secret containers — silently losing the private key). `register-provisioner-app.yml` check-secrets now gates on `provisioner-app-private-key` (the only unrecoverable secret) and cleans up partial SM state before re-registration. Staging test does not start Python server — treat any `manifest_form_html()` change as requiring real-runtime probe. |
| R-08 | OpenRouter budget probe | Validated (Jest) | `/credits` probe fail-closed by default (gates → HITL); configurable via `OPENROUTER_BUDGET_FAIL_OPEN` (ADR-0004); fail-open deferred to first real-credits run |
| R-09 | Telegram callback_data trust boundary | Validated (Jest jsCode-level) | `src/agent/tests/router.test.ts` evaluates `approval-callback.json` validate-and-parse jsCode in-sandbox: missing `TELEGRAM_CHAT_ID` throws, off-whitelist chat.id → `_action='unauthorized'`, malformed callback_data → `_action='unknown'`, plus `destroy-resource.json` enforces 48-char `resource_id` ceiling for the 64-byte Telegram callback_data cap; real-Telegram E2E deferred |

---

## Secrets Inventory

All secrets live **only** in GCP Secret Manager. Never in `.env`, never in repository files.

| Secret name | Component | Who injects | Status (2026-05-01) |
|-------------|-----------|-------------|---------------------|
| `github-app-private-key` | GitHub App (per-clone runtime) | Cloud Run receiver (auto-injected, see R-07) | ❌ Missing — auto-created by bootstrap |
| `github-app-id` | GitHub App (per-clone runtime) | Cloud Run receiver (auto-injected, see R-07) | ❌ Missing — auto-created by bootstrap |
| `github-app-webhook-secret` | GitHub App (per-clone runtime) | Cloud Run receiver (auto-injected, see R-07) | ❌ Missing — auto-created by bootstrap |
| `github-app-installation-id` | GitHub App (per-clone runtime) | Cloud Run receiver `/install-callback` (auto-injected, PR #92) | ❌ Missing — auto-created by bootstrap (receiver writes on click 2) |
| `provisioner-app-id` | Provisioner GitHub App `autonomous-agent-provisioner-v2` (org-level, ADR-0014) | `register-provisioner-app.yml` Cloud Run receiver | ✅ Present (created 2026-05-03T13:52:12) |
| `provisioner-app-private-key` | Provisioner GitHub App `autonomous-agent-provisioner-v2` (org-level, ADR-0014) | `register-provisioner-app.yml` Cloud Run receiver | ✅ Present (created 2026-05-03T13:52:12) |
| `provisioner-app-installation-id` | Provisioner GitHub App `autonomous-agent-provisioner-v2` (org-level, ADR-0014) | `register-provisioner-app.yml` Cloud Run receiver `/install-callback` | ✅ Present (created 2026-05-03T13:52:26) |
| `cloudflare-api-token` | Cloudflare | Human operator | ✅ Present (kebab copy created 2026-05-01T09:25:46, length 53) |
| `cloudflare-account-id` | Cloudflare | Human operator | ✅ Present (kebab copy created 2026-05-01T09:25:38, length 32) |
| `n8n-encryption-key` | n8n | Bootstrap workflow (auto-generated CSPRNG) | ✅ Present (created 2026-05-01T12:13–12:15 by bootstrap.yml run 25213902199) |
| `n8n-admin-password-hash` | n8n ≥2.17.0 | Bootstrap workflow (auto-generated bcrypt — see R-06) | ✅ Present (created 2026-05-01T12:13–12:15 by bootstrap.yml run 25213902199) |
| `telegram-bot-token` | Telegram | Human operator | ✅ Present (kebab copy created 2026-05-01T09:26:16, length 46) |
| `openrouter-management-key` | OpenRouter (Router uses for `/credits` probe + bootstrap provisioning) | Human operator | ✅ Present (Provisioning Key, created 2026-05-01T09:23:50, verified via `/api/v1/keys` 200) |
| `openrouter-runtime-key` | OpenRouter (n8n runtime, $10/day cap, ADR-0004) | Bootstrap workflow (auto-provisioned via Management API) | ✅ Present (created 2026-05-01T12:13–12:15 by bootstrap.yml run 25213902199; `limit=$10`, `limit_reset=daily`) |
| `linear-api-key` | Linear | Human operator | ✅ Present (kebab copy created 2026-05-01T09:25:54, length 48) |
| `linear-webhook-secret` | Linear | Human operator | ✅ Present (kebab copy created 2026-05-01T09:26:01, length 64) |
| `railway-api-token` | Railway (fallback) | Human operator | ✅ Present (kebab copy created 2026-05-01T09:26:08, length 36) |
| `railway-postgres-service-id` | Railway Postgres service (ADR-0015) | `apply-railway-provision.yml` | ❌ Missing — auto-created by apply-railway-provision.yml |
| `railway-project-token` | Railway CLI scoped token (ADR-0015) | `apply-railway-provision.yml` | ❌ Missing — auto-created by apply-railway-provision.yml |
| `n8n-api-key` | n8n persistent API key (no expiry, label `automation`) | `configure-n8n-openrouter.yml` idempotent step | ❌ Missing — auto-created on first Stage 4 run after 2026-05-05 |

Last reconciled with GCP project `or-infra-templet-admin` on 2026-05-01 after the first autonomous `bootstrap.yml` Phase-1 dispatch (run 25213902199) added the four bootstrap-managed secrets `n8n-encryption-key`, `n8n-admin-password-hash`, `n8n-admin-password-plaintext`, and `openrouter-runtime-key` — see [`docs/bootstrap-state.md`](docs/bootstrap-state.md) for the full snapshot of all 32 actual secrets, enabled APIs, WIF state, and the Recently-deleted log.

---

## Key Files

| File | Purpose |
|------|---------|
| `docs/JOURNEY.md` | Append-only session log (agent appends every session) |
| `docs/session-state.json` | Machine-readable session state (branch, last commit, focus issue). Written by `write-session-state.sh` (Stop) and `pre-compact.sh`; read by `post-compact.sh` and `session-start.sh`. Survives context compaction. |
| `.claude/hooks/pre-compact.sh` | PreCompact hook: saves `docs/session-state.json`, injects session summary into compact prompt (`async: true`) |
| `.claude/hooks/post-compact.sh` | PostCompact hook: reads `docs/session-state.json`, injects branch/focus/autonomy-contract orientation after compaction |
| `.claude/hooks/post-tool-validate.sh` | PostToolUse hook (Write\|Edit): validates `.ts` → tsc, `.json` → JSON.parse, `.yaml/.yml` → js-yaml; blocks on error |
| `.claude/hooks/pre-tool-commit-gate.sh` | PreToolUse hook (Bash): blocks `git commit` if `tsc --noEmit` fails |
| `.claude/hooks/write-session-state.sh` | Stop hook (second entry): writes `docs/session-state.json`; runs independent of GH_TOKEN |
| `docs/adr/` | Markdown Architectural Decision Records (MADR format) |
| `policy/adr.rego` | OPA: blocks merge if infra change lacks ADR |
| `policy/context_sync.rego` | OPA: blocks merge if src/ change lacks JOURNEY.md + CLAUDE.md update |
| `terraform/gcp.tf` | WIF pool, provider, Secret Manager, IAM bindings |
| `terraform/cloudflare.tf` | DNS zone, records, Cloudflare Worker scaffold |
| `src/agent/index.ts` | Zero-dependency TypeScript Skills Router (`POST /webhook`, header `x-signature-256`, format `sha256=<hex>` over raw body — fail-closed per R-02) |
| `src/agent/skills/SKILL.md` | YAML skill registry (Jaccard intent matching) |
| `src/worker/edge-router.js` | Cloudflare Worker — edge proxy to Railway Skills Router |
| `src/n8n/workflows/telegram-route.json` | n8n workflow: Telegram webhook → Skills Router (Phase 5, import via n8n UI) |
| `src/n8n/workflows/linear-issue.json` | n8n workflow: Linear webhook → Telegram notify (Phase 5, import via n8n UI) |
| `src/n8n/workflows/health-check.json` | n8n workflow: real handler probing Skills Router `/health` + OpenRouter `/credits`, replies to Telegram. Reference implementation for migrating other stubs. |
| `src/n8n/workflows/create-adr.json` | n8n workflow: real handler. Receives `{title, context}`, validates HMAC (R-02), signs ADR-0003, calls Skills Router, then via the GitHub App: scaffolds `docs/adr/<NNNN>-<slug>.md` from `template.md`, opens a PR ready-for-review, replies to Telegram with the URL. |
| `src/n8n/workflows/github-pr.json` | n8n workflow: real handler. HMAC-validates inbound payload (R-02), signs ADR-0003 to Skills Router, then via the GitHub App opens a PR for `{title, head, base?, body?, draft?}` and replies the URL to Telegram. |
| `src/n8n/workflows/deploy-railway.json` | n8n workflow: real handler. HMAC-validates inbound payload (R-02), signs ADR-0003 to Skills Router, then triggers a non-destructive Railway redeploy via GraphQL (`serviceInstanceRedeploy(serviceId, environmentId)`) and replies status to Telegram. Inbound payload: `{service_id, environment_id?}`. |
| `src/n8n/workflows/destroy-resource.json` | n8n workflow: real handler. HMAC-validates inbound payload (R-02), signs ADR-0003 to Skills Router, on `pending_approval` sends a Telegram inline-keyboard prompt with Approve/Deny buttons whose `callback_data` fully encodes the destroy command (`dr:<verb>:<resource_type_short>:<resource_id>`). MVP supports `resource_type=railway-service` only. See ADR-0005. |
| `src/n8n/workflows/approval-callback.json` | n8n workflow: passive Telegram Trigger listening for `callback_query` updates. Authorizes by `chat.id` whitelist against `TELEGRAM_CHAT_ID` (R-09), parses `callback_data`, on `approve` calls Railway `serviceDelete` GraphQL, strips buttons via `editMessageReplyMarkup`, acknowledges via `answerCallbackQuery`, replies status. Pairs with `destroy-resource.json` (ADR-0005). Not a SKILL.md skill. |
| `railway.toml` | Railway agent service build/deploy config (TypeScript Skills Router) |
| `railway.n8n.toml` | Railway n8n service config (n8nio/n8n image, env var documentation) |
| `wrangler.toml` | Cloudflare Worker deployment config (required by wrangler-action) |
| `.github/workflows/documentation-enforcement.yml` | OPA/Conftest CI gate |
| `.github/workflows/check-pr-discipline.yml` | PR discipline gate: blocks merge if current-focus issue (1) is timestamp-stale or (2) does not reference the PR number. Runs on every PR to main via `GITHUB_TOKEN` (no extra secret). |
| `.github/workflows/terraform-plan.yml` | IaC validation gate |
| `.github/workflows/deploy.yml` | Railway + Cloudflare deployment |
| `.github/workflows/bootstrap.yml` | One-click bootstrap: secret generation, Secret Manager injection, Railway vars, terraform apply |
| `.github/workflows/probe-railway.yml` | Read-only Railway account-state probe (ADR-0008). Runs `me { projects … }` GraphQL, classifies state A/B/C, writes raw payload + classification to `$GITHUB_STEP_SUMMARY` + workflow annotations. Zero mutations. |
| `.github/workflows/apply-railway-provision.yml` | Idempotent Railway provisioner (ADR-0009 + ADR-0015). Classifier aggregates projects from `me.projects` (personal scope) AND `me.workspaces[*].projects` (workspace scope). State-C: `projectCreate` → 3× `serviceCreate` (`n8n` + `agent` via `serviceConnect` to this repo's `main`; `Postgres` via `ghcr.io/railwayapp-templates/postgres-ssl:17` image) → Volume attachment (`/var/lib/postgresql/data`, `PGDATA=.../pgdata`) → Postgres env vars (`POSTGRES_DB/USER/PASSWORD`, `PGDATA`, `DATABASE_URL`) → Railway project token creation → polls `serviceDomain`. Writes 5 IDs + project token to GCP Secret Manager (`railway-project-id`, `railway-environment-id`, `railway-n8n-service-id`, `railway-agent-service-id`, `railway-postgres-service-id`, `railway-project-token`). State-A requires all 3 services present; state-B fills in missing ones. All steps idempotent (skip-gated). |
| `docs/adr/0008-railway-provisioning.md` | ADR for Railway provisioning: probe-then-provision. State C (operator's account empty) confirmed live on 2026-05-01. ADR-0009 owns the mutation workflow. |
| `docs/adr/0009-railway-mutation-workflow.md` | ADR for `apply-railway-provision.yml`. Defines the state-A/B/C mutation dispatch, idempotency contract, failure semantics (no destruction on duplicate-name), polling soft-fail, and the binding HTTP header contract for every Railway GraphQL call. |
| `docs/adr/0010-clone-gcp-project-isolation.md` | ADR establishing that each child instance cloned from this template MUST live in its own operator-provided GCP project. The GCP project boundary is the secret namespace boundary — kebab-case canon (ADR-0006) stays un-prefixed. Documents the per-clone handshake contract. **Partially superseded by ADR-0011 §1** — auto-creation via Project Factory replaces the operator-brought path. |
| `docs/adr/0011-silo-isolation-pattern.md` | ADR adopting the silo isolation pattern across all per-clone resources: GCP Project Factory (§1, shipped Phase C/PR #32), Cloudflare parameterization (§2, shipped Phase B/PR #31), Telegram Managed Bots (§3, **Phase D deferred — vendor floor: per-bot recipient tap non-removable**), Linear vendor-blocked acknowledgment (§4, docs Phase A/PR #30), ADR-0007/-0010 reconciliation (§5, docs Phase A/PR #30). Net: 2 new auto-implementations + 2 vendor-floored exceptions (Telegram, Linear). |
| `docs/adr/0013-spec-language-and-generic-provisioner.md` | ADR-0013 (Accepted). Defines the spec language (YAML+JSON-Schema), NL→spec boundary, home repo, and validation pipeline for Phase 2 (goal ב). |
| `docs/adr/0014-provisioner-github-app.md` | ADR-0014 (Accepted). Replaces `gh-admin-token` Classic PAT with a dedicated Provisioner GitHub App (`autonomous-agent-provisioner-v2`). Supersedes ADR-0012 §E.1 Sub-step 2. Defines App permissions, 9 workflows to migrate, and new `register-provisioner-app.yml` one-time registration workflow. Phase 1 complete 2026-05-03; Phase 2 complete 2026-05-03 (all 9 workflows migrated to `actions/create-github-app-token@v1`; `inject-gh-admin-token.yml` tombstoned). Phase 3 complete 2026-05-03 (`gh-admin-token` deleted from SM via `delete-gh-admin-token.yml`; tombstone + deletion workflow removed). |
| `docs/adr/0015-postgresql-railway-n8n.md` | ADR-0015 (Accepted). Adds PostgreSQL + persistent Volume to Railway provisioning (ADR-0015 extends ADR-0009). Decisions: `ghcr.io/railwayapp-templates/postgres-ssl:17` image; PGDATA subdirectory (`/var/lib/postgresql/data/pgdata`) to avoid `lost+found` conflict; `DB_TYPE=postgresdb` + `DATABASE_URL=${{Postgres.DATABASE_URL}}` for n8n; project token scoped for CLI use only (GraphQL mutations still use account token). |
| `.github/workflows/register-provisioner-app.yml` | One-time workflow (ADR-0014 Phase 1). Deploys Cloud Run receiver with `SECRET_PREFIX=provisioner-app-` and `APP_PERMISSIONS` (base64 JSON: `administration`+`contents`+`secrets`+`workflows`+`metadata`). Captures `provisioner-app-id`, `provisioner-app-private-key`, `provisioner-app-installation-id` in `or-infra-templet-admin` SM. 2-click vendor floor — same R-07 pattern as bootstrap Phase 4. Run once globally for the org; no `WEBHOOK_URL` (API-only App). |
| `schemas/system-spec.v1.json` | JSON-Schema 2020-12 for the `SystemSpec` v1 resource. Validated by `src/agent/tests/spec-schema-validation.test.ts` in CI. |
| `specs/` | User-facing system specs (`*.yaml`), each conforming to `schemas/system-spec.v1.json`. The reference example is `specs/hello-world-agent.yaml`. |
| `src/agent/tests/spec-schema-validation.test.ts` | Jest test: validates every file in `specs/` against `schemas/system-spec.v1.json` using ajv (JSON-Schema 2020-12). |
| `src/agent/tests/template-provisioning.test.ts` | Jest test: 108 provisioning invariants — spec uniqueness, kebab-case naming, `fromTemplate` pointer, `parse-spec.js` GITHUB_OUTPUT contract, GCP region whitelist, required secrets declared. Added 2026-05-04. |
| `.github/workflows/test-template-e2e.yml` | Template E2E test suite. Tier 1 (tsc+Jest, every PR on specs/schemas/tests) + Tier 2 (Railway probe + GCP secrets checklist, dispatch/weekly). Added 2026-05-04. |
| `specs/template-testing-system.yaml` | SystemSpec for the dedicated template-testing clone (`or-template-testing-001`). Not yet provisioned. Added 2026-05-04. |
| `.github/workflows/apply-system-spec.yml` | Phase 2 provisioner (ADR-0013). `workflow_dispatch` takes `spec_path`; validate → provision-clone (calls `provision-new-clone.yml` as a reusable workflow via `uses:`, blocking) → provision-providers (single job that dispatches `apply-railway-spec.yml` and/or `apply-cloudflare-spec.yml` after one shared WIF auth + PAT fetch). The `needs:` ordering guarantees the target GCP project + GitHub repo exist before Railway/Cloudflare write to them. PR mode: validate-only. |
| `.github/workflows/apply-railway-spec.yml` | Phase 2 Railway provider sub-workflow (ADR-0013, reuses ADR-0009 state-A/B/C classifier). `workflow_dispatch` takes `spec_path`; validates spec, parses `spec.railway.services[]`, probes Railway, creates project named `metadata.name`, then per-service: `kind: typescript` → `serviceCreate` + `serviceConnect(repo, branch=main, rootDirectory)`; `kind: docker` → `serviceCreate(source.image)`. When `n8n` is in the spec, auto-provisions `Postgres` service (`ghcr.io/railwayapp-templates/postgres-ssl:17`) + persistent Volume + env vars (POSTGRES_DB/USER/PASSWORD/PGDATA/DATABASE_URL) — mirrors `apply-railway-provision.yml` so `bootstrap-dispatch.yml` Phase 3 `DB_TYPE=postgresdb` injection always has a target. Writes `railway-project-id`, `railway-environment-id`, `railway-<svc>-service-id`, and `railway-postgres-service-id` to `spec.gcp.projectId`'s GCP Secret Manager. Idempotent. PR mode: probe-only self-register. |
| `.github/workflows/apply-cloudflare-spec.yml` | Phase 2 Cloudflare provider sub-workflow (ADR-0013). `workflow_dispatch` takes `spec_path`; reads `spec.cloudflare.{zone, worker.{name, route}}`, resolves zone → zoneId via Cloudflare REST API (apex + subdomain walk), writes `cloudflare-zone-id`, `cloudflare-worker-name`, `cloudflare-worker-route` to `spec.gcp.projectId`'s GCP Secret Manager. Worker script deployment + route binding remain owned by `deploy.yml` in the clone (R-01). Idempotent. PR mode: probe-only self-register. |
| `scripts/parse-spec.js` | Reads `SPEC_PATH` YAML, emits fields to `GITHUB_OUTPUT` + `GITHUB_STEP_SUMMARY`. Called by `apply-system-spec.yml` dispatch mode. |
| `tools/validate.sh` | Local validation runner (desktop environments only) |

---

## Session Protocol

Every Claude Code session **must**:
1. Read this file first (note especially §Operator communication channel — questions go in chat, never via issues/files).
2. Append a timestamped entry to `docs/JOURNEY.md` before any edits.
3. Update this file if architecture or dependencies change.
4. Push changes — CI runs `npm run test` and `terraform plan` automatically via GitHub Actions. The `PostToolUse` hook auto-validates `.ts`/`.json`/`.yaml` files after every Write/Edit; the `PreToolUse` hook blocks `git commit` if `tsc --noEmit` fails. Both run locally before CI.
5. Document any new risk in `docs/risk-register.md` (mirrors the embedded register).
6. **When opening a PR:** update the `current-focus` issue body to reference the PR number (e.g., "PR #N open for ..."). This is enforced by `check-pr-discipline.yml` CI — the PR cannot merge if the issue body does not contain `#N`.

### Pre-dispatch planning gate (mandatory for all state-mutating operations)

Before dispatching **any** `workflow_dispatch` that writes, creates, or deletes resources — the agent MUST:

1. **Probe current state** using read-only means (GitHub API, `probe-source-secrets.yml`, `probe-railway.yml`, existing resource checks). Do NOT rely on memory or previous session state — check what actually exists right now.

2. **Present a concrete plan** in the chat, including:
   - What will be created / modified / deleted
   - What already exists and will be skipped (idempotent steps)
   - What vendor-floor actions will be required from the operator (e.g. R-07 GitHub App clicks)
   - Estimated sequence and which steps are irreversible

3. **Proceed unless the operator explicitly refuses** ("לא", "no", "cancel", "stop", "abort") in the same chat turn. Any other response — including silence — is treated as approval.

This gate applies even when the operator's request is unambiguous ("do a test", "provision X", "clean up Y"). It does NOT apply to read-only probe dispatches (`probe-railway.yml`, `probe-source-secrets.yml`, and similar). The probe-then-plan step is never skipped.

### Automatic hook coverage (enforced by `.claude/settings.json`)

| Hook | Trigger | Effect |
|------|---------|--------|
| `SessionStart` | Session begins | `npm install`; seeds `docs/session-state.json` if missing; warns if bootstrap-state > 7 days old |
| `PreCompact` | Auto-compaction begins | Writes `docs/session-state.json`; injects branch/commit/focus-issue summary into compact prompt |
| `PostCompact` | Compaction completes | Reads `docs/session-state.json`; injects orientation block into conversation |
| `PostToolUse(Write\|Edit)` | File written/edited | Validates `.ts` → `tsc`; `.json` → JSON.parse; `.yml/.yaml` → js-yaml; blocks on error |
| `PreToolUse(Bash)` | Before Bash tool | Blocks `git commit` if `tsc --noEmit` fails |
| `Stop` | Session ends | Blocks if current-focus issue not updated post-commit; writes `docs/session-state.json` |
| `check-pr-discipline.yml` (CI) | Every PR to main | Blocks merge if: (1) issue timestamp older than PR's oldest commit, OR (2) issue body does not reference `#PR_NUMBER` |
