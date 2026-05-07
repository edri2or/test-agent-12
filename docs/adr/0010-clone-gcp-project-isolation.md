# ADR-0010: Each template clone gets its own operator-managed GCP project

**Date:** 2026-05-01
**Status:** Accepted, **partially superseded by [ADR-0011](0011-silo-isolation-pattern.md) §1** (auto-creation in `grant-autonomy.sh`, Phase C)
**Deciders:** Claude Code (build agent), session `claude/adr-0010-clone-isolation`

> **Supersession note (2026-05-01, ADR-0011 Phase C):** ADR-0011 §1 extends `tools/grant-autonomy.sh` with `gcloud projects create` + `gcloud billing projects link` so the per-clone GCP project is auto-created when `GCP_BILLING_ACCOUNT` plus one of `GCP_PARENT_FOLDER`/`GCP_PARENT_ORG` are set. The "operator contract" section below describes the back-compat fallback path (used when those env vars are unset — this remains valid). The deferred collision-detection check in the "Detection / safety net" section **remains relevant**: ADR-0011's bash auto-create uses operator-specified project IDs (no random suffix), so accidental ID reuse across clones is still possible. The kebab-case-canon argument and the project-as-namespace-boundary decision both remain binding under ADR-0011.

## Context and Problem Statement

This repository is a **GitHub Template Repository**. Operators clone it to create new "child instances" (separate GitHub repos, each one a deployed autonomous-agent system). Each child instance writes secrets to GCP Secret Manager during `bootstrap.yml` Phase 1 and writes Railway IDs during `apply-railway-provision.yml` (ADR-0009). All secret names are kebab-case canonical (ADR-0006) and **un-prefixed**: e.g. `railway-project-id`, `n8n-encryption-key`, `openrouter-runtime-key`.

If two child instances bootstrap against the **same** GCP project, every kebab-case secret collides — the second clone silently overwrites the first's `railway-project-id`, `railway-environment-id`, etc. There is no per-clone prefix, no namespace, and no detection mechanism for this collision.

The codebase never creates a GCP project automatically:

- `terraform/gcp.tf` contains zero `google_project` resources.
- `tools/grant-autonomy.sh:32` requires the operator to export `GCP_PROJECT_ID` and runs `gcloud projects describe` (read-only) on it (`grant-autonomy.sh:58`).
- `bootstrap.yml:62` reads `vars.GCP_PROJECT_ID` from GitHub Variables (per-repo).

So the question is not "should the agent create the project?" — that path was rejected before this ADR (ADR-0007 forbids the operator providing a billing-account-bound credential the agent could use to create projects safely). The question is: **what is the contract operators must follow when they clone this template?**

## Decision Drivers

- **ADR-0007 inviolability** — no operator action beyond `tools/grant-autonomy.sh`. We can require the operator to use a particular GCP project at handshake time; we cannot add a second operator step.
- **Secret namespace integrity** — kebab-case secret names (ADR-0006) are canonical. Adding per-clone prefixes would break the canon and complicate every consumer (`bootstrap.yml`, `apply-railway-provision.yml`, n8n workflows, `src/agent/`).
- **Blast radius isolation** — a leaked credential in clone A must not be usable for clone B. Project-level IAM is the strongest GCP boundary: SAs cannot cross-project without explicit binding.
- **Operator cognitive load** — "create a fresh project for each child instance" is a one-line instruction. "Configure prefix variables, audit collisions" is a checklist that decays.
- **Rejected alternatives:**
  - **Per-secret prefix (`<clone-slug>-railway-project-id`):** changes ADR-0006 canon, touches every consumer file, requires a new variable that's easy to misconfigure.
  - **Auto-create project from `grant-autonomy.sh`:** requires `roles/billing.user` on the operator's billing account, plus a parent folder, plus the agent inheriting permissions to mutate billing — a major escalation of the bootstrap surface.

## Considered Options

1. **Option A — Per-clone GCP project, agent-created.** The agent's WIF SA gets `roles/resourcemanager.projectCreator` on the billing account; `bootstrap.yml` calls `gcloud projects create`. Rejected: increases the autonomy surface (billing-account-level mutation) and conflicts with ADR-0007's "no new operator-granted permissions" intent.
2. **Option B — Per-secret prefix within a shared GCP project.** Every secret becomes `<repo-slug>-<canonical-name>`. Rejected: breaks the ADR-0006 kebab-case canon and complicates every reader.
3. **Option C — Per-clone GCP project, operator-created at handshake (chosen).** The operator creates a fresh GCP project for each child instance (or reuses an empty one) and exports its ID as `GCP_PROJECT_ID` when running `tools/grant-autonomy.sh`. The handshake is still the **single permitted operator action** per ADR-0007 — we just clarify that this single action is **per child instance**, not once globally.

## Decision Outcome

**Chosen option:** Option C. Each child instance lives in its own operator-provided GCP project. The GCP project boundary IS the namespace boundary; secret names remain un-prefixed kebab-case under ADR-0006.

### Operator contract (binding)

When cloning this template to create a new child instance, the operator must:

1. Create (or pick a fresh, empty) GCP project. Recommended naming: `<purpose>-agent-<short-hash>` or any operator-chosen ID.
2. Bind a billing account to that project.
3. In Cloud Shell on that project, with `gcloud` authenticated as project owner:

   ```bash
   export GH_TOKEN=ghp_...                    # PAT scoped to the new repo
   export GITHUB_REPO=your-org/your-new-repo
   export GCP_PROJECT_ID=the-fresh-project-id  # ⚠️ MUST be unique per child instance
   bash tools/grant-autonomy.sh
   ```

After this single command per child instance, the autonomy contract takes over — no further operator touches on that clone.

The template-builder repo (`edri2or/autonomous-agent-template-builder`) itself runs against `GCP_PROJECT_ID=or-infra-templet-admin` — this **is** that repo's clone-of-itself project. Future clones MUST point to a different project ID.

### Detection / safety net

`tools/grant-autonomy.sh` should refuse to run if it detects a collision: if the target project already contains kebab-case secrets like `railway-project-id` AND a `bootstrap-state.md` snapshot reports a different `GITHUB_REPOSITORY` than the current one, abort with a diagnostic. (Implementation deferred — first clone hasn't happened yet; the abort logic lands when we wire it in real.)

### Consequences

**Good:**

- Project-level IAM is GCP's strongest isolation boundary — no cross-clone leakage.
- Secret naming canon (ADR-0006) is preserved unchanged.
- No new operator permissions or workflow code paths required.
- Maps 1:1 to GitHub repo per clone — easy mental model.
- Cost lives where it should: each child instance has its own billing line.

**Bad / accepted trade-offs:**

- Operator must remember to create a fresh project per clone. Mitigations: README + CLAUDE.md call this out; `grant-autonomy.sh` will (in a follow-up) detect collision and abort.
- The collision-detection follow-up isn't built yet — we ship the contract now and the safety check before the first real clone.
- If the operator accidentally reuses a project, the second clone overwrites the first's secrets silently. This is the failure mode the contract guards against; the safety check above closes it.

## Validation

- `docs/runbooks/bootstrap.md` updated with the per-clone instruction.
- `README.md` "Single bootstrap action" block updated to clarify `GCP_PROJECT_ID=fresh-project-per-clone`.
- `CLAUDE.md` HITL inventory row 1 updated to read "GCP project per child instance — operator creates a new one each time".
- Future ADR-XXXX will track the `grant-autonomy.sh` collision-detection check when it lands.

## Links

- ADR-0006 — Secret naming convention (kebab-case canon)
- ADR-0007 — Inviolable Autonomy Contract (single permitted operator action)
- ADR-0009 — Railway mutation workflow (consumer of `railway-*-id` secrets that this ADR namespaces by GCP project)
- `tools/grant-autonomy.sh` — handshake script, runs per child instance
- `docs/runbooks/bootstrap.md` — operator-facing handshake walkthrough
