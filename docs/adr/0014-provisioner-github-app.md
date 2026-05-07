# ADR-0014: Replace gh-admin-token PAT with a Dedicated Provisioner GitHub App

**Date:** 2026-05-03
**Status:** Accepted
**Deciders:** Operator + Claude Code

## Context and Problem Statement

All provisioning workflows on the template-builder (creating clone repos, setting GitHub Variables/Secrets, dispatching workflows on clones) authenticate via a Classic PAT stored as `gh-admin-token` in `or-infra-templet-admin` Secret Manager. Classic PATs are tied to a human user account, do not expire by default, carry overly broad scopes (`repo + workflow + admin:org`), and GitHub has declared intent to eventually allow organizations to disable them entirely. Fine-grained PATs went GA in March 2025 and GitHub Apps are the current industry standard for long-lived org-level automation.

## Decision Drivers

- Classic PATs are tied to a human user — if the user leaves the org, all provisioning breaks
- No token expiration → leaked token grants indefinite org-wide access
- GitHub's roadmap: orgs will be able to block Classic PATs; `gh-admin-token` as Classic PAT is end-of-life technology
- GitHub Apps provide short-lived tokens (8 h), 3× higher API rate limits, and a clear non-human audit identity
- The template-builder's `or-infra-templet-admin` has **no GitHub App at all** — Phase 4 (R-07) was never run on it, so the current runtime App pattern does not exist there either

## Considered Options

1. **Keep `gh-admin-token` as Classic PAT** — no work, but security debt grows; org policy may block it
2. **Upgrade to fine-grained PAT** — safer scopes + expiration, but still user-bound, still a PAT
3. **Dedicated Provisioner GitHub App** — org-level App, short-lived tokens, not user-bound, full audit trail ← **chosen**

## Decision Outcome

**Chosen option: Dedicated Provisioner GitHub App**, because it eliminates the human-user dependency, aligns with the 2025 industry standard, and enables the operator to remove `gh-admin-token` from Secret Manager entirely after migration.

### App specification

| Field | Value |
|-------|-------|
| Name | `autonomous-agent-provisioner` |
| Organization | `edri2or` |
| Installation scope | **All repositories** (current + future) |
| Webhook | none — API-only, no webhook needed |

### Required permissions

**Repository-level:**

| Permission | Level | Required for |
|-----------|-------|-------------|
| `administration` | write | `repos/generate` (create clone from template); `DELETE /repos/{owner}/{repo}` (destroy-clone skill); manage repo settings |
| `contents` | write | push content, clone |
| `secrets` | write | set GitHub Secrets on new clones (`grant-autonomy.sh`) |
| `variables` | write | set GitHub Variables on new clones (`grant-autonomy.sh`, `apply-railway-provision.yml`) |
| `workflows` | write | `workflow_dispatch` on clones (`redispatch-bootstrap`, `apply-system-spec`, bootstrap Phase 5) |
| `metadata` | read | baseline — required by GitHub for all Apps |

### New secrets in `or-infra-templet-admin` SM

| Secret name | Description |
|-------------|-------------|
| `provisioner-app-id` | GitHub App ID (integer, public) |
| `provisioner-app-private-key` | RSA private key for JWT signing |
| `provisioner-app-installation-id` | Installation ID for the `edri2or` org installation |

### Consequences

**Good:**
- `gh-admin-token` can be deleted from `or-infra-templet-admin` SM after migration
- Tokens auto-expire after 8 h — no leaked-credential-lives-forever risk
- Actions appear in GitHub audit log as `autonomous-agent-provisioner[bot]`, not as a human user
- API rate limit: 15,000 req/h per installation (vs 5,000 for PAT)
- Clones no longer need `gh-admin-token` copied into their SM (replaced by `provisioner-app-private-key`)
- `inject-gh-admin-token.yml` becomes obsolete and can be removed

**Bad / accepted trade-offs:**
- One-time registration requires the R-07-style manifest flow (2 browser clicks — GitHub vendor floor, unavoidable)
- All workflows consuming `gh-admin-token` must be updated to use `actions/create-github-app-token`
- `tools/grant-autonomy.sh` CI mode receives `GH_TOKEN` from the caller; callers must pass the App token
- `repos/generate` (create from template) has a known GitHub limitation: new repos are not auto-added to the App's permission list when created via template endpoint. Mitigation: install App at org level (`all repositories`) so all repos — including newly created ones — are automatically covered

## Implementation Plan

### Phase 1 — Register the App (one-time, this ADR)

New workflow: `.github/workflows/register-provisioner-app.yml`
- Deploys a Cloud Run receiver (extends `src/bootstrap-receiver/main.py` with three small parameterizations: manifest permissions driven by env var, secret name prefix driven by env var (`SECRET_PREFIX=provisioner-app-`), and `WEBHOOK_URL` made optional — the provisioner App has no webhook; then deploy with `APP_NAME=autonomous-agent-provisioner`)
- Serves manifest form with the permissions above
- On `/callback`: exchanges code, stores `provisioner-app-id` + `provisioner-app-private-key` in `or-infra-templet-admin` SM
- On `/install-callback`: stores `provisioner-app-installation-id` in SM
- Tears down Cloud Run service after SM write

### Phase 2 — Migrate all workflows

Workflows to update (replace `gh-admin-token` read + `GH_TOKEN` usage):

| File | Current usage | Change |
|------|--------------|--------|
| `provision-new-clone.yml` | create repo, grant-autonomy, copy token to clone SM | use `actions/create-github-app-token`; copy `provisioner-app-id` + `provisioner-app-private-key` to clone SM instead of `gh-admin-token` |
| `redispatch-bootstrap.yml` | dispatch bootstrap.yml on clone | use `actions/create-github-app-token` |
| `apply-system-spec.yml` | dispatch apply-railway-spec + apply-cloudflare-spec | use `actions/create-github-app-token` |
| `apply-railway-spec.yml` | GitHub API calls | use `actions/create-github-app-token` |
| `apply-cloudflare-spec.yml` | GitHub API calls | use `actions/create-github-app-token` |
| `cleanup-test-agents.yml` | delete repos | use `actions/create-github-app-token` |
| `apply-railway-provision.yml` | set WEBHOOK_URL variable on clone | use `actions/create-github-app-token` |
| `bootstrap.yml` Phase 5 | dispatch deploy.yml on clone | read `provisioner-app-id` + `provisioner-app-private-key` from clone SM; use `actions/create-github-app-token` |
| `inject-gh-admin-token.yml` | copy PAT to clone SM | **deprecate** — replaced by Provisioner App credentials |

### Phase 3 — Cleanup

- Delete `gh-admin-token` from `or-infra-templet-admin` SM
- Remove `inject-gh-admin-token.yml`
- Update `CLAUDE.md` secrets inventory

## Destroy-clone skill

Test clones accumulate quickly and must be cleaned up. The Provisioner App's existing `administration: write` permission already covers `DELETE /repos/{owner}/{repo}` — no new permission is needed.

A `destroy-clone` n8n skill will be added (extending ADR-0005's HITL destroy pattern) to delete a clone root-and-branch across all three platforms:

| Step | Action | Platform |
|------|--------|----------|
| 0 | Operator sends natural-language destroy intent via Telegram | Telegram |
| 1 | Skills Router matches `destroy-clone` skill (`requires_approval: true`), returns `pending_approval` | Skills Router |
| 2 | n8n workflow sends Approve/Deny inline-keyboard showing repo URL + Railway project + GCP project ID | Telegram inline-keyboard |
| 3 (approved) | `projectDelete` mutation | Railway GraphQL |
| 4 | `gcloud projects delete <project-id>` (enters 30-day soft-delete; recoverable) | GCP Resource Manager |
| 5 | `DELETE /repos/{owner}/{repo}` via Provisioner App token | GitHub API |

**Order rationale:** Railway and GCP deleted first (both reversible: Railway project can be restored; GCP has 30-day recovery window). GitHub repo deleted last — it is the audit trail.

**HITL gate:** Step 2 is mandatory and non-bypassable, following the exact ADR-0005 two-workflow pattern (`destroy-resource.json` + `approval-callback.json`). See ADR-0005 for the `callback_data` format (`dr:<verb>:<type_short>:<resource_id>`) — destroy-clone extends this with new type shorts `gh` (GitHub repo) and `gc` (GCP project) alongside the existing `rs` (Railway service).

**GCP permission note:** The runtime SA already has `roles/owner` on clone projects (created via `grant-autonomy.sh`). Project deletion requires `resourcemanager.projects.delete` which is included in `roles/owner`. No new GCP IAM binding needed.

## Validation

After Phase 1: dispatch `register-provisioner-app.yml` → confirm `provisioner-app-id` exists in SM.
After Phase 2: dispatch `provision-new-clone.yml` for a test clone → confirm no `gh-admin-token` reads in workflow logs.
CI: `policy/context_sync.rego` enforces CLAUDE.md + JOURNEY.md update on any `src/` change.

## Links

- [ADR-0012 — GitHub-driven clone provisioning](0012-github-driven-clone-provisioning.md)
- [ADR-0007 — Inviolable Autonomy Contract](0007-inviolable-autonomy-contract.md)
- [ADR-0005 — Destroy-resource approval callback](0005-destroy-resource-approval-callback.md)
- [actions/create-github-app-token](https://github.com/actions/create-github-app-token)
- [GitHub Apps vs PATs — GitHub Docs](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/deciding-when-to-build-a-github-app)
- [Fine-grained PATs GA — March 2025](https://github.blog/changelog/2025-03-18-fine-grained-pats-are-now-generally-available/)
- [Railway oops-proofed deletion](https://blog.railway.com/p/how-we-oops-proofed-infrastructure-deletion-on-railway)
- [Gruntwork — Destroying Infrastructure with Pipelines](https://docs.gruntwork.io/2.0/docs/pipelines/tutorials/destroying-infrastructure/)
