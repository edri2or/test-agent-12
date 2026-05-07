# Runtime-System Autonomy Contract

**Context:** The deployed application cluster — TypeScript Skills Router + n8n Orchestrator — running on Railway after bootstrap completion.

This document is the normative reference for what the deployed autonomous system may and may not do during normal operation. It mirrors Section B of `CLAUDE.md` with additional operational guidance.

---

## Autonomous Actions (no human approval required)

### Communication

- Parse inbound Telegram text messages from known operator chat IDs
- Send Telegram text replies and status updates
- Log all intents and actions to structured external logging

### Repository Operations

- Read repository files via authenticated GitHub API
- Create branches from `main`
- Commit generated code to non-main branches
- Open pull requests (code review required before merge)
- Add comments to pull requests

### Project Management (Linear)

- Query issue metadata, team state, and cycle information
- Append comments to issues
- Transition issue statuses (e.g., "In Progress" → "In Review")
- Read project and milestone data

### Inference

- Send prompts to OpenRouter API
- Select fallback models based on real-time latency metrics
- Provision scoped sub-service API keys via OpenRouter Management API (within budget cap)
- Revoke sub-service keys on anomalous behavior detection

### Skills Routing

- Match inbound Telegram intents to `SKILL.md` definitions via Jaccard similarity
- Execute matched skills deterministically
- Defer complex API calls to n8n workflows via webhook triggers

---

## Actions Requiring Human Approval

| Action | Approval method |
|--------|----------------|
| Merge code to `main` | GitHub PR review |
| Destructive file operations | Telegram approval button prompt |
| Net-new cloud environment provisioning | Human operator confirmation |
| IAM policy alterations | Human operator + Terraform plan review |
| Exceeding OpenRouter daily budget cap | Human operator override |
| Any `delete`, `drop`, or `destroy` MCP tool invocation | Explicit Telegram confirmation |

---

## Forbidden Actions (runtime system)

| Action | Risk |
|--------|------|
| Delete GitHub repositories | Irreversible |
| Drop cloud databases | Unrecoverable data loss |
| Alter IAM permission policies | Privilege escalation |
| Merge code directly to `main` | Bypasses human review |
| Process webhooks without HMAC-SHA256 validation | Spoofing / unauthorized trigger (R-02) |
| Execute requests from unknown Telegram chat IDs | Social engineering vector |
| Exceed $10/day OpenRouter budget | Runaway cost |
| Make more than 20 n8n webhook calls/minute | Infinite loop exhaustion |

---

## Allowed External Network Calls

The runtime system's network egress is strictly limited to:

| Endpoint | Purpose |
|----------|---------|
| `api.linear.app` (GraphQL) | Project management |
| `api.telegram.org` | HITL communication |
| `openrouter.ai/api/v1` | LLM inference |
| `api.github.com` | Repository operations |
| `mcp.linear.app` | Linear MCP server |
| n8n internal Railway network | Workflow execution |
| GCP Secret Manager API | Secret retrieval at runtime |

All other egress should be blocked at the Railway network level.

---

## Error Containment

On any unhandled exception:

1. **Fail-closed** — drop the inbound payload
2. **Log** — append full stack trace to structured external logging
3. **Alert** — send error notification via Telegram to operator chat ID
4. **Do not recover** — no automated retry or recovery sequences
5. **Await** — human operator diagnosis and restart decision

This prevents cascading failures and ensures all anomalies are human-visible.

---

## Rate Limits

| Resource | Limit | Enforcement |
|----------|-------|-------------|
| OpenRouter daily spend | $10 USD | OpenRouter Management API budget |
| n8n webhook calls | 20/minute | n8n rate limiting configuration |
| GitHub API calls | Per GitHub App rate limits | Built-in |
| Telegram messages | 30 messages/second (Telegram limit) | Built-in |

---

## Kill Switches

Two independent kill switches immediately paralyze the runtime agent:

1. **Telegram kill switch** — Revoke the bot token via @BotFather (`/revoke`). Severs HITL interface and all inbound command processing.

2. **WIF kill switch** — Delete the GCP WIF provider:
   ```bash
   gcloud iam workload-identity-pools providers delete github-provider \
     --workload-identity-pool=github-pool \
     --location=global \
     --project=YOUR_PROJECT_ID
   ```
   Severs all CI/CD pipeline authentication. New deployments become impossible.

Use both in a security incident for maximum containment.

---

## Audit Requirements

Every intent and action must produce:

1. An entry in structured external logging (append-only, timestamped)
2. A JOURNEY.md-equivalent structured log entry for significant operations
3. Preservation of webhook request IDs for traceability

Audit logs must be retained for a minimum of 90 days and must be tamper-evident.
