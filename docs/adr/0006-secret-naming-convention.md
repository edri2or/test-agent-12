# ADR-0006: Secret Manager naming convention — kebab-case canonical

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Operator (`edriorp38@or-infra.com`), Claude Code (build agent)

## Context and Problem Statement

The operator-populated GCP project `or-infra-templet-admin` contained 22 pre-existing secrets, predominantly named in `UPPER_SNAKE_CASE` (`TELEGRAM_BOT_TOKEN`, `CLOUDFLARE_API_TOKEN`, …). The codebase, by contrast, references all Secret Manager names in `lower-kebab-case` (`telegram-bot-token`, `cloudflare-api-token`, …) — used consistently across `CLAUDE.md`, `terraform/variables.tf`, `.github/workflows/bootstrap.yml`, and `tools/bootstrap.sh`, with no UPPER_SNAKE deviations found at the time of writing. Two operator secrets were already kebab-case (`cloudflare-dns-manager-token`, `cloudflare-dns-manager-token-id`).

A canonical naming convention must be established so that `bootstrap.yml` and downstream consumers can resolve secrets unambiguously, and so that the operator's existing UPPER_SNAKE_CASE secrets coexist with the new canonical set without collision.

## Decision Drivers

- **Code reality.** Kebab-case is already the de facto convention throughout the template (IaC, workflows, runbooks); UPPER_SNAKE is not used for Secret Manager names anywhere in the repository.
- **GCP idiom.** Google's own documentation and tooling examples consistently use kebab-case for secret names; the alphabet is restricted to `[a-z0-9-]` for many tooling integrations.
- **Coexistence.** Operator's UPPER_SNAKE secrets may be referenced by external tooling (Cloud Run jobs, ad-hoc scripts) outside this repository. Renaming risks breakage.
- **Auditability.** A single canonical name per secret simplifies rotation, IAM scoping, and cross-session state diffing.

## Considered Options

1. **Adopt UPPER_SNAKE_CASE** — refactor every kebab reference in the template (terraform, workflows, tools, runbooks).
2. **Adopt kebab-case (canonical) and create kebab copies of operator's UPPER_SNAKE secrets** — leave originals untouched.
3. **Add a runtime alias resolver** — wrap every secret read with a function that tries both styles.

## Decision Outcome

**Chosen option:** Option 2 — kebab-case is canonical; copy values from existing UPPER_SNAKE secrets into new kebab-case secrets.

Rationale: zero refactor cost in the template; preserves any external dependencies on the UPPER_SNAKE names; matches GCP idiom; avoids the runtime overhead and subtle correctness traps of Option 3 (e.g., divergent versions between aliases).

### Consequences

**Good:**
- The codebase, IaC, and runbooks remain unchanged. `bootstrap.yml` and the Skills Router continue to reference kebab-case names with zero migration.
- External consumers of the UPPER_SNAKE secrets are unaffected.
- New secrets going forward must be created in kebab-case — easy to enforce via lint or pre-commit.

**Bad / accepted trade-offs:**
- Two parallel copies of the same value exist for six secrets, doubling rotation work until the UPPER_SNAKE originals are retired.
- Drift risk: if a value changes in one and not the other, downstream behavior diverges. Mitigation: rotation should target the kebab-case canonical entry; UPPER_SNAKE copies are read-only legacy.
- Mild storage cost (negligible at GCP Secret Manager pricing).

## Validation

1. After this ADR is merged, every new Secret Manager secret added by `bootstrap.yml`, terraform, or operator scripts MUST use `lower-kebab-case`. Pattern: `^[a-z][a-z0-9-]*$`.
2. Inventory verification (read-only):
   ```bash
   gcloud secrets list --project=or-infra-templet-admin \
     --filter="name~'^projects/.*/secrets/[a-z][a-z0-9-]*$'" \
     --format="value(name)"
   ```
   Should list ≥9 kebab-case secrets as of 2026-05-01: `cloudflare-account-id`, `cloudflare-api-token`, `cloudflare-dns-manager-token`, `cloudflare-dns-manager-token-id`, `linear-api-key`, `linear-webhook-secret`, `openrouter-management-key`, `railway-api-token`, `telegram-bot-token`.
3. The bootstrap workflow's existing references at `bootstrap.yml:152,157-163,336-340` resolve to live secrets — no name lookup failures.

## Links

- `docs/bootstrap-state.md` — current GCP secrets inventory and reconciliation table.
- `docs/JOURNEY.md` 2026-05-01 (post-PR #15) entry — diagnostic record of decision.
- ADR-0004 — runtime guardrails (defines `openrouter-runtime-key` daily cap; mandates `openrouter-management-key` for provisioning).
