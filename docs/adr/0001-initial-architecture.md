# ADR-0001: Initial System Architecture

**Date:** 2026-04-30
**Status:** Accepted
**Deciders:** Platform Architect, Claude Code Build Agent

## Context and Problem Statement

A new autonomous software orchestration platform must be architected. The platform requires secure identity management, automated deployments, LLM inference routing, external workflow orchestration, and a human-in-the-loop communication layer, all while adhering to least-privilege security principles and supporting zero-touch CI/CD.

## Decision Drivers

- Eliminate static long-lived service account keys in CI/CD pipelines
- Enable fully automated deployments with cryptographic trust (WIF/OIDC)
- Separate build-time scaffold autonomy from runtime system autonomy
- Support human-gated bootstrap for identity, billing, and root token creation
- Enforce documentation synchronization via Policy-as-Code

## Considered Options

1. **GCP WIF + Railway + n8n (selected)** — OIDC-based identity, Railway as runtime, n8n as orchestrator
2. **Static service account keys + Vercel** — Simpler but violates least-privilege; static keys are a persistent security liability
3. **AWS IAM + Lambda** — Native OIDC support but higher operational complexity and vendor lock-in

## Decision Outcome

**Chosen option:** Option 1 — GCP WIF + Railway + n8n, because it eliminates static credential management, provides native OIDC support in CI/CD, and integrates cleanly with the skills-router pattern proven in `project-life-133`.

### Consequences

**Good:**
- No static service account keys anywhere in the repository or CI environment
- Railway's native OIDC eliminates secret injection for deployments
- n8n's external secret mount pattern eliminates credential hardcoding in workflows
- TypeScript Skills Router requires zero runtime npm dependencies (proven pattern)
- OPA/Conftest policy gates prevent documentation drift deterministically

**Bad / accepted trade-offs:**
- Cloudflare Workers CI deployment requires API token (R-01: OIDC not natively supported without workarounds)
- n8n headless CLI may encounter port collisions (R-03: `N8N_RUNNERS_ENABLED=false` mitigation required)
- Initial bootstrap requires 7-9 human-gated steps before any automation can run

## Validation

- `terraform validate` in `terraform/` passes cleanly
- `npm run test` executes router unit tests (Jest)
- OPA/Conftest policy check in `.github/workflows/documentation-enforcement.yml` blocks PRs missing JOURNEY.md updates
- `terraform plan` outputs a valid execution plan (requires GCP credentials via WIF)

## Links

- `FINAL_SYNTHESIS_HANDOFF.md.md` — full architecture synthesis
- `docs/runbooks/bootstrap.md` — human bootstrap sequence
- `CLAUDE.md` — autonomy contracts
- R-01, R-02, R-03, R-04, R-05 in `docs/risk-register.md`
