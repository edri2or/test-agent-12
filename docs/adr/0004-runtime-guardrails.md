# ADR-0004: Runtime Guardrails — OpenRouter Budget, Rate Limit, HITL Gate

**Date:** 2026-04-30
**Status:** Accepted
**Deciders:** Build agent + operator review

## Context and Problem Statement

`CLAUDE.md` declares four runtime autonomy bounds, none of which were enforced anywhere in code:

1. OpenRouter $10/day budget cap (`CLAUDE.md` runtime-autonomy table, "Rate limits" line).
2. n8n webhooks rate-limited to 20 req/min (same line).
3. HITL gate when an action would exceed the OpenRouter budget threshold (`CLAUDE.md` runtime-autonomy table, "Requires human approval" column).
4. The `openrouter-infer` skill (`src/agent/skills/SKILL.md:45`) routes intents matching `[ask, prompt, generate, infer, llm, model, …]` but no n8n workflow file existed at `/webhook/openrouter-infer`, so every match was a dead-end.

These claims existed only in prose (`README.md`, `SECURITY.md`, `AGENTS.md`) and were the last unimplemented runtime guardrail set before connecting an OpenRouter account with real credits — a hard prerequisite for autonomous LLM use.

## Decision Drivers

- **Zero-dep philosophy** — Skills Router has no npm runtime deps; new code must keep that property.
- **R-02 alignment** — every gate must fail-closed under uncertainty.
- **ADR-0003 contract preservation** — the `POST /webhook` + `x-signature-256` HMAC contract is a signed-off perimeter and must not change.
- **Server-side > client-side enforcement** — strong cap requires a guarantee that survives agent bugs.
- **Autonomy preservation** — autonomous loop must keep working under threshold; only *exceeding* the threshold should require HITL.

## Considered Options

### A. Cloudflare Worker edge-only enforcement

Add a `[[unsafe.bindings]] type = "ratelimit"` to `wrangler.toml` and call `env.RATELIMIT.limit({ key })` inside `src/worker/edge-router.js`. Use Cloudflare KV / Durable Object for budget state.

**Rejected (for this PR).** `terraform/cloudflare.tf` declares the `n8n` hostname as an un-proxied CNAME; routing it through the Worker requires a DNS topology change + WebSocket re-validation. Out of scope. The Worker also doesn't easily test in Jest. **Deferred to a follow-up PR.**

### B. In-process Skills Router enforcement + downstream OpenRouter key (chosen)

- **Rate limit** — sliding-window counter inside `src/agent/index.ts`, keyed by `req.socket.remoteAddress`. Default 20 req per 60 s. Triggered post-signature-validation so attackers cannot consume counters.
- **Hard budget cap (server-side)** — provision a downstream API key via OpenRouter's Management API with `limit=10, limit_reset="daily"`. n8n's `openrouter-infer` workflow uses *this* key (never the management key). OpenRouter rejects requests at the edge once the cap is hit. Resets at midnight UTC.
- **Soft HITL gate (Router)** — pre-route `GET /api/v1/credits` (60 s cached) when the matched skill carries `budget_gated: true`. If `remaining < OPENROUTER_BUDGET_THRESHOLD_USD`, the Router returns `{ status: "pending_approval", reason: "openrouter_budget_threshold" }` so the operator gets a Telegram approval prompt *before* the call, not a 402 *after*.
- **Schema additivity** — new field `budget_gated?: boolean` on `Skill`, default `false`. Existing skills are unaffected; `requires_approval: true` remains the always-HITL gate.

### C. Documentation-only / deferred

Mark all four as "documented but not yet enforced", continue without code. **Rejected** — the operator explicitly flagged this as blocking before connecting real credits.

## Decision Outcome

**Chosen option: B.**

Default failure mode for the `/credits` probe is **fail-closed** (gate → human approval) when the endpoint is unreachable. Rationale: `CLAUDE.md` treats budget excess as HITL; if we cannot verify the balance, we should assume excess. Operators who prefer liveness can flip with `OPENROUTER_BUDGET_FAIL_OPEN=true`.

### Operator-overridable defaults

| Knob | Default | Override env var |
|---|---|---|
| `/credits` failure mode | fail-closed | `OPENROUTER_BUDGET_FAIL_OPEN=true` |
| HITL threshold (USD remaining) | `1.0` | `OPENROUTER_BUDGET_THRESHOLD_USD` |
| `/credits` cache TTL | 60 s | constant in `src/agent/index.ts` |
| Rate-limit max | 20 | `RATE_LIMIT_MAX` |
| Rate-limit window | 60 000 ms | `RATE_LIMIT_WINDOW_MS` |
| Rate-limit key | `req.socket.remoteAddress` | constant |

### Consequences

**Good:**
- Single trust boundary (per ADR-0003) is also the single enforcement boundary — no new runtime infrastructure.
- Fully Jest-testable; 18+ new tests added (`RateLimiter`, `OpenRouterBudgetGate`, integration on ephemeral port, n8n workflow file shape).
- OpenRouter cap is enforced server-side regardless of agent behavior — even if every other gate fails, the runtime key cannot exceed $10/day.
- `budget_gated` is additive: introducing the flag on new skills (e.g., a future `openrouter-batch-infer`) requires zero plumbing.

**Bad / accepted trade-offs:**
- In-process rate-limit state is lost on agent restart. Acceptable for a single-replica service; would need Redis/KV for HA.
- The Router holds the management key in-process to call `/credits`; the management key is read-only-ish for that endpoint but operators should be aware. Mitigation: `OPENROUTER_MANAGEMENT_KEY` is *not* used for chat completions — only `/credits`.
- A `/credits` outage during a budget-gated route causes HITL by default — liveness regression for operators who haven't tuned `OPENROUTER_BUDGET_FAIL_OPEN`. Documented in R-08.
- Cloudflare-edge limit on the n8n hostname is deferred; n8n's *external* webhook surface (Telegram, Linear) is currently bounded only by upstream rate-limits (Telegram Bot API caps + Linear's own webhook rate) until the follow-up PR.

## Validation

- `npm test` — 27 prior tests unchanged; ≥18 new tests added covering all gates.
- `npx tsc --noEmit` — clean.
- `python3 -c "import json; json.load(open('src/n8n/workflows/openrouter-infer.json'))"` — JSON OK.
- CI gates: `documentation-enforcement.yml` enforces ADR + JOURNEY.md + CLAUDE.md updates whenever `src/` or `terraform/` change.
- Manual end-to-end (deferred until OpenRouter management key is wired):
  1. Run bootstrap → confirm `openrouter-runtime-key` exists in Secret Manager with daily limit on the OpenRouter dashboard.
  2. Curl 21 signed payloads in <60 s → 21st returns 429.
  3. Set `OPENROUTER_BUDGET_THRESHOLD_USD` to a value greater than the current remaining → `openrouter-infer` route returns `pending_approval`.

## Links

- Implementing PR: TBD (this PR)
- ADR-0003 — webhook signature contract (preserved)
- [OpenRouter — Get remaining credits](https://openrouter.ai/docs/api/api-reference/credits/get-credits)
- [OpenRouter — Provisioning API keys](https://openrouter.ai/docs/features/provisioning-api-keys)
- [Cloudflare Workers — Rate Limiting binding (deferred follow-up)](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
