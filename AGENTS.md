# AGENTS.md — Agent Roles and Autonomy Contracts

This file describes every agent that operates within this repository and its deployed systems.

---

## 1. Build Agent — Claude Code CLI

**Context:** Local development machine / CI pipeline (build time)
**Identity:** Human operator's local Claude Code session

### Permitted Actions

- Read and edit files in `src/`, `terraform/`, `policy/`, `.github/workflows/`, `docs/`
- Create: ADRs, skills (`SKILL.md` entries), unit tests, config templates
- Delete: deprecated code in `src/`, outdated unit tests
- Run locally: `npm run build`, `npm run test`, `terraform plan`, `railway status`, linting tools
- Deploy: non-destructive updates via `railway up` (only after test suite passes)
- Append entries to `docs/JOURNEY.md` each session

### Forbidden Actions

- `terraform apply` or any remote infrastructure state mutation
- Committing plaintext secrets, tokens, or API keys to any file
- Automating Telegram bot creation via API or script
- Automating GitHub App registration via curl or API
- Downloading or executing unverified external binaries
- Modifying branch protection rules via the GitHub API
- Deleting cloud databases, network resources, or IAM policies

### Halt Conditions

The build agent **must stop and print human instructions** when it encounters:
- A missing secret required to continue scaffolding
- 3 consecutive validation failures despite patching
- A contradiction between `FINAL_SYNTHESIS_HANDOFF.md.md` and official vendor documentation
- Any instruction to cross a human-gated boundary

---

## 2. Runtime Agent — TypeScript Skills Router

**Context:** Railway container (runtime)
**Identity:** Deployed `src/agent/index.ts` process

### Permitted Actions (autonomous)

- Parse inbound Telegram messages from known operators
- Match user intents to `SKILL.md` definitions via Jaccard similarity
- Read repository state via authenticated GitHub API
- Open pull requests, create branches from `main`
- Comment on Linear issues, transition issue states
- Query OpenRouter API for inference (hard cap: $10/day, 20 n8n webhook req/min)
- Append audit entries to structured external logging

### Forbidden Actions (runtime)

- Delete GitHub repositories
- Drop cloud databases or storage buckets
- Alter IAM permission policies
- Exceed OpenRouter budget threshold
- Merge code directly to `main` (PRs require human review)
- Execute requests missing HMAC-SHA256 webhook signatures

### Approval Required (runtime)

- Destructive operations of any kind
- Provisioning net-new cloud environments with billing costs
- Merging generated code to `main`

### Kill Switches

1. Revoke the Telegram Bot token via @BotFather → severs HITL interface
2. Delete the GCP WIF provider → severs all CI/CD pipeline authentication

---

## 3. Runtime Agent — n8n Orchestrator

**Context:** Railway container (runtime), paired with TS Skills Router
**Identity:** Containerized n8n instance

### Permitted Actions (autonomous)

- Execute workflow automations triggered by TS Router or webhook events
- Retrieve secrets from GCP Secret Manager at runtime via IAM-scoped bindings
- Call external REST APIs (Linear, Telegram, OpenRouter, GitHub) as configured
- Expose workflows as MCP tools via `n8n-nodes-langchain.mcptrigger`
- Import/export workflow JSON via `n8n` CLI

### Forbidden Actions (runtime)

- Self-modify IAM roles or GCP project configuration
- Process webhook payloads without HMAC-SHA256 signature validation (fail-closed, R-02)
- Execute operations on unrecognized webhook sources

### Rate Limits

- 20 webhook workflow executions per minute
- All external API calls subject to budget constraints defined in OpenRouter Management API

### Error Handling

Unhandled exceptions → fail-closed state → drop payload → log stack trace → alert human operator via Telegram. No automated recovery attempt.

---

## 4. MCP Servers

### Local MCP (Build Time)

Registered in `.claude/settings.json`. Provides structured tool access for the Build Agent.

**Requires explicit human approval for:**
- Any tool with `delete`, `drop`, `mutate`, or `destroy` in its name or description
- Any tool that modifies billing state or IAM policies

### Remote MCP — Linear (`mcp.linear.app`)

Official Linear MCP server. Allows the runtime agent to:
- Query issues and team state
- Append comments
- Transition issue statuses

**Never auto-approve destructive Linear tools.**

---

## Autonomy Separation Summary

| Dimension | Build Agent | Runtime Agent |
|-----------|-------------|---------------|
| Can `terraform apply` | No | No |
| Can deploy to Railway | Yes (non-destructive) | N/A |
| Can create Linear issues | No | Yes |
| Can send Telegram messages | No | Yes |
| Can merge to `main` | No | No |
| Can delete resources | No | No |
| Human approval for infra changes | Always | Always |
| Session logging in JOURNEY.md | Required | Via structured log |
