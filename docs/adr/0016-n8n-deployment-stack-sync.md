# ADR-0016: n8n Deployment Stack — Secret Names in GCP Secret Manager

**Date:** 2026-05-04
**Status:** Accepted
**Deciders:** template maintainer

## Context and Problem Statement

The template's `terraform/variables.tf` provisions GCP Secret Manager secrets via a `for_each` over `var.secret_names`. The original default list used kebab-case names (`railway-api-token`, `telegram-bot-token`, etc.) matching earlier conventions. The n8n/Railway deployment workflows (stages 2–6, ported from project-life-130) reference secrets by UPPER_CASE names (`RAILWAY_TOKEN`, `TELEGRAM_BOT_TOKEN`, `N8N_OWNER_PASSWORD`, etc.) via `google-github-actions/get-secretmanager-secrets@v2`. Both naming conventions must coexist in the provisioned set so the GCP project is ready for both the Terraform-managed infrastructure layer and the n8n operational layer.

## Decision Drivers

- Workflow stages fetch secrets by exact UPPER_CASE name; the secret must exist before any stage runs
- Terraform manages secret resource creation (not values); values are written out-of-band by operators or other workflows
- Adding names to the default list is additive and safe — Terraform creates empty secret resources, operators populate them
- kebab-case names are kept for backwards compatibility with existing probes and ADR-0006 conventions

## Considered Options

1. **Add UPPER_CASE names to `var.secret_names` default** — Terraform provisions all secrets at `terraform apply` time; workflows find them ready
2. **Create secrets imperatively in each workflow** — Each stage creates its own secrets if missing; complex, not idempotent across stages
3. **Rename kebab-case to UPPER_CASE only** — Breaking change for existing probes and ADR-0006 documentation

## Decision Outcome

**Chosen option:** Option 1 — add UPPER_CASE names to `var.secret_names` default alongside existing kebab-case names.

### Consequences

**Good:**
- A single `terraform apply` provisions the full secret set needed by all deployment stages
- Stages 2–6 can run immediately after provisioning without secret-not-found errors
- Additive change; no existing secrets or workflows are affected

**Bad / accepted trade-offs:**
- Two naming conventions coexist in the list (kebab-case legacy + UPPER_CASE operational); mitigated by inline comments
- Some conceptual duplication (e.g., `telegram-bot-token` and `TELEGRAM_BOT_TOKEN`) — operators must populate both if both consumers are used

## Validation

CI runs `terraform plan` on PRs touching `terraform/`. The plan output shows `google_secret_manager_secret` resources for each new name. Secrets receive values via the deployment workflows after `terraform apply`.

## Links

- PR: sync n8n/Railway stack from project-life-130 into template
- ADR-0006: secret naming convention (kebab-case for Terraform-managed secrets)
- ADR-0008: Railway provisioning
