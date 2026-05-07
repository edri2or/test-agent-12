# ADR-0005: Destroy-resource Telegram approval-callback architecture

**Date:** 2026-05-01
**Status:** Proposed
**Deciders:** Platform Architect, Developer

## Context and Problem Statement

The `destroy-resource` skill is `requires_approval: true` per `src/agent/skills/SKILL.md:117`. The Skills Router unconditionally returns `{status: "pending_approval"}` for matched intents (`src/agent/index.ts:437-444`), and CLAUDE.md §Runtime-System Autonomy classifies destructive operations as "Requires human approval". Unlike the four prior real handlers (`health-check`, `create-adr`, `github-pr`, `deploy-railway`) which are synchronous request-response flows, this one must pause for an asynchronous human decision and resume on a button click. The template needs a HITL approval mechanism that fits the existing constraints (no state store, n8n+TS Skills Router only, Railway redeploy survival).

## Decision Drivers

- No state store exists in the repo (no DB / KV / Redis / Firestore).
- Adding infra (state layer) is out of scope for the MVP.
- The Router and SKILL.md should stay untouched — callback approval is a Telegram-side concern, not a routing concern.
- The template must survive Railway redeploys (R-06).
- The pattern should match documented n8n + Telegram practice, not hand-rolled glue.
- `callback_data` is capped at 64 bytes by the Telegram Bot API.

## Considered Options

1. **n8n `Wait` node, single workflow** — pause the workflow on `pending_approval`, send `$execution.resumeUrl` as the inline-button target, resume on button tap.
2. **External state store (Redis / Firestore) + correlation ID** — store the pending destroy request server-side, send a token via Telegram, look up + execute on callback.
3. **Two workflows + idempotent `callback_data`** — `destroy-resource.json` sends Telegram buttons whose `callback_data` fully encodes the destroy command; a separate `approval-callback.json` workflow listens for `callback_query` updates, parses the data, authorizes, and executes.

## Decision Outcome

**Chosen option:** Option 3 (two workflows + idempotent callback_data), because:

- It needs no state store — the `callback_data` itself is the state.
- It avoids `n8n-io/n8n#13633` (a documented "Respond to webhook not working when using wait node option On webhook call" bug) and the partial-execution-changes-resumeUrl caveat in n8n's Wait-node docs.
- It matches n8n's documented Telegram callback-query pattern (Telegram Trigger with `updates: ["callback_query"]` → Switch on `callback_data`).
- It keeps the Skills Router and `SKILL.md` untouched.
- It fits the 64-byte `callback_data` budget for any 36-char Railway service UUID with room to spare (`dr:a:rs:` = 8 bytes prefix).

### Architecture

```
destroy-resource.json (the skill handler)
  Webhook → HMAC validate (R-02) → ADR-0003 sign → Call Router →
  pending_approval → Telegram sendMessage with inline_keyboard buttons:
    [✅ Approve | callback_data="dr:a:rs:<id>"]
    [❌ Deny    | callback_data="dr:d:rs:<id>"]
  → Respond 200

approval-callback.json (passive listener)
  Telegram Trigger (updates: ["callback_query"]) →
  Authorize (chat.id === $env.TELEGRAM_CHAT_ID) →
  Parse callback_data → Switch on verb →
  [approve] Railway GraphQL serviceDelete(id) →
  [deny]    no destruction
  → editMessageReplyMarkup (strip buttons, prevent re-tap) →
  → answerCallbackQuery (dismiss spinner) →
  → sendMessage (status confirmation)
```

### `callback_data` format

`"dr:" + verb + ":" + resource_type_short + ":" + resource_id`

- Verbs: `a` (approve) / `d` (deny). 1 char.
- Resource type short codes (MVP): `rs` (railway-service). 2 chars.
- Total prefix: `dr:a:rs:` = 8 chars, leaves 56 bytes for the resource_id (Railway UUIDs are 36 chars).

### MVP resource scope

`resource_type=railway-service` only — single GraphQL mutation `serviceDelete(id)` against `https://backboard.railway.app/graphql/v2` (same endpoint and auth model already used by `bootstrap.yml`, `tools/bootstrap.sh`, and `deploy-railway.json`). Additional resource types (GCP, GitHub repo, Linear issue) are explicit follow-ups — each adds a new short code + Switch arm + API call.

### Authorization

Single layer: `update.callback_query.message.chat.id === $env.TELEGRAM_CHAT_ID` (string-compared). Mismatch → `answerCallbackQuery` with "Unauthorized" + drop. Telegram's button-tap delivery model bounds the threat: only users with chat access AND an actual button rendered in their chat view can issue a callback. Residual trust boundary documented as **R-09**.

### Consequences

**Good:**
- Zero new infra (no DB, no state store, no Wait-node usage).
- Router and SKILL.md unchanged — minimal blast radius.
- Survives Railway redeploys naturally (no in-flight state to lose).
- Replay-resistant by `editMessageReplyMarkup` after first tap (buttons stripped on every Switch arm including the unauthorized arm).
- Idempotent destroy: re-tapping (in the impossible race case) calls `serviceDelete(id)` twice; Railway returns "not found" cleanly on the second call.

**Bad / accepted trade-offs:**
- Multi-operator approval (N-of-M) is not supported in MVP — single `chat.id` whitelist.
- TTL on the inline keyboard is not enforced (Telegram doesn't natively support this); approval messages remain valid until tapped or until the buttons are stripped.
- Audit trail lives only in the Telegram message thread; structured logging is a follow-up.
- Bot-token leak is the residual threat — an attacker with the bot token + chat access could craft callback_query payloads. **R-09** documents this.

## Validation

- `npm test` adds 5 assertions: 3 canonical triplet for `destroy-resource.json` (valid JSON, signs ADR-0003 with `DESTROY_RESOURCE_WEBHOOK_SECRET`, no stub); 1 verifying `approval-callback.json` is valid JSON and contains a Telegram Trigger node; 1 cross-workflow assertion that both files reference the same `dr:a:rs:` and `dr:d:rs:` callback_data prefixes (catches drift between the two workflows).
- Manual end-to-end (real Telegram bot + real Railway service) deferred to first n8n deploy — same status as ADR-0003 / ADR-0004 pre-deploy validation.
- `policy/adr.rego` enforces this ADR's existence at merge time.

## Links

- [Telegram Bot API](https://core.telegram.org/bots/api) — `InlineKeyboardMarkup`, `callback_query`, `answerCallbackQuery`, `editMessageReplyMarkup`.
- [n8n Telegram callback operations](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.telegram/callback-operations/)
- [n8n Wait node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.wait/) — rejected option; partial-execution caveat.
- [n8n Issue #13633](https://github.com/n8n-io/n8n/issues/13633) — Respond to webhook bug with `On webhook call` Wait mode.
- ADR-0003 (`docs/adr/0003-webhook-signature-contract.md`) — HMAC contract reused for the inbound webhook.
- ADR-0004 (`docs/adr/0004-runtime-guardrails.md`) — runtime autonomy bounds; sets the precedent that destructive operations require HITL.
- R-09 (`docs/risk-register.md`) — callback_data trust boundary.
