# Staging Validation Runbook

How to exercise R-06, R-07, and R-08 without real GCP billing, real OpenRouter
credits, or a real Telegram bot. Each risk has a `Required experiment` clause
in `docs/risk-register.md`; this runbook explains how to satisfy that clause
locally.

## When to run this runbook

- Before opening a PR that touches `src/agent/index.ts`, `src/n8n/workflows/`,
  `.github/workflows/bootstrap.yml`, or `src/bootstrap-receiver/`.
- Before bumping the n8n image version pinned in `railway.n8n.toml`.
- Before promoting a new Skills Router release.
- After updating `OpenRouterBudgetGate` or `validateWebhookSignature` in the
  Router.

## R-06 — n8n owner re-sync idempotency

**Risk:** Each Railway deploy could overwrite the n8n owner password (or
silently leave a stale record) when `N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true`.

**What we validate:** After a container restart with identical env vars, the
owner row's password hash and `createdAt` are bit-identical.

**How:**
```bash
bash tools/staging/test-r06-n8n-owner.sh
```

Requirements: `docker`, `sqlite3`, `htpasswd` (usually in `apache2-utils` /
`httpd-tools`).

**Expected output:** `[R-06] PASS — owner password + createdAt unchanged
across restart (idempotent)`.

**On FAIL:** the env-managed owner is NOT idempotent at the n8n version under
test. Do not pin that version in `railway.n8n.toml` until upstream fixes it
or until a deterministic re-sync path is documented. Append the version + the
diff between rows to `docs/risk-register.md` R-06 section.

**What this does NOT cover:** Railway-specific behavior (filesystem
persistence on Railway volumes, secret-injection ordering, the exact restart
signal Railway sends). Re-validate on Railway once a Railway environment
exists for staging.

## R-07 — Cloud Run receiver lifecycle

**Risk:** Bootstrap leaves orphaned Cloud Run resources or fails partway
through, leaving Secret Manager in an inconsistent state.

**What we validate:**
- Pre-flight check rejects missing `WEBHOOK_URL` BEFORE any `gcloud run
  deploy` call (PR #8 invariant).
- Polling logic exits successfully when secrets eventually appear.
- Teardown is invoked even when the poll times out (mirrors `if: always()`
  in `bootstrap.yml:628`).

**How:**
```bash
bash tools/staging/test-r07-receiver-lifecycle.sh
```

No GCP project required — the script injects a `mock-gcloud` shim onto `PATH`
and asserts via the call log.

**Expected output:** `[R-07] All 3 scenarios PASS`.

**On FAIL:** read the mismatched scenario output. The most common drift is
that the bootstrap YAML changed its semantics without updating the test
contract — either the YAML is regressed or the test needs to be updated. Both
must move together.

**What this does NOT cover:** the human OAuth dance. Specifically:
- Browser-side rendering of the GitHub App Manifest form on the receiver's
  `/` route
- The two real GitHub clicks ("Create GitHub App" + "Install")
- Whether the App's webhook URL ends up matching what was set in
  `vars.WEBHOOK_URL`

These steps are R-07's irreducible HITL. Manual checklist below.

### R-07 manual E2E (when a sandbox GH org + free-tier GCP project are
available)

1. Create a GCP project (free tier is fine — Cloud Run + Secret Manager fit
   well within the free quotas for a one-shot bootstrap).
2. Set `WEBHOOK_URL`, `GITHUB_ORG`, `APP_NAME` repo variables.
3. Trigger `.github/workflows/bootstrap.yml` (`gh workflow run bootstrap.yml`).
4. Watch the workflow logs for the "ACTION REQUIRED" message printing the
   receiver URL.
5. Open the URL in a browser. Click "Create GitHub App". On the next page,
   click "Install".
6. Verify within 10 minutes:
   - `gcloud secrets versions access latest --secret=github-app-id` returns a
     numeric ID.
   - `gcloud secrets versions access latest --secret=github-app-private-key`
     returns a PEM block.
   - `gcloud secrets versions access latest --secret=github-app-webhook-secret`
     returns a hex string.
   - `gcloud run services list` does NOT list `github-app-bootstrap-receiver`
     (teardown ran).
   - The newly-created GitHub App in the org's Developer Settings has its
     webhook URL set to the value of `vars.WEBHOOK_URL` (NOT a placeholder).
7. Append the run timestamp + outcome to `docs/risk-register.md` R-07 section.

## R-08 — OpenRouter `/credits` budget probe fail-closed

**Risk:** Operator flips `OPENROUTER_BUDGET_FAIL_OPEN=true` during a probe
outage, silently disabling the daily-cap HITL gate.

**What we validate:**
- `OpenRouterBudgetGate.shouldGate` returns `gated=true` with
  `reason=PROBE_FAIL_CLOSED` when the probe rejects, by default.
- Same gate returns `gated=false` with `reason=PROBE_FAIL_OPEN` when
  `failOpen=true`.
- The webhook handler propagates `pending_approval` with the
  `probe_failed_fail_closed` reason when a budget-gated skill matches AND
  the probe rejects.

**How:**
```bash
cd src/agent && npm test
```

The relevant tests:
- `OpenRouterBudgetGate` block — `src/agent/tests/router.test.ts:290-346`
- `Webhook handler — guardrails` block — `src/agent/tests/router.test.ts:350-498`
  - Specifically the test "budget-gated skill returns pending_approval with
    probe_failed_fail_closed when /credits probe rejects (R-08)" added in
    this PR.

**Expected output:** all tests pass.

**On FAIL:** the gate's contract has regressed. Trace the failing test's
expected `reason` against `GATE_REASONS` in `src/agent/index.ts:207-211`
before changing either side.

**What this does NOT cover:** behavior under a real OpenRouter outage with
real credits flowing. Specifically:
- Whether the server-side `limit_reset: "daily"` cap on the runtime key
  fires when the soft gate is bypassed.
- The fail-open path with `OPENROUTER_BUDGET_FAIL_OPEN=true` against a real
  rejected probe — currently only mock-tested.

These run once a real OpenRouter account is connected. When that happens:
1. Set `OPENROUTER_BUDGET_FAIL_OPEN=true` in the staging Railway env.
2. Revoke or rotate the management key (`gcloud secrets versions disable`).
3. Send a Telegram message that matches an `openrouter-infer` intent.
4. Confirm the call proceeds (fail-open behavior) and the runtime key's
   server-side cap is the only remaining defense.
5. Restore `OPENROUTER_BUDGET_FAIL_OPEN=false` and the management key.

## After running

If all three artifacts pass, append a session entry to `docs/JOURNEY.md`
recording the date and the commit SHA tested. The Status column in
`docs/risk-register.md` for R-06/R-07/R-08 already references these artifacts;
do not regress those statuses unless a script genuinely starts failing.
