# ADR-0002: Web-Native Bootstrap via GitHub Actions

**Date:** 2026-04-30
**Status:** Accepted
**Deciders:** Claude Code (claude-sonnet-4-6), Operator

---

## Context

The initial project design assumed operator access to a local terminal with `gcloud`, `terraform`, and `railway` CLIs available. The `tools/bootstrap.sh` script was authored under that assumption.

The deployment environment is Claude Code on the web. No local CLI tooling is available or required. All automation must run through GitHub Actions cloud runners.

## Decision

Replace `tools/bootstrap.sh` (local CLI approach) with `.github/workflows/bootstrap.yml` (GitHub Actions `workflow_dispatch` workflow).

Key properties of the new approach:

- **Authentication:** WIF/OIDC — GitHub Actions token exchanged for short-lived GCP credential. No static service account keys.
- **Secret injection:** Secrets generated inside the runner (CSPRNG), written directly to GCP Secret Manager. Never touch GitHub Secrets or repository files.
- **Railway configuration:** Railway env vars set via GraphQL API (`variableCollectionUpsert`) using an account-level `RAILWAY_API_TOKEN` stored in GCP Secret Manager.
- **Terraform:** Runs `terraform apply` inside the runner using the WIF-derived credential. State stored in GCS.
- **GitHub App registration:** Cloud Run receiver deployed temporarily; operator completes 2 browser clicks; receiver is torn down (see ADR-0003 / R-07).
- **Human approvals:** The `bootstrap` GitHub Environment requires manual approval before the workflow executes, preserving the HITL gate.

## Consequences

**Positive:**
- Zero local tooling required — any operator with GitHub access can bootstrap.
- Audit trail via GitHub Actions logs (immutable, org-level retention).
- WIF removes the entire class of static credential leakage risk.

**Negative:**
- Operators must configure GitHub Secrets/Variables before triggering — more upfront UI work than a single CLI script.
- GitHub Actions runner environment differences from local shells could surface edge cases.
- `tools/bootstrap.sh` is now deprecated but retained for reference (local/air-gapped environments).

## Alternatives Considered

| Option | Reason rejected |
|--------|----------------|
| Keep `bootstrap.sh`, require local CLI | Not viable for web-only Claude Code environments |
| Codespaces / Dev Container | Adds dependency on GitHub Codespaces billing; unnecessary for a one-shot bootstrap |
| Cloud Shell | Requires GCP Console access before WIF is established — circular dependency |
