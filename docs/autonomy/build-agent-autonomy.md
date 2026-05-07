# Build-Agent Autonomy Contract

**Context:** Claude Code CLI acting as the local scaffolding agent during template development and instantiation.

This document is the normative reference for what Claude Code may and may not do while operating in build-agent mode. It mirrors Section A of `CLAUDE.md` with additional operational guidance.

---

## Permitted Actions

### File Operations

| Action | Scope |
|--------|-------|
| Read any file | Entire repository |
| Edit source files | `src/`, `terraform/`, `policy/`, `.github/workflows/`, `docs/` |
| Create new files | ADRs in `docs/adr/`, skills in `src/agent/skills/`, unit tests in `src/agent/tests/`, config templates anywhere |
| Delete files | Deprecated code in `src/` only, outdated unit tests |

### Local Commands (non-destructive only)

```bash
npm run build          # TypeScript compilation
npm run test           # Jest unit tests
npm run dev            # Local TS router execution
terraform fmt          # Format HCL
terraform validate     # Validate HCL syntax
terraform plan         # Execution plan (read-only)
railway status         # Check deployment status
git status/diff/log    # Read git state
git add/commit/push    # Stage and push changes
```

### Deployment

- `railway up` for non-destructive updates **only after** the local test suite passes in full

---

## Forbidden Actions

| Action | Reason |
|--------|--------|
| `terraform apply` | Mutates remote infrastructure state; requires human review of plan |
| `terraform destroy` | Irreversible resource deletion |
| `railway down` | Destructive for stateful services |
| Commit plaintext secrets | Violates secrets hygiene absolutely |
| Commit `.env` files with real values | Same |
| Automate Telegram bot creation | Platform-enforced human gate (R-04) |
| Automate GitHub App registration | OAuth consent boundary |
| Download and execute unverified binaries | Supply chain risk |
| Modify branch protection rules via API | Repository governance boundary |
| Delete cloud databases or networks | Unrecoverable state destruction |
| Alter IAM permission policies | Privilege escalation risk |
| Use `--no-verify` git flag | Bypasses safety hooks |
| Force-push to `main` | Destroys shared history |

---

## Halt Conditions

Claude Code **must stop immediately and print human instructions** when:

1. **Missing secret:** A secret is required to continue scaffold generation.
   - Print: "HALT: Missing secret `SECRET_NAME`. Run: `gcloud secrets create SECRET_NAME --replication-policy=automatic`"
   - Wait for human confirmation before continuing.

2. **3x validation failure:** A local validation command fails three consecutive times despite patching attempts.
   - Append the failure to `docs/risk-register.md`
   - Request human arbitration

3. **Evidence conflict:** An instruction in `FINAL_SYNTHESIS_HANDOFF.md.md` contradicts official vendor documentation.
   - Defer to official documentation
   - If unresolvable, append to `docs/risk-register.md` and halt

4. **Human-gated boundary encountered:** Any item from the `human-actions.md` checklist is required.
   - Print the exact instructions the human operator must follow
   - Provide copy-paste-ready commands
   - Do not attempt to bypass or simulate the human action

---

## Session Protocol

Every Claude Code session must:

1. Read `CLAUDE.md` (root) first
2. Append a timestamped entry to `docs/JOURNEY.md` before any file edits
3. Run `npm run test` and `terraform plan` before pushing to any branch
4. Update `CLAUDE.md` if system architecture or dependencies change
5. Create or update an ADR in `docs/adr/` if infrastructure dependencies change
6. Document any new risk in `docs/risk-register.md`

---

## Conflict Resolution Order

1. `FINAL_SYNTHESIS_HANDOFF.md.md` (primary source of truth)
2. Official vendor documentation (supersedes repo templates on implementation details)
3. Repository templates (fallback for unspecified details)

If (1) and (2) conflict: document in `docs/risk-register.md` and halt for human arbitration.
