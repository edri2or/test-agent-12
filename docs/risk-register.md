# Risk Register

Tracks unresolved architectural vulnerabilities, areas requiring empirical validation, and operations requiring mandatory human intervention.

**Source:** Embedded `risk-register.md` in `FINAL_SYNTHESIS_HANDOFF.md.md`.

---

## Risk Matrix

| ID | Component | Description | Classification | Owner | Status |
|----|-----------|-------------|----------------|-------|--------|
| R-01 | Cloudflare | Lack of native OIDC for Workers CI/CD | BLOCKED, NEEDS_EXPERIMENT | Platform Architect | Open |
| R-02 | Webhooks | Fail-open webhook security (legacy pattern) | SYNTHESIS_INFERENCE | Developer | Open |
| R-03 | n8n | Headless CLI port collisions | NEEDS_EXPERIMENT | DevOps | Open |
| R-04 | Telegram | Bot creation requires per-bot user tap (Bot API 9.6 partial) | HITL_TAP_REQUIRED_PER_CLONE (Phase D session re-research; supersedes Phase A's `AUTOMATABLE_VIA_BOT_API_9.6` over-claim) | Operator | Open — ADR-0011 §3 deferred until vendor surfaces fully programmatic path |
| R-05 | MCP | Arbitrary code execution via tool calling | OFFICIAL_STANDARD | Security | Open |
| R-06 | n8n | Owner account re-sync on Railway restart (≥2.17.0) | NEEDS_EXPERIMENT | DevOps | Validated locally (Docker) — Railway re-validation deferred |
| R-07 | GitHub App | Cloud Run receiver lifecycle / OAuth callback | NEEDS_EXPERIMENT | Platform Architect | Lifecycle validated (mocked gcloud) — E2E manual |
| R-08 | OpenRouter | `/credits` budget probe fail-closed default | SYNTHESIS_INFERENCE | Developer | Validated (Jest) — fail-open path deferred to first real-credits run |
| R-09 | Telegram | `callback_data` trust boundary in destroy-resource approval flow | SYNTHESIS_INFERENCE | Security | Validated (Jest jsCode-level) — see `src/agent/tests/router.test.ts` R-09 block; real-Telegram E2E deferred |
| R-10 | Linear | No `createWorkspace` GraphQL mutation — vendor-blocked silo isolation | VENDOR_BLOCKED | Operator | Open — documented by ADR-0011 §4 |
| R-11 | GCP IAM | Runtime SA org-level role expansion for ADR-0012 GitHub-driven clone provisioning | SYNTHESIS_INFERENCE | Security | Open — mitigated by repo-scoped WIF |

---

## R-01: Cloudflare OIDC Gap

**Risk:** Native OIDC support for Cloudflare Workers CI/CD deployments is not available without complex workarounds, forcing reliance on static API tokens.

**Impact:** API token leakage in CI logs could lead to domain hijacking, DNS rerouting, or unauthorized Worker deployment.

**Mitigation:**
- Store the API token strictly within GCP Secret Manager (never in GitHub Secrets or repository)
- Retrieve at runtime via `google-github-actions/get-secretmanager-secrets` action
- Limit token scope to specific DNS zone and Worker script only
- Token is never echoed or logged in CI steps

**Required experiment:** Test experimental GCP Workload Identity Federation paths to Cloudflare APIs when Cloudflare adds official OIDC support.

**Human action required:** Generate token manually in Cloudflare dashboard. Inject into GCP Secret Manager. Do not paste into any CI environment variable directly.

---

## R-02: Webhook Fail-Open Vulnerability

**Risk:** Legacy architectures (observed in `claude-admin`) fall into fail-open paths when webhook secret validation keys are missing.

**Impact:** Unauthorized actors could trigger workflows arbitrarily, leading to resource exhaustion or data corruption.

**Mitigation:**
- HMAC-SHA256 signature validation is mandatory in both n8n and TS Router
- If the signature header is missing: respond HTTP 401, drop payload, log the attempt
- If the signature is present but invalid: respond HTTP 403, drop payload, log with source IP
- Implemented in `src/agent/index.ts` — see `validateWebhookSignature()`

**Validation:** Unit test `src/agent/tests/router.test.ts` includes fail-closed test cases.

---

## R-03: n8n Port Collision

**Risk:** Port 5679 collisions occur when running complex workflows headlessly via the n8n CLI inside Railway containers.

**Impact:** Automated deployment pipelines fail non-deterministically, halting continuous delivery.

**Mitigation:**
- Set `N8N_RUNNERS_ENABLED=false` in Railway environment variables
- Enforce unique broker ports across environments
- Use REST API triggers instead of CLI process execution where possible

**Required experiment:** Validate n8n execution via REST API triggers under high concurrent load in Railway environment.

---

## R-04: Telegram Bot Creation Automation (revised twice — see history below)

**History:**

- **Original (pre-2026-04):** classified `DO_NOT_AUTOMATE`. @BotFather's interactive `/newbot` flow was the only mechanism.
- **Phase A revision (2026-05-01, ADR-0011 §3 draft):** reclassified to `AUTOMATABLE_VIA_BOT_API_9.6` based on the Telegram changelog announcing Managed Bots (April 2026). **This was an over-claim** — the changelog and feature exist but the actual flow still requires a recipient-side tap.
- **Phase D session re-research (2026-05-01):** corrected classification to `HITL_TAP_REQUIRED_PER_CLONE`. Live re-read of [core.telegram.org/bots/api-changelog](https://core.telegram.org/bots/api-changelog) and [aiia.ro Managed Bots writeup](https://aiia.ro/blog/telegram-managed-bots-create-ai-agents-two-taps/) confirmed: *"Telegram requires explicit approval before any managed bot is created — anti-abuse."* Tap is non-removable. ADR-0011 §3 deferred accordingly.

**Current classification:** `HITL_TAP_REQUIRED_PER_CLONE`. Bot API 9.6's `getManagedBotToken` reduces the per-clone manual surface from a multi-step @BotFather conversation to **one tap per clone**, but does not eliminate it.

**Operator action contract (current):**
- Either: pre-create the bot via @BotFather and export `telegram-bot-token` to GCP Secret Manager (existing ADR-0010 contract).
- OR (future, when ADR-0011 §3 lands): pre-create a manager bot once globally; per clone, tap a deep link printed by `grant-autonomy.sh`; script polls `getManagedBotToken` for the new child token.

**Mitigation:**
- No `@BotFather` UI scripting anywhere in this repo.
- The 1-tap flow (Bot API 9.6) is preserved as a future implementation outline in ADR-0011 §3 "Future implementation outline".
- Existing operator-provided `telegram-bot-token` flow remains the working contract until the vendor surface improves.

**Unblocking trigger:** Telegram surfaces a vendor-API path that mints child bots without a per-bot tap (e.g., a SaaS pre-authorization flow). Track via Telegram's [Bot API changelog](https://core.telegram.org/bots/api-changelog).

**Classification rationale:** `HITL_TAP_REQUIRED_PER_CLONE` ≠ `DO_NOT_AUTOMATE`. The latter would forbid any future agent involvement; the former acknowledges that future ADR-0011 §3 implementation can scaffold the deep link + token poll, while the tap itself remains operator-required per vendor policy.

---

## R-05: MCP Prompt Injection

**Risk:** Advanced prompt injection could deceive the runtime agent into executing destructive file operations or exfiltrating sensitive context via MCP tool calls.

**Impact:** Compromise of repository contents, secrets, or infrastructure.

**Mitigation:**
- TS Router runs in a sandboxed Railway container with no root access
- All MCP tool inputs are validated against schema before execution
- Explicit human confirmation (Telegram approval button) required for any `delete`, `drop`, or `mutate` tool calls
- Output sanitization before passing external data to LLM context
- Never configure auto-approval for destructive tool capabilities

**Validation:** `.claude/settings.json` includes deny rules for destructive commands.

---

## New Risks (append below)

<!-- Format: ## R-NN: Title
Description, impact, mitigation, owner, status -->

---

## R-06: n8n Owner Account Restart Behavior (≥2.17.0)

**Risk:** When `N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true`, n8n re-syncs the owner account from env vars on every container restart. Behavior under Railway's restart-on-deploy model (where every deploy causes a container restart) has not been empirically validated.

**Classification:** NEEDS_EXPERIMENT

**Evidence basis:** n8n PR #27859 introduced the feature (2026-04-14). Railway templates and official docs have not yet been updated to document the interaction. The PR description states that env vars "sync on every startup" but does not explicitly address destructive vs non-destructive behavior when an owner record already exists with a different password hash.

**Impact if misconfigured:** Each Railway deploy could overwrite the owner password with the env-var hash, potentially locking out existing sessions. Alternatively (less likely), it could fail silently and leave a stale owner record.

**Mitigation:**
- Store the bcrypt hash in GCP Secret Manager as the authoritative source — the hash is deterministic for the same password, so syncing is idempotent
- Pin the n8n Docker image to `≥2.17.0` explicitly in `railway.toml` / `Dockerfile`
- Validate behavior in a staging Railway environment before production

**Required experiment:** Deploy n8n 2.17.0 to Railway with `N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true`, confirm owner is created on first boot without a browser, then trigger a second deploy and confirm the owner record is not destructively altered.

**Validation artifact:** `tools/staging/test-r06-n8n-owner.sh` — Docker-based local equivalent. Spins up `n8nio/n8n:2.17.0` with the env-managed owner vars + a SQLite volume, captures the owner row, restarts the container with the same env, and asserts the password hash + createdAt are unchanged. Run before any n8n version bump and before promoting Railway template changes.

**Owner:** DevOps
**Status:** Validated locally (Docker) — see `docs/runbooks/staging-validation.md`. Railway-specific re-validation deferred until a Railway environment exists.

---

## R-07: GitHub App Cloud Run Bootstrap Receiver

**Risk:** A temporary GCP Cloud Run service is deployed during bootstrap to receive the GitHub App Manifest OAuth callback. If the service fails to start, crashes before the callback, or if the human does not complete both browser clicks within the 10-minute poll window, the bootstrap job times out and leaves orphaned Cloud Run resources + incomplete Secret Manager state.

**Classification:** NEEDS_EXPERIMENT

**Evidence basis:** GitHub App Manifest flow (Step 1) requires a browser-POST — no REST API alternative for standard (non-GHEC) orgs. Probot and similar projects use this exact Cloud Run callback receiver pattern in production. The Cloud Run service is torn down automatically by the bootstrap workflow after secrets are confirmed present in Secret Manager.

**Impact if misconfigured:** 
- Partial secrets written to Secret Manager (app-id written, private-key write failed) could leave the system in an inconsistent state
- Cloud Run service left running if teardown step is skipped (costs money, potential security surface)
- If `REDIRECT_URL` is not set before the human visits `/`, the GitHub callback will point to `https://placeholder/callback` and fail

**Mitigation:**
- Bootstrap workflow polls Secret Manager for `github-app-id` up to 10 minutes with 30-second intervals (20 retries)
- Cloud Run service is deleted via `gcloud run services delete` in a final cleanup step (runs even on failure via `if: always()`)
- `REDIRECT_URL` is set to the Cloud Run service URL immediately after deploy, before printing the "visit this URL" instruction to the operator
- Health endpoint `GET /health` returns `{"status":"ok"}` — workflow probes it before printing URL

**Required experiment:** End-to-end test: deploy receiver → click "Create GitHub App" → click "Install" → confirm all 3 secrets present in Secret Manager → confirm Cloud Run service deleted.

**Validation artifact:** `tools/staging/test-r07-receiver-lifecycle.sh` — drives 3 scenarios with a mocked `gcloud` shim on `PATH`: (1) happy path: secrets appear after 2 polls → assert teardown invoked; (2) timeout: secrets never appear → assert teardown still invoked (mirrors `if: always()` in `bootstrap.yml`); (3) `WEBHOOK_URL` unset pre-flight: assert fail-closed before any `gcloud run deploy` call (re-asserts the PR #8 invariant). The full E2E with a real GitHub App registration remains a manual checklist in `docs/runbooks/staging-validation.md` — the 2 browser clicks are R-07's irreducible HITL.

**Owner:** Platform Architect
**Status:** Lifecycle validated (mocked gcloud) — see `docs/runbooks/staging-validation.md`. Real-GCP E2E remains manual.

---

## R-08: OpenRouter Budget Probe Fail-Closed Default

**Risk:** The Skills Router uses an `OpenRouterBudgetGate` that probes `GET /api/v1/credits` (60s cached) before routing any skill flagged `budget_gated: true` (currently `openrouter-infer`). When the probe itself fails — network error, OpenRouter outage, malformed response, expired management key — the gate's behavior is governed by `OPENROUTER_BUDGET_FAIL_OPEN`. Default is **fail-closed** (`false`): probe failure → return `pending_approval` → route to HITL. An operator who flips `OPENROUTER_BUDGET_FAIL_OPEN=true` to "keep things working" during a probe outage silently disables the daily-cap pre-flight; the only remaining defense is the server-side `limit_reset: "daily"` on the `openrouter-runtime-key` (ADR-0004).

**Classification:** SYNTHESIS_INFERENCE

**Evidence basis:** Introduced in PR #7 (`docs/adr/0004-runtime-guardrails.md`). The two-layer enforcement model — server-side hard cap on the runtime key + soft pre-flight HITL gate at the Router — is documented in `CLAUDE.md` §Runtime-System Autonomy. The fail-closed default reflects CLAUDE.md's guidance that any action exceeding the budget threshold requires human approval; uncertain probe state is treated as "assume excess".

**Impact if misconfigured:**
- `OPENROUTER_BUDGET_FAIL_OPEN=true` + probe outage → daily-cap HITL gate silently bypassed; runtime calls proceed until the server-side cap on the runtime key fires (typically end-of-day, after a costly burst).
- `OPENROUTER_BUDGET_THRESHOLD_USD` set too low (e.g. `0.0`) → every `budget_gated` skill returns `pending_approval` → HITL fatigue → operator approves blindly, defeating the gate.
- `OPENROUTER_BUDGET_THRESHOLD_USD` set too high (e.g. `9.99`) → cap is effectively disabled until the very last cent.

**Mitigation:**
- Default `OPENROUTER_BUDGET_FAIL_OPEN=false` enforced in `src/agent/index.ts` and set explicitly in `.github/workflows/bootstrap.yml`.
- Threshold default `OPENROUTER_BUDGET_THRESHOLD_USD=1.0` documented in `CLAUDE.md` §Runtime autonomy.
- Probe response cached 60s — limits blast radius of a transient probe failure to the cache window.
- Server-side hard cap on `openrouter-runtime-key` is the authoritative enforcement; the Router gate is a UX layer (advance HITL warning before the user hits a 402 from OpenRouter).

**Required experiment:** Deploy with `OPENROUTER_BUDGET_FAIL_OPEN=false`; revoke or rotate the management key to force probe failure; confirm `openrouter-infer` returns `pending_approval` with `reason: "probe_failed_fail_closed"` (the `GATE_REASONS.PROBE_FAIL_CLOSED` constant defined in `src/agent/index.ts:210`). Then flip to `true`, repeat, and confirm calls proceed (will surface `reason: "probe_failed_fail_open"`). Document both behaviors in the runbook.

**Validation artifact:** Jest covers the fail-closed path end-to-end: `OpenRouterBudgetGate` unit tests (`src/agent/tests/router.test.ts:335-345`) + webhook-handler integration test "budget-gated skill returns pending_approval with probe_failed_fail_closed when /credits probe rejects" (added in this PR). The fail-open scenario stays deferred to the first real-credits deploy because flipping `OPENROUTER_BUDGET_FAIL_OPEN=true` is an operator decision, not a code path that can be validated without an active OpenRouter account.

**Owner:** Developer
**Status:** Validated (Jest) — see `docs/runbooks/staging-validation.md`. Fail-open path deferred until first real-credits run.

---

## R-09: `callback_data` Trust Boundary in destroy-resource Approval Flow

**Risk:** The `destroy-resource` skill (`requires_approval: true`) implements its HITL approval gate via Telegram inline-keyboard buttons whose `callback_data` fully encodes the destroy command (`dr:<verb>:<resource_type_short>:<resource_id>`). The pairing workflow `approval-callback.json` (Telegram Trigger on `callback_query`) authorizes the tap by checking `update.callback_query.message.chat.id === $env.TELEGRAM_CHAT_ID`. There is **no cryptographic signature on the `callback_data` itself** — Telegram alone vouches that the tap came from a legitimate button render, and the `chat.id` whitelist is the only authorization layer.

**Classification:** SYNTHESIS_INFERENCE

**Evidence basis:** Introduced in ADR-0005 (`docs/adr/0005-destroy-resource-approval-callback.md`). The two-workflow architecture was chosen to avoid (a) the n8n `Wait` node bug `n8n-io/n8n#13633` and (b) standing up a state store the template otherwise has no need for. The trade-off is that the destroy command lives in `callback_data` rather than in server-side state correlated by an opaque token.

**Impact if misconfigured:**
- `TELEGRAM_CHAT_ID` env var unset or wrong → fail-closed (the validate node throws); no destruction happens.
- Bot-token leak with chat access → an attacker who exfiltrates the bot token AND has the chat_id could craft a `callback_query` payload via `setWebhook` rerouting or direct bot-API calls to a malicious endpoint impersonating Telegram. This is the residual residual-trust scenario; mitigated by token rotation on suspected compromise (see `docs/runbooks/rollback.md`).
- Multi-user chat → any participant in the configured chat can tap an approval button; this is acceptable for the MVP single-operator deployment but blocks multi-approver / N-of-M flows.
- Stale buttons → `editMessageReplyMarkup` strips the inline keyboard on every Switch arm in `approval-callback.json` (including the unauthorized arm), so a second tap on the same message is a no-op.

**Mitigation:**
- `chat.id` whitelist enforced in `approval-callback.json` validate-and-extract node — fail-closed if `TELEGRAM_CHAT_ID` env var is missing.
- `editMessageReplyMarkup` after first tap prevents replay on the same message.
- Idempotent destroy: re-executing `serviceDelete(<id>)` in the impossible race case is harmless — Railway returns "not found" cleanly on the second call.
- `RAILWAY_API_TOKEN` is read via `$env['RAILWAY_API_TOKEN']` only; never echoed in `sendMessage` text bodies.
- `callback_data` length is bounded by Telegram (64 bytes) — schema-validated by the `dr:<verb>:<type>:<id>` parser; non-conforming data routes to the `unknown` arm and drops cleanly.

**Required experiment:** Deploy with `TELEGRAM_CHAT_ID` set; tap an Approve button from the configured chat → confirm `serviceDelete` mutation fires. Tap an Approve button from a different chat (e.g., a second test bot conversation) → confirm `answerCallbackQuery` returns "Unauthorized" and no GraphQL call is made. Repeat with `TELEGRAM_CHAT_ID` unset — confirm fail-closed throw.

**Validation artifact:** Jest covers the trust boundary at the jsCode level (`src/agent/tests/router.test.ts`):
- `approval-callback.json validate-and-parse: missing TELEGRAM_CHAT_ID throws (R-09 fail-closed)`
- `approval-callback.json validate-and-parse: chat.id mismatch returns _action='unauthorized'`
- `approval-callback.json validate-and-parse: malformed callback_data returns _action='unknown'`
- `destroy-resource.json validate-and-extract: resource_id > 48 chars throws (callback_data 64-byte cap)`
- `destroy-resource.json and approval-callback.json agree on callback_data prefix` (cross-workflow drift detector)

The four jsCode-level tests evaluate the embedded Code-node bodies in a sandboxed `new Function(...)` harness with stubbed `$input`, `$env`, `Buffer`, and `require`. Manual E2E with a real Telegram bot tap from an off-whitelist chat remains deferred until a Railway environment exists.

**Owner:** Security
**Status:** Validated (Jest jsCode-level) — chat.id whitelist, malformed callback_data, missing-`TELEGRAM_CHAT_ID` fail-closed, and the 48-char `resource_id` ceiling are all covered. Real-Telegram E2E deferred until a Railway environment exists.

---

## R-10: Linear has no `createWorkspace` API — vendor-blocked silo isolation

**Risk:** ADR-0011 adopts the silo isolation pattern for every per-clone resource (GCP project, Railway project, Cloudflare resources, Telegram bot). Linear is the **only** vendor where the silo path cannot be automated: the [Linear GraphQL API](https://linear.app/developers/graphql) exposes operations *within* an existing workspace but has no `createWorkspace` mutation. Workspace creation is a UI-only action.

**Classification:** VENDOR_BLOCKED

**Evidence basis:** Direct inspection of [Linear's GraphQL schema](https://linear.app/developers/graphql) — search results across Linear's documentation, API reference, and community forums show no programmatic workspace-creation surface as of 2026-05-01. The closest related capability is OAuth2 `client_credentials` for server-to-server auth *within* a pre-existing workspace.

**Impact if misconfigured:** an operator running multiple template clones against the same Linear workspace shares Linear issues, projects, and webhook traffic across clones — partial namespace collision (the kebab-case `linear-api-key` secret is per-clone in GCP, but the workspace it points to is shared).

**Mitigation (the two acceptable contracts per ADR-0011 §4):**
- **L-pool (default).** All clones share one operator Linear workspace + one `linear-api-key`. Acceptable for trust-isolated single-org operators where Linear data is already operator-private.
- **L-silo (opt-in).** Operator creates a fresh Linear workspace + API key per clone (manually, via Linear UI), exports `LINEAR_API_KEY` to `tools/grant-autonomy.sh`. Parallel to ADR-0010's original GCP contract semantics — operator-brought-per-clone.

**Required experiment:** none — this is a vendor surface gap, not an empirical question.

**Resolution path:** revise this risk only if Linear ships a workspace-creation API in the future, or if the user explicitly accepts L-pool as the long-term contract.

**Owner:** Operator
**Status:** Open — documented by ADR-0011 §4. No automation possible until Linear adds the mutation.

---

## R-11: Runtime SA Org-Level Role Expansion (ADR-0012)

**Risk:** ADR-0012 (GitHub-driven clone provisioning) requires extending the existing runtime Service Account (`github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com`) with two org-level role bindings: `roles/resourcemanager.projectCreator` (+ `roles/resourcemanager.organizationViewer`) on the org and `roles/billing.user` on the billing account. Previously these roles were absent at the org level. Compromise of CI on the template-builder repo could be exercised to create projects under the org and link them to billing.

**Classification:** SYNTHESIS_INFERENCE

**Evidence basis:** ADR-0012 §E.1 sub-step 1. The role expansion is the minimum surface required for the workflow to call `gcloud projects create --folder=...` and `gcloud billing projects link` autonomously.

**Impact if misconfigured / abused:**

- A successful intrusion into the template-builder repo's CI (e.g., malicious PR that lands on `main`) could mass-create empty GCP projects under the org and burn billing-account quota.
- Existing project-level isolation guarantees (ADR-0010) are unchanged — the SA cannot read/mutate other clones' projects (their WIF providers are scoped to their own repos).

**Mitigation:**

- **Repo-scoped WIF (the primary control).** The runtime SA's WIF provider has `attributeCondition: assertion.repository == 'edri2or/autonomous-agent-template-builder'`. Only workflows running on this exact repo can impersonate the SA. An attacker would need to land malicious code in this repo's CI to exercise the org-level bindings.
- **Audit trail.** Every project creation is a `provision-new-clone.yml` workflow run on this repo, visible in GitHub Actions history.
- **Branch protection** on `main` (assumed standard) means PRs require review before merge — adding a manual choke point.
- **Workflow-dispatch only.** `provision-new-clone.yml` has no `push` or `pull_request` trigger; it requires explicit manual dispatch from a user with workflow-dispatch permission on the repo.
- **Org policy quotas (defensive).** GCP org policies can cap project-creation rate (`constraints/resourcemanager.projectCreatorRoles`) — recommended for the operator to add post-Phase-E.

**Required experiment:** dispatch `provision-new-clone.yml` from a non-default branch (which the existing WIF binding still permits — `assertion.repository` matches regardless of branch). Confirm the workflow runs successfully. Then, recommend the operator add a branch-restriction in `attributeCondition` if this becomes a concern (`assertion.ref == 'refs/heads/main' && assertion.repository == '...'`).

**Owner:** Security
**Status:** Open — mitigated by repo-scoped WIF. Org policy quota as a future hardening recommendation.
