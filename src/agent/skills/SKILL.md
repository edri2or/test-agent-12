# SKILL.md — Skills Registry

Agent skills are defined as YAML blocks below. The TypeScript Skills Router
uses Jaccard similarity matching on `intent_keywords` to route inbound intents.

**Adding a new skill:** Copy the template block, fill in the fields, and add it
below the existing skills. The router picks up changes without restart.

**Field semantics:**
- `requires_approval: true` — every match returns `pending_approval` (always HITL).
- `budget_gated: true` — the Router runs an OpenRouter `/credits` pre-flight; only
  returns `pending_approval` when `remaining < OPENROUTER_BUDGET_THRESHOLD_USD`.
  Use this for skills that consume the daily $10 OpenRouter cap (ADR-0004).

---

## Skill: telegram-route

```yaml
name: telegram-route
description: Parse and route a Telegram message to the appropriate handler skill
intent_keywords: [telegram, message, bot, chat, notify, send, alert]
n8n_webhook: /webhook/telegram-route
handler: telegram
requires_approval: false
```

---

## Skill: linear-issue

```yaml
name: linear-issue
description: Create or update a Linear project management issue
intent_keywords: [linear, issue, task, ticket, create, bug, feature, todo, backlog]
n8n_webhook: /webhook/linear-issue
handler: linear
requires_approval: false
```

---

## Skill: openrouter-infer

```yaml
name: openrouter-infer
description: Route an inference prompt to OpenRouter with model selection
intent_keywords: [ask, prompt, generate, infer, llm, model, question, explain, summarize, analyze]
n8n_webhook: /webhook/openrouter-infer
handler: openrouter
requires_approval: false
budget_gated: true
```

---

## Skill: health-check

```yaml
name: health-check
description: Report the health status of all system components
intent_keywords: [health, status, ping, check, up, running, alive, monitor]
n8n_webhook: /webhook/health-check
handler: health
requires_approval: false
```

---

## Skill: deploy-railway

```yaml
name: deploy-railway
description: Trigger a non-destructive Railway deployment of the current main branch
intent_keywords: [deploy, release, ship, railway, push, update, rollout]
n8n_webhook: /webhook/deploy-railway
handler: railway
requires_approval: false
```

---

## Skill: create-adr

```yaml
name: create-adr
description: Scaffold a new Architectural Decision Record from the MADR template
intent_keywords: [adr, architecture, decision, record, document, madr, design]
n8n_webhook: /webhook/create-adr
handler: adr
requires_approval: false
```

---

## Skill: github-pr

```yaml
name: github-pr
description: Open a GitHub pull request for a generated code change
intent_keywords: [pr, pull, request, github, merge, review, branch, code, change]
n8n_webhook: /webhook/github-pr
handler: github
requires_approval: false
```

---

## Skill: destroy-resource

```yaml
name: destroy-resource
description: Destroy a cloud resource (HUMAN APPROVAL REQUIRED)
intent_keywords: [destroy, delete, remove, drop, terminate, teardown, cleanup]
n8n_webhook: /webhook/destroy-resource
handler: destroy
requires_approval: true
```

---

## Template (copy to add a new skill)

```yaml
name: skill-name
description: One sentence describing what this skill does
intent_keywords: [keyword1, keyword2, keyword3]
n8n_webhook: /webhook/skill-name
handler: handler-name
requires_approval: false
budget_gated: false
```
