# ADR-0003: Inter-service Webhook Signature Contract (n8n → Skills Router)

**Date:** 2026-04-30
**Status:** Accepted
**Deciders:** Build agent + operator review

## Context and Problem Statement

The n8n Telegram workflow (`src/n8n/workflows/telegram-route.json`) and the TypeScript Skills Router (`src/agent/index.ts`) disagreed end-to-end on three things: URL path (`/route` vs `/webhook`), signature header name (`X-Webhook-Signature` vs `x-signature-256`), and HMAC computation (signature merged into the body as `_sig` vs computed over the raw body bytes the receiver reads). The path was unreachable in practice, so no Telegram intent ever made it to the Router. We need a single, durable convention for inter-service HMAC so that this mismatch cannot recur.

Adding `github-app-webhook-secret` to `terraform/variables.tf` `secret_names` is part of the same PR (closes a bootstrap-blocking inventory gap where the Cloud Run receiver wrote to a non-existent Secret Manager container) — it is a trivial container addition driven by this same contract decision and does not warrant a separate ADR.

## Decision Drivers

- Existing Router code (`validateWebhookSignature` in `src/agent/index.ts:169-189`) is already correct: timing-safe comparison, `sha256=<hex>` format, fail-closed per R-02.
- Existing fail-closed test suite (`src/agent/tests/router.test.ts:143-183`, 6 tests) covers the Router convention. Changing the Router would require rewriting tests and weakening R-02 protection.
- Every `n8n_webhook` path declared in `src/agent/skills/SKILL.md` already uses the `/webhook/...` prefix. The only `/route` reference in the entire repo was the broken n8n workflow line.
- Industry research: GitHub's `X-Hub-Signature-256` + `sha256=<hex>` is the de-facto convention used by Stripe, Shopify, Okta, and others. HMAC must be computed over **raw body bytes** — re-serialized JSON breaks signatures because of whitespace and key-ordering drift.

## Considered Options

1. **Align n8n to the Router (chosen).** Change n8n to POST to `/webhook` with header `x-signature-256`, build the body as an explicit string in a Code node, sign that exact string, and send it via HTTP Request `contentType: raw` so n8n does not re-serialize.
2. **Align Router to n8n's previous behavior.** Add a `/route` alias and accept `X-Webhook-Signature`. Rejected: requires rewriting the working Router and its R-02 test suite, codifies the `_sig`-in-body anti-pattern, and breaks every other skill in `SKILL.md` that declared `/webhook/...` paths.
3. **Defer and add a dispatcher layer.** Introduce a translation shim. Rejected: adds a moving part to fix a contract that just needs to be standardized once.

## Decision Outcome

**Chosen option:** Align n8n to the Router. The contract for any service calling the Skills Router is:

| Aspect | Value |
|--------|-------|
| Method + path | `POST /webhook` |
| Body | JSON matching `WebhookPayload` (`intent`, `chat_id`, `user_id`, `timestamp`, `metadata`) |
| Body transmission | Caller must send the exact bytes the signature was computed over (no re-serialization) |
| Header | `x-signature-256` |
| Header value | `sha256=<lowercase hex>` (HMAC-SHA256 of the raw body using the shared secret) |
| Failure mode | Fail-closed — receiver returns 401 on missing/invalid signature; sender throws if secret env var is absent (R-02) |

### Consequences

**Good:**
- Single, GitHub-aligned convention shared by all callers of the Router.
- Existing fail-closed test suite (R-02) remains the source of truth — no test rewrites.
- Future skill workflows (Linear, OpenRouter, GitHub PR, deploy-railway, etc.) get a documented contract to mirror.

**Bad / accepted trade-offs:**
- Any new n8n author calling the Router from an HTTP Request node must remember to set `contentType: raw` and pre-compute the body string in a Code node — not the n8n default (`bodyParameters`). Mitigation: the canonical pattern is now committed in `src/n8n/workflows/telegram-route.json` as a copyable template.
- Caller env var `SKILLS_ROUTER_SECRET` becomes an additional ops requirement; missing it fails closed (acceptable per R-02).

## Validation

- `npm test` — all 27 Router tests pass unchanged, including the 6 fail-closed signature cases.
- `tsc --noEmit` clean.
- CI gates: `documentation-enforcement.yml` enforces ADR + JOURNEY.md + CLAUDE.md updates whenever `src/` or `terraform/` change.
- Manual end-to-end HMAC simulation script documented in `JOURNEY.md` session entry; runs once n8n is deployed.

## Links

- Implementing PR: [#5](https://github.com/edri2or/autonomous-agent-template-builder/pull/5)
- [GitHub Docs — Validating webhook deliveries](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries)
- [Hookdeck — How to Implement SHA256 Webhook Signature Verification](https://hookdeck.com/webhooks/guides/how-to-implement-sha256-webhook-signature-verification)
- [webhooks.cc — How to Verify Webhook Signatures](https://webhooks.cc/docs/guides/verify-webhook-signatures)
