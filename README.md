# autonomous-agent-template

A GitHub Template Repository that bootstraps a secure, autonomous software orchestration platform end-to-end.

## What This Template Provides

A new project created from this template includes:

- **Identity & Security** — GCP Workload Identity Federation (WIF/OIDC); no static service account keys
- **Runtime** — TypeScript Skills Router (zero npm dependencies) + n8n orchestrator on Railway
- **Edge** — Cloudflare DNS + Workers via wrangler-action
- **LLM Gateway** — OpenRouter with programmatic key rotation and $10/day budget cap
- **Project Management** — Linear bidirectional GitHub PR sync + official MCP server
- **HITL Communication** — Telegram bot for alerts, approvals, and manual overrides
- **Policy-as-Code** — OPA/Conftest Rego policies block merges on documentation drift
- **Audit** — Append-only `JOURNEY.md` session log + structured external logging
- **IaC** — Terraform for GCP WIF, Secret Manager, and Cloudflare DNS
- **Rollback** — CLI-based reversion paths; destructive cleanup is always human-gated

## Architecture

```
GitHub → GitHub Actions (OPA → Terraform plan → Deploy)
                                     │
                         ┌───────────┴───────────┐
                      Railway                Cloudflare
                  (TS Router + n8n)          (DNS + Workers)
                         │
                  GCP Secret Manager
                  (all secrets injected by human)
                         │
              ┌──────────┼──────────┐
           OpenRouter  Linear    Telegram
```

## The single bootstrap action — once per child instance

This template is governed by an **Inviolable Autonomy Contract** ([ADR-0007](docs/adr/0007-inviolable-autonomy-contract.md), see top of [`CLAUDE.md`](CLAUDE.md)). The contract permits exactly **one** operator action per child instance cloned from this template — `tools/grant-autonomy.sh`.

**Per [ADR-0010](docs/adr/0010-clone-gcp-project-isolation.md) + [ADR-0011](docs/adr/0011-silo-isolation-pattern.md), each child instance MUST live in its own dedicated GCP project.** Secret names are un-prefixed kebab-case ([ADR-0006](docs/adr/0006-secret-naming-convention.md)), so the GCP project boundary IS the namespace boundary; reusing one project across multiple clones silently overwrites secrets. ADR-0011 §1 (Phase C) extends `tools/grant-autonomy.sh` with `gcloud projects create` + `gcloud billing projects link` so the project is auto-created when the operator exports `GCP_BILLING_ACCOUNT` + parent. Back-compat: when those are unset, the script falls through to ADR-0010 manual mode and expects `GCP_PROJECT_ID` to already exist.

### Path C (Recommended for clones-after-the-first) — GitHub-driven via [ADR-0012](docs/adr/0012-github-driven-clone-provisioning.md)

After the template-builder repo itself is bootstrapped, every future clone provisions through a `workflow_dispatch` on the template-builder repo — **zero Cloud Shell touches per clone**. Claude Code dispatches `provision-new-clone.yml` with the new clone's name + GCP project ID and the workflow creates the GitHub repo from the template, creates the GCP project, sets up WIF, and syncs secrets end-to-end.

The operator's only remaining surface is a one-time-global setup (performed once, ever, for the entire org's clone lifecycle): bind two org-level roles on the existing runtime SA, store one PAT as `gh-admin-token` in Secret Manager, and ensure `is_template=true`. Details in [`docs/runbooks/bootstrap.md`](docs/runbooks/bootstrap.md) Path C and [ADR-0012 §E.1](docs/adr/0012-github-driven-clone-provisioning.md).

### Path A (chicken-egg) — Cloud Shell `tools/grant-autonomy.sh`

For the very first clone (before the template-builder itself exists, or for direct-bootstrapping the template-builder), the original Cloud Shell path remains supported:

```bash
# In GCP Cloud Shell (gcloud already authenticated as project owner OR
# as a principal with projectCreator+billing.user on the parent folder/org)
export GH_TOKEN=ghp_...                       # PAT, repo + workflow + admin:org
export GITHUB_REPO=your-org/your-new-repo
export GCP_PROJECT_ID=fresh-project-for-this-clone   # ⚠️ unique per child instance

# Optional — ADR-0011 §1 auto-create. Skip these to use ADR-0010 manual mode
# (in which case GCP_PROJECT_ID must already exist).
export GCP_PARENT_FOLDER=123456789012        # OR GCP_PARENT_ORG=987654321098
export GCP_BILLING_ACCOUNT=ABCDEF-ABCDEF-ABCDEF

bash tools/grant-autonomy.sh
```

The script creates the WIF pool/provider/SA, sets all GitHub Variables, syncs platform secrets from GCP Secret Manager to GitHub Secrets, and verifies. **No SA key is ever minted, stored, or shipped.** WIF is the sole identity backbone from the first run. After this script succeeds, every future Claude Code session has full autonomy — the operator is never asked for another action on this clone.

The remaining bootstrap of the runtime cluster (terraform-managed resources, n8n encryption keys, runtime OpenRouter key) flows through `bootstrap.yml` triggered by the agent. See [`docs/runbooks/bootstrap.md`](docs/runbooks/bootstrap.md) for the full handshake walkthrough.

### Pre-existing operator state (already done — never re-asked)

| Platform | Where the credential lives in GCP Secret Manager |
|----------|--------------------------------------------------|
| GCP project + billing | n/a (live binding, owner role) |
| Railway account + API token | `railway-api-token` |
| Cloudflare account + API token | `cloudflare-api-token`, `cloudflare-account-id` |
| Telegram bot — **vendor floor: 1 tap per clone** ([R-04, ADR-0011 §3 deferred](docs/adr/0011-silo-isolation-pattern.md)). Bot API 9.6 Managed Bots can reduce per-clone setup to one tap, but the tap is non-removable per Telegram anti-abuse policy. Today: operator-provided `telegram-bot-token` per clone. | `telegram-bot-token` |
| OpenRouter Provisioning Key | `openrouter-management-key` |
| Linear workspace + API key | `linear-api-key`, `linear-webhook-secret` |
| GitHub App ([R-07](docs/risk-register.md#r-07-github-app-cloud-run-bootstrap-receiver), 2-click manifest flow per child instance) | `github-app-id`, `github-app-private-key`, `github-app-webhook-secret` (auto-injected by Cloud Run receiver) |
| n8n encryption key + admin owner | `n8n-encryption-key`, `n8n-admin-password-hash` (auto-generated by `bootstrap.yml`) |

## Autonomy Boundaries

This template enforces a strict two-layer autonomy model:

- **Build-Agent Autonomy** (Claude Code while scaffolding): see [`CLAUDE.md`](CLAUDE.md) section A and [`docs/autonomy/build-agent-autonomy.md`](docs/autonomy/build-agent-autonomy.md)
- **Runtime-System Autonomy** (deployed n8n + TS Router): see [`CLAUDE.md`](CLAUDE.md) section B and [`docs/autonomy/runtime-system-autonomy.md`](docs/autonomy/runtime-system-autonomy.md)

## Development

```bash
npm run build      # compile TypeScript
npm run test       # run Jest unit tests
npm run dev        # run TS router locally
npm run deploy     # railway up (requires Railway linked)

terraform -chdir=terraform fmt
terraform -chdir=terraform validate
terraform -chdir=terraform plan   # requires GCP credentials
```

## Policy Enforcement

CI blocks merges when:

- `src/` changes without updates to `docs/JOURNEY.md` **and** `CLAUDE.md`
- `terraform/` changes without a new ADR in `docs/adr/`

See [`policy/`](policy/) for Rego source.

## Security

See [`SECURITY.md`](SECURITY.md) for vulnerability disclosure policy and secrets handling rules.

**Never commit secrets.** All credentials are injected by a human operator into GCP Secret Manager and retrieved at runtime.

## License

MIT
