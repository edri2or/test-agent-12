# ADR-0013: Spec language and generic provisioner skeleton (goal ב)

**Date:** 2026-05-02
**Status:** Accepted
**Deciders:** Build agent (Claude Code, claude-opus-4-7), operator

## Context and Problem Statement

Phase 1 (goal א — self-cloning of this template) is operational. Validated end-to-end on `autonomous-agent-test-clone-10` 2026-05-02 via `provision-new-clone.yml` + `bootstrap.yml` + the manifest 2-click flow. The template-builder now reliably produces a working agent stack with one operator action per clone (R-07 + R-04 + R-10 vendor floors, see [ADR-0007](0007-inviolable-autonomy-contract.md)).

Phase 2 (goal ב — *arbitrary-system provisioning from natural-language spec*) is not yet started. The end-state is a deployed runtime agent that accepts "build me system X" as a Telegram intent and provisions every required resource from scratch under the [ADR-0007 autonomy contract](0007-inviolable-autonomy-contract.md). This ADR scopes the foundational design choices so implementation can begin in parallel modules. Per [issue #51](https://github.com/edri2or/autonomous-agent-template-builder/issues/51), no implementation PR may merge until this ADR is Accepted.

The four structural choices below are coupled: the spec language fixes what the provisioner consumes; the boundary fixes where the LLM hand-off happens; the home repo fixes the blast radius of Phase 2 changes; the validation pipeline fixes how spec errors get caught. Each is decided in isolation, but the recommendation in §Decision Outcome is a coherent quadruple.

## Decision Drivers

- **ADR-0007 inviolability** — Phase 2 must not introduce new vendor floors beyond R-04/R-07/R-10. Any new floor surfaces here as a blocker, tracked in `docs/risk-register.md`.
- **Reuse over reinvent** — `tools/grant-autonomy.sh`, `provision-new-clone.yml`, `apply-railway-provision.yml`, and `bootstrap.yml` already encode the working primitives. Phase 2 must call them as library functions, not parallel-implement them.
- **Failure containment** — the provisioner mutates real cloud accounts. Spec validation must catch shape errors before any side effect; runtime failures must be idempotent (re-runnable without orphaning resources).
- **Auditability** — every "build me X" run produces a workflow run in this repo's Actions history, the spec used, and a typed manifest of resources created. This is the audit trail; nothing else is.
- **Operator legibility** — a human reading a stored spec must be able to predict the resources that will be created. Specs that route through a free-form LLM at provision time fail this test.

## Considered Options

### A. Spec language shape

1. **YAML + JSON-Schema** — typed, declarative, human-readable. The spec file is the contract; JSON-Schema validates shape pre-flight; the provisioner is a switch over schema-defined fields. Aligns with how `provision-new-clone.yml` already takes typed `workflow_dispatch` inputs.
2. **Terraform module shape (HCL)** — leverage the Terraform ecosystem (state, plan/apply, providers). The spec *is* a `terraform.tfvars` against a generic module. Inherits HCL semantics + provider maturity.
3. **Opinionated intent DSL (custom)** — a higher-level language that captures intent ("a webhook-driven agent with a Postgres + a Redis") and compiles down to concrete provider calls. Maximum legibility; maximum implementation cost.

### B. Intent → spec compiler boundary

1. **Direct NL → workflow** — Telegram message routes to an n8n workflow that calls an LLM, which directly invokes provisioner workflows. No persisted spec.
2. **NL → typed spec → workflow** — Telegram message routes to a new `spec-compile` skill that produces a JSON spec, validates it against the schema, posts it back to Telegram for HITL approval, then dispatches the provisioner with the spec as input. The spec is stored in the resulting workflow's run artifacts.
3. **NL → spec → IR → workflow** — additional intermediate "intermediate representation" layer between spec and provisioner. The IR is a flattened execution plan (DAG of provider calls). Most flexible; most surface area.

### C. Phase 2 home repo

1. **Continue on `autonomous-agent-template-builder`** — same repo as Phase 1. CI, ADR set, JOURNEY, secrets, WIF all reusable.
2. **Split into a new `autonomous-agent-runtime` repo** — the template *builder* is for Phase 1 (self-cloning); a new repo is for Phase 2 (arbitrary-system provisioning). Cleaner conceptual split.

### D. Spec validation pipeline

1. **JSON-Schema validation in CI** — every spec PR'd into a `specs/` directory in this repo runs `ajv validate` against the JSON-Schema. Pre-merge.
2. **OPA/Rego policy on top of JSON-Schema** — adds policy ("no spec may request more than 5 services", "all secrets must be in Secret Manager"). Reuses existing `policy/` infrastructure.
3. **Skip validation, fail at runtime** — provisioner does its own validation; no CI gate. Cheapest; weakest signal.

## Decision Outcome

**Accepted:** **A.1 + B.2 + C.1 + D.2** — YAML + JSON-Schema spec, NL → typed spec → workflow boundary with Telegram HITL approval at the spec stage, continue on `autonomous-agent-template-builder`, JSON-Schema + OPA/Rego validation in CI for any spec checked in. Operator confirmed all four decisions 2026-05-02 (chat session `claude/continue-work-3VUho`).

Justification:

- **A.1 over A.2/A.3:** Terraform (A.2) is the right tool for individual provider mutations and may be invoked *by* the provisioner, but it is the wrong shape for the cross-provider top-level spec — Phase 1's working primitives are GitHub Actions workflows, not a Terraform root module, and forcing all of them into Terraform regresses the autonomy contract (Terraform state lives somewhere; CI dispatches do not). A custom DSL (A.3) is premature abstraction; YAML+JSON-Schema captures every Phase 1 input shape (`provision-new-clone.yml` inputs, `bootstrap.yml` Variables, Railway service list, Cloudflare zone) without adding a compiler.
- **B.2 over B.1/B.3:** the persisted spec is the audit artifact and the HITL gate. B.1 collapses both into a free-form LLM call at provision time, which is unauditable and contradicts ADR-0005's destroy-resource pattern (HITL on destructive operations applies a fortiori to *creation*). B.3 is a layer too many for Phase 2 v0; the IR can be added later if the schema-to-workflow switch becomes unwieldy.
- **C.1 over C.2:** Phase 2 reuses Phase 1's `tools/grant-autonomy.sh`, the §E.1 one-time-global pre-grants, the WIF backbone, and the GitHub App receiver. A split repo would either duplicate these (bad) or take a dependency on the template-builder repo (worse — circular). Splitting is reconsidered if/when Phase 2 surface dwarfs Phase 1, not before.
- **D.2 over D.1/D.3:** D.1 catches shape errors but not policy violations (resource ceilings, naming conventions, secret-handling rules). The `policy/` directory already runs OPA/Conftest in CI; Phase 2 specs route through the same gate. D.3 fails closed at runtime, but only after side effects may have started — too late.

### Concrete shape (subject to revision in implementation)

A spec file at `specs/<system-name>.yaml`:

```yaml
apiVersion: aatb.or-infra.com/v1
kind: SystemSpec
metadata:
  name: hello-world-agent
  description: "Minimal echo agent — Telegram intent → reply"
spec:
  gcp:
    projectId: or-hello-world-001
    region: us-central1
  github:
    repo: edri2or/hello-world-agent
    fromTemplate: edri2or/autonomous-agent-template-builder
  railway:
    services:
      - name: agent
        kind: typescript
        rootDir: src/agent
      - name: n8n
        kind: docker
        image: n8nio/n8n
  cloudflare:
    zone: hello-world.or-infra.com
    worker:
      name: hello-world-edge
      route: hello-world.or-infra.com/*
  secrets:
    # keys in GCP Secret Manager (kebab-case canon, ADR-0006)
    required:
      - openrouter-runtime-key
      - telegram-bot-token
  intent:
    # natural-language description that produced this spec; for audit only
    source: "build me a minimal echo agent with Telegram + OpenRouter"
```

The schema lives at `schemas/system-spec.v1.json` (JSON-Schema 2020-12). The provisioner workflow `apply-system-spec.yml` takes `spec_path` as `workflow_dispatch` input, validates against the schema, and dispatches one provider sub-workflow per top-level field (`gcp`, `github`, `railway`, `cloudflare`, `secrets`) — each sub-workflow already exists or wraps an existing primitive (`provision-new-clone.yml` for `gcp` + `github`, `apply-railway-provision.yml` for `railway`, etc.).

The intent → spec compiler is a new skill `spec-compile` in `src/agent/skills/` plus an n8n workflow `compile-spec.json`. The skill receives the NL string + the JSON-Schema, calls OpenRouter to emit a candidate spec, validates locally, and replies the spec to Telegram for approval. Approval triggers `apply-system-spec.yml` via the GitHub App; denial discards.

### Consequences

**Good:**

- Spec is the audit artifact and the HITL gate; LLM output is persisted and human-approved before any side effect.
- Provisioner is a switch over typed fields; each branch wraps an existing Phase 1 primitive — minimal new code, maximal reuse.
- CI gates every checked-in spec via JSON-Schema + OPA. Runtime-generated specs (compiled from NL) get the same JSON-Schema validation in the skill before the Telegram approval.
- No new vendor floor surfaced. R-04/R-07/R-10 still apply per child instance; Phase 2 inherits them.

**Bad / accepted trade-offs:**

- The schema must evolve as Phase 2 explores new resource shapes. Versioned via `apiVersion: aatb.or-infra.com/v1`; v2 ships with a compatibility shim, not a rewrite.
- The HITL approval at spec stage adds a per-build operator tap. This is *additive* to the runtime autonomy contract — accepted, because creation is high-blast-radius (matches ADR-0005's destroy-resource symmetry).
- Continuing on this repo (C.1) means Phase 2 changes share CI and ADR namespace with Phase 1 closure work. Mitigated by keeping Phase 2 code under a clear `src/spec/` + `specs/` + `schemas/` prefix, distinct from existing directories.

### What this ADR does NOT decide (deferred)

- The exact JSON-Schema field set beyond the example above. Schema design is the first implementation PR.
- The set of provider sub-workflows. Each is a separate PR after the schema lands.
- The Telegram HITL approval message format (inline keyboard shape, callback_data encoding). Reuses ADR-0005's pattern, exact bytes deferred.
- Whether the `spec-compile` skill calls OpenRouter directly or routes through n8n. Implementation detail.
- Multi-tenant spec namespacing if Phase 2 ever serves more than one operator. Out of scope until that's a real requirement.

## Validation

1. **Pre-merge (this ADR):** `markdownlint`, `markdown-invariants`, `lychee --offline`, OPA/Conftest — all green.
2. **Issue-discussion gate (fulfilled 2026-05-02):** all four open questions confirmed by operator in chat: A.1 (YAML + JSON-Schema), B.2 (NL → typed spec → workflow), C.1 (continue on this repo), D.2 (JSON-Schema + OPA/Rego in CI). See [issue #51](https://github.com/edri2or/autonomous-agent-template-builder/issues/51) for context.
3. **Post-Accepted, pre-implementation:** open a tracking sub-issue per top-level schema field (`gcp`, `github`, `railway`, `cloudflare`, `secrets`, `intent`). Each sub-issue ships independently.
4. **Phase 2 v0 acceptance criterion:** dispatching `apply-system-spec.yml` against the example `specs/hello-world-agent.yaml` produces a working clone at `edri2or/hello-world-agent` indistinguishable from one produced by `provision-new-clone.yml` directly. This is the regression test for "did we break Phase 1 by generalizing".

## Links

- [ADR-0007: Inviolable Autonomy Contract](0007-inviolable-autonomy-contract.md) — the binding constraint
- [ADR-0005: Destroy-resource HITL approval](0005-destroy-resource-approval-callback.md) — symmetric pattern for create-resource HITL at spec stage
- [ADR-0006: Secret naming convention (kebab-case)](0006-secret-naming-convention.md) — applies to spec `secrets.required` field
- [ADR-0010: Per-clone GCP project isolation](0010-clone-gcp-project-isolation.md) — the spec's `gcp.projectId` must always be a fresh project
- [ADR-0011: Silo isolation pattern](0011-silo-isolation-pattern.md) — vendor-floor inventory Phase 2 must not extend
- [ADR-0012: GitHub-driven clone provisioning](0012-github-driven-clone-provisioning.md) — the Phase 1 primitive `apply-system-spec.yml` wraps for the `gcp` + `github` fields
- [Risk register](../risk-register.md) — R-04/R-07/R-10 vendor floors Phase 2 inherits; new floors land here
- [Issue #51](https://github.com/edri2or/autonomous-agent-template-builder/issues/51) — current-focus issue, discussion home
- [JSON-Schema 2020-12](https://json-schema.org/draft/2020-12/release-notes)
