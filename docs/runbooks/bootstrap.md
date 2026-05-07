# Bootstrap Runbook

**Governing contract:** [ADR-0007](../adr/0007-inviolable-autonomy-contract.md) — Inviolable Autonomy Contract. **Three scopes** (per ADR-0007's "Honest scope amendment" 2026-05-01): (1) one-time GCP handshake; (2) one-time-global §E.1 setup for autonomous multi-clone; (3) per-clone vendor floors (R-04, R-07, R-10). The "one touch ever" framing applies only to scope (1).

---

## Path C — Recommended for clones-after-the-first: GitHub-driven (ADR-0012)

Once the template-builder repo itself has been bootstrapped (Path A or B) **and** the §E.1 one-time-global pre-grants are in place, every future clone provisions through a `workflow_dispatch` on the template-builder repo. **Zero Cloud Shell touches per clone.**

### One-time-global operator pre-grants (performed once, ever, for the entire org's clone lifecycle — NOT per clone)

These are the last operator touches **for clone-provisioning**. After these steps land, every future clone is fully bootstrapped via a single `workflow_dispatch` from Claude Code. (Per-clone vendor floors R-04/R-07/R-10 still apply at the moment a clone wants to use Telegram + GitHub App + a dedicated Linear workspace; those are separate from clone provisioning.)

**Sub-step 1a: org-level role expansion on the existing runtime SA.**

```bash
SA="github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com"
ORG_ID=905978345393                     # or-infra.com

gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:$SA" \
  --role="roles/resourcemanager.projectCreator" --condition=None

gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:$SA" \
  --role="roles/resourcemanager.organizationViewer" --condition=None

# Note: org-level billing.user is included here for completeness but it
# does NOT propagate to the billing account if the billing account isn't
# "owned by or transferred to" the organization. See sub-step 1b for the
# binding that actually grants billing.resourceAssociations.create on the
# specific billing account. Do this anyway — it's harmless and matches the
# org IAM pattern of the other SAs (`terraform-sa`, `claude-admin-sa`).
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:$SA" \
  --role="roles/billing.user" --condition=None
```

**Sub-step 1b: billing-account-level grant — must be done from the original billing-account creator's account.**

Org-level `roles/billing.user` does not propagate to a billing account that isn't "owned by or transferred to" the organization. For billing accounts created from a personal Google account before the Workspace existed, only the gmail account can grant SA-level billing roles. See ADR-0012 §E.1 for the full rationale and the three iterations that landed on this step.

```bash
# Switch the active gcloud account to the gmail account that originally
# created the billing account.
gcloud auth login edri2or@gmail.com   # or `gcloud config set account ...`

# billing.user — link/unlink projects to the billing account (the create flow).
gcloud billing accounts add-iam-policy-binding 014D0F-AC8E0F-5A7EE7 \
  --member="serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com" \
  --role="roles/billing.user"

# billing.viewer — list projects on the billing account (lets
# probe-billing-projects.yml diagnose the 5/10-project soft-cap before
# it blocks an apply-system-spec dispatch). billing.user alone is
# insufficient: it permits `link`/`unlink` but NOT `billing.projects.list`.
# Added 2026-05-02 after live diagnostic on apply-system-spec runs
# 25253910937 / 25254068938 / 25254227982.
gcloud billing accounts add-iam-policy-binding 014D0F-AC8E0F-5A7EE7 \
  --member="serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com" \
  --role="roles/billing.viewer"
```

Risk note: see [R-11](../risk-register.md#r-11-runtime-sa-org-level-role-expansion-adr-0012). The runtime SA's WIF provider has `attributeCondition: assertion.repository == 'edri2or/autonomous-agent-template-builder'`, so the org-level bindings are only exercisable from CI on this exact repo.

**Sub-step 2: store a PAT as `gh-admin-token` in GCP Secret Manager.**

```bash
read -rsp "Paste PAT (scopes: repo, workflow, admin:org): " PAT; echo
printf '%s' "$PAT" | gcloud secrets create gh-admin-token \
  --data-file=- \
  --replication-policy=automatic \
  --project=or-infra-templet-admin
unset PAT
```

The PAT lives in the same `or-infra-templet-admin` project as the other platform tokens. Preferred form: a fine-grained token scoped to the `edri2or` org.

**Sub-step 3: ensure `is_template=true` on the source template repo.**

Already done as of 2026-05-01 (Q-Path). Re-running is harmless:

```bash
gh api -X PATCH repos/edri2or/autonomous-agent-template-builder -F is_template=true
```

**Sub-step 4: factory-folder OrgPolicy override (only if the org enforces `iam.allowedPolicyMemberDomains`).**

If your org enforces `iam.allowedPolicyMemberDomains` (default: deny `allUsers`), the per-clone `bootstrap.yml` Phase 4 cannot grant `allUsers run.invoker` on the Cloud Run receiver, and the receiver can't accept GitHub OAuth callbacks (R-07 fails with `FAILED_PRECONDITION: One or more users named in the policy do not belong to a permitted customer`).

Override the constraint at the **factory folder** so all current and future clones inherit `allowAll`. This is a folder-scope override — it does NOT relax the org-level constraint for any other folder. Run from the **workspace-admin account** (the folder lives in the Workspace org, the gmail account does NOT have `orgpolicy.policy.set` on it):

```bash
gcloud auth login edriorp38@or-infra.com   # or your workspace-admin account
gcloud services enable orgpolicy.googleapis.com   # on Cloud Shell's billing project — typically your gmail-owned project
sleep 30   # API propagation
cat > /tmp/policy.yaml <<'EOF'
name: folders/667201164106/policies/iam.allowedPolicyMemberDomains
spec:
  rules:
    - allowAll: true
EOF
gcloud org-policies set-policy /tmp/policy.yaml
```

Validated end-to-end 2026-05-02 on `folders/667201164106` (the factory folder for `autonomous-agent-test-clone-N` clones). After this binding, every clone provisioned under this folder inherits the override — no per-clone work for any future clone.

Skip this sub-step if your org doesn't enforce `iam.allowedPolicyMemberDomains` (most non-Workspace and many Workspace orgs do not).

### Per-clone provisioning (Claude Code-driven)

Claude Code dispatches `provision-new-clone.yml` with four inputs (`new_repo_name`, `new_project_id`, `parent_folder_id`, `billing_account_id`) and one optional input (`github_owner`, default `edri2or`). The workflow:

1. Authenticates to GCP via the existing WIF on this repo.
2. Reads `gh-admin-token` from Secret Manager.
3. Creates the new repo via `gh api repos/.../generate`.
4. Runs `tools/grant-autonomy.sh` end-to-end against the new project (CI mode — `SECRETS_SOURCE_PROJECT=or-infra-templet-admin` so platform-secret reads point at the template-builder's project).
5. Reports the new clone's IDs in the workflow step summary.

See [ADR-0012](../adr/0012-github-driven-clone-provisioning.md) for the full design. The Q-Path JOURNEY entry (2026-05-01) is the binding proof that the underlying ADR-0011 §1 auto-create works end-to-end.

---

## Path D — Post-Provisioning Activation (clone-side)

**Trigger:** read this when the current Claude session is operating on a clone repo (NOT the template-builder), and the clone has been provisioned by Path C / `provision-new-clone.yml` but not yet activated. Path C ends with the GCP project + WIF + runtime SA + GitHub Variables in place; Path D documents what the operator + agent do next to get the clone fully operational.

**Detection heuristic (for Claude sessions):** this is a clone if `github.repository != 'edri2or/autonomous-agent-template-builder'`. To confirm activation is incomplete, check `gcloud secrets list --project=$GCP_PROJECT_ID --filter='name:github-app-id'` — if empty, GitHub App not yet registered → Path D applies.

**Why a separate path:** Phase E (ADR-0012) made provisioning autonomous, but three vendor floors per ADR-0007 §"Honest scope amendment" remain forever per child instance: R-07 (GitHub App 2-click manifest flow), R-04 (Telegram bot 1-tap, vendor anti-abuse), R-10 (Linear has no `createWorkspace` API). Path D orders the residual surface and defines the "activated" success state — gaps that `provision-new-clone.yml` alone cannot close.

### Sequence

**Prerequisites (set by `apply-system-spec.yml` → `apply-railway-spec.yml` automatically):**
- GitHub Variables `APP_NAME` and `WEBHOOK_URL` must be set on the clone repo before bootstrap runs. `apply-railway-spec.yml` creates the Railway project, the n8n service domain, and sets both variables automatically. If dispatching bootstrap manually (not via `apply-system-spec.yml`), set these first: `APP_NAME` = desired GitHub App name; `WEBHOOK_URL` = `https://<n8n-railway-domain>/webhook/github`. Without `WEBHOOK_URL`, n8n's own `WEBHOOK_URL` and `N8N_EDITOR_BASE_URL` env vars are left empty on Phase 3 (auto-filled on re-run once the domain is known).

**Pre-flight checklist (Claude-driven manual path — verify ALL before dispatching bootstrap):**

| Check | How to verify | Auto-set? |
|-------|--------------|-----------|
| `APP_NAME` set on clone repo | `GET /repos/{clone}/actions/variables/APP_NAME` | ❌ Set manually or via spec |
| Railway n8n service has a domain | Dispatch `read-railway-domain.yml` on template-builder | ✅ `apply-railway-provision.yml` now creates it |
| `WEBHOOK_URL` set on clone repo | `GET /repos/{clone}/actions/variables/WEBHOOK_URL` | ✅ `apply-railway-provision.yml` now sets it automatically |

If `WEBHOOK_URL` is missing despite `apply-railway-provision.yml` having run: the n8n domain may not have been created. Dispatch `apply-railway-provision.yml` again — it will create the domain and set `WEBHOOK_URL` automatically.

If `APP_NAME` is missing: bootstrap Phase 4 will be **silently skipped** (the `github-app-registration` job condition is `vars.APP_NAME != ''`). Bootstrap summary will now show a `⚠ Phase 4 SKIPPED` warning. Set `APP_NAME` and re-run bootstrap.

1. **Set up GitHub App registration input.** Set GitHub Variable `APP_NAME` (the App's display name) on the clone repo. `apply-system-spec.yml` sets this from `metadata.name` in the spec. Required because `bootstrap.yml` gates Phase 4's `github-app-registration` job on `vars.APP_NAME != ''`.

2. **Dispatch `bootstrap.yml` on this clone repo.** What each phase does:
   - **Phase 1** — generates n8n secrets (encryption key, bcrypt admin password hash) + provisions the OpenRouter runtime key via Management API + injects all to the clone's GCP Secret Manager.
   - **Phase 2** — Terraform apply (WIF, Secret Manager containers, Cloudflare DNS).
   - **Phase 3** — injects Railway env vars into the n8n service (`N8N_ENCRYPTION_KEY`, `N8N_INSTANCE_OWNER_*`, `N8N_RUNNERS_ENABLED=false`, `N8N_PORT=5678`, `WEBHOOK_URL`, `N8N_EDITOR_BASE_URL`) and the agent service (`GCP_PROJECT_ID`, `OPENROUTER_*`, `TELEGRAM_*`). **Note:** `N8N_PROTOCOL` is intentionally NOT set — Railway terminates TLS at the load balancer; n8n must bind plain HTTP. Setting `N8N_PROTOCOL=https` without SSL certs crashes n8n on startup.
   - **Phase 4** — deploys temporary Cloud Run receiver, prints URL to Step Summary.
   - **Phase 5** — dispatches `deploy.yml` to trigger the first agent (TypeScript Skills Router) build on Railway. This is required because `serviceConnect` in `apply-railway-spec.yml` wires the repo but does not trigger a build; the agent service stays "offline" until `deploy.yml` runs.

3. **R-07 vendor floor — 2 browser clicks.** Operator visits the URL printed in Phase 4: clicks "Create GitHub App" → clicks "Install" on the resulting page. The Cloud Run receiver auto-injects `github-app-id` + `github-app-private-key` + `github-app-webhook-secret` + `github-app-installation-id` into the clone's GCP Secret Manager and updates the `APP_INSTALLATION_ID` GitHub Variable automatically. The workflow polls for up to 10 minutes then tears down the receiver. See [R-07](../risk-register.md#r-07-github-app-cloud-run-bootstrap-receiver) for the lifecycle test.

   **R-07 recovery — if `/install-callback` shows an error page or "manual step needed" page:**
   The GitHub App installation completes on GitHub's side regardless of receiver errors. Act **immediately** — bootstrap polls for `github-app-installation-id` for 10 minutes from when Phase 4 started; recovery must land within that window or bootstrap must be re-dispatched.

   1. Get the `installation_id`: read it from the partial page the receiver displays, **or** call `GET /orgs/{org}/installations` and find the app by slug.
   2. Dispatch `write-clone-secret.yml` on the template-builder repo:
      - `clone_project_id` = clone's GCP project ID
      - `secret_name` = `github-app-installation-id`
      - `secret_value` = the installation ID
   3. Set the `APP_INSTALLATION_ID` repo variable on the clone: `POST /repos/{clone}/actions/variables` with `{"name":"APP_INSTALLATION_ID","value":"<id>"}`.
   4. If more than 9 minutes have elapsed since Phase 4 started (polling has timed out): re-dispatch `redispatch-bootstrap.yml` after completing steps 1–3.

4. **R-04 vendor floor — Telegram bot.** Either:
   - **(a) Pre-create per clone (recommended for active clones):** follow §1f below to create the bot via `@BotFather`, then export the token to the clone's GCP Secret Manager as `telegram-bot-token` (kebab-case canon, ADR-0006).
   - **(b) Defer:** if the clone won't immediately use Telegram routing, leave `telegram-bot-token` unset. Runtime workflows that need it will fail-closed until provisioned.
   - See [R-04](../risk-register.md#r-04-telegram-bot-creation-automation-revised-twice--see-history-below) for the vendor-floor rationale.

5. **R-10 — Linear workspace decision.** Choose:
   - **L-pool (default):** all clones share the operator's existing Linear workspace + the existing `linear-api-key` (in template-builder's Secret Manager). Acceptable when Linear data is operator-private and trust-isolated. The runtime SA on the clone needs cross-project Secret Manager access on `or-infra-templet-admin` to read `linear-api-key` — grant via `roles/secretmanager.secretAccessor` on that specific secret.
   - **L-silo (opt-in):** operator creates a fresh Linear workspace via UI per clone, generates a new API key, exports as `linear-api-key` in the clone's own Secret Manager. Required when clone-level data isolation is wanted; vendor-blocked from automation since Linear has no `createWorkspace` mutation.
   - See [R-10](../risk-register.md#r-10-linear-has-no-createworkspace-api--vendor-blocked-silo-isolation).

### Success criteria — clone is "activated" when ALL of these hold

- `gcloud secrets list --project=$GCP_PROJECT_ID` includes: `github-app-id`, `github-app-private-key`, `github-app-webhook-secret`, `github-app-installation-id`, `n8n-encryption-key`, `n8n-admin-password-hash`, `openrouter-runtime-key`.
- GitHub Variable `APP_INSTALLATION_ID` is set on the clone repo (auto-set by the receiver's `/install-callback`).
- n8n service on Railway is **ACTIVE** (not CRASHED). If CRASHED, check that `N8N_PROTOCOL` is NOT set in the service's env vars — if it is, re-run Phase 3 with the current bootstrap.yml (the var is removed).
- Agent service on Railway is **ACTIVE** — Phase 5 dispatches `deploy.yml` to trigger the first build. If still offline after Phase 5, check the `deploy.yml` run in the clone's Actions tab.
- `telegram-bot-token` is reachable (either in clone's Secret Manager for L-silo / per-clone bot, or in template-builder's with cross-project read binding for shared use), OR explicitly deferred per step 4(b).
- `linear-api-key` is reachable per the L-pool / L-silo decision in step 5.

### Operator surface (per child instance — irreducible per ADR-0007)

| Step | What | Where | Why irreducible |
|------|------|-------|-----------------|
| 3a | "Create GitHub App" click | github.com browser | GitHub manifest flow; 1-click on GHEC preview |
| 3b | "Install" click | github.com browser | OAuth install consent |
| 4 | `@BotFather` /newbot OR Managed Bots tap | Telegram | Vendor anti-abuse |
| 5 (silo only) | Create Linear workspace | linear.app browser | No `createWorkspace` API |

**Total irreducible operator clicks per clone: 2 (R-07) + 1 (R-04) + optional 1 (R-10 silo).** Note: the `APP_INSTALLATION_ID` paste (formerly step 3c) is now automated — the receiver's `/install-callback` writes the installation ID to Secret Manager and updates the GitHub Variable automatically. Acknowledged. Documented. No code workaround possible for the remaining vendor floors; tracked in CLAUDE.md §"Honest scope" and the risk register.

---

## Path A — Original: `tools/grant-autonomy.sh` (one Cloud Shell command)

For operators who have already created their platform accounts and stored credentials in GCP Secret Manager (kebab-case canonicals per [ADR-0006](../adr/0006-secret-naming-convention.md)). The single trust handshake — **once per child instance**.

Per [ADR-0010](../adr/0010-clone-gcp-project-isolation.md) + [ADR-0011 §1](../adr/0011-silo-isolation-pattern.md), `GCP_PROJECT_ID` MUST be a fresh GCP project dedicated to this child instance. Reusing a project across clones silently overwrites the prior clone's kebab-case secrets (`railway-project-id`, `n8n-encryption-key`, etc.) — the project boundary IS the secret namespace boundary.

Two modes are supported:

- **ADR-0011 §1 auto-create (recommended):** export `GCP_BILLING_ACCOUNT` + one of `GCP_PARENT_FOLDER`/`GCP_PARENT_ORG`. The script runs `gcloud projects create` + `gcloud billing projects link` itself. Pre-grants needed once globally on the parent: `roles/resourcemanager.projectCreator` + `roles/billing.user`.
- **ADR-0010 manual fallback:** pre-create the project in the GCP Console; the script detects it exists and skips creation.

```bash
# Open https://shell.cloud.google.com — gcloud is already authenticated.
export GH_TOKEN=ghp_xxx                                      # PAT, repo+workflow+admin:org
export GITHUB_REPO=owner/repo                                # e.g. edri2or/autonomous-agent-template-builder
export GCP_PROJECT_ID=fresh-project-for-this-clone           # ⚠️ unique per clone (ADR-0010)

# Optional (ADR-0011 §1 auto-create). Omit to use ADR-0010 manual fallback.
export GCP_PARENT_FOLDER=123456789012                        # OR GCP_PARENT_ORG=987654321098
export GCP_BILLING_ACCOUNT=ABCDEF-ABCDEF-ABCDEF

bash tools/grant-autonomy.sh
```

The script:
- Enables required GCP APIs (idempotent).
- Creates the GCS Terraform state bucket.
- Creates the runtime SA and grants it the role set the runtime needs.
- Creates the WIF pool + provider, restricted to this exact repo via `assertion.repository`.
- Sets `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`, `GCP_PROJECT_ID`, `GCP_REGION`, `TF_STATE_BUCKET`, `N8N_OWNER_EMAIL` as GitHub repo Variables.
- Syncs `telegram-bot-token`, `cloudflare-api-token`, `openrouter-management-key`, `railway-api-token` from GCP Secret Manager to GitHub Secrets (the workflows that consume them via `${{ secrets.* }}` until they migrate to in-workflow Secret Manager fetching).
- Verifies the trust handshake.
- **No SA key is ever minted, stored, or shipped.** WIF is the sole identity backbone from the first GitHub Actions run.

After completion, every Claude Code session has full autonomy on this repo — see ADR-0007 forbidden-words list for what the agent must never request thereafter.

---

## Path B — Legacy: `tools/one-shot.sh` (for fresh template instantiations)

If you are creating a brand-new instance from this template and have **not** pre-populated GCP Secret Manager, use the original 7-credential collection flow below. This path mints a temporary SA key in `secrets.GOOGLE_CREDENTIALS`, which `bootstrap.yml` deletes from GitHub Secrets after WIF is provisioned. **Note:** the SA key in GCP itself is not auto-revoked — manual cleanup required.

**End-to-end footprint:**

1. Collect 7 platform credentials (one time, browser-only).
2. Export them as env vars and run `./tools/one-shot.sh`.
3. Click 2 buttons in the GitHub Actions summary: **Create GitHub App** + **Install**.

That's it.

---

## How the automation works

```
You: export {7 platform credentials}
        ↓
You: ./tools/one-shot.sh
        ↓
one-shot.sh (local):
  • encrypts and writes all GitHub Secrets via REST API (libsodium sealed-box)
  • writes all GitHub Variables via REST API
  • creates the bootstrap GitHub Environment (no reviewers — solo operator)
  • triggers .github/workflows/bootstrap.yml
        ↓
bootstrap.yml (GitHub Actions cloud runner):
  1. Auth to GCP — WIF if available, otherwise GOOGLE_CREDENTIALS SA key
  2. Generate n8n secrets (CSPRNG encryption key, bcrypt admin password hash)
  3. Inject all secrets → GCP Secret Manager
  4. terraform apply  (creates WIF pool/provider, IAM, buckets)
  5. Auto-update GCP_WORKLOAD_IDENTITY_PROVIDER + GCP_SERVICE_ACCOUNT_EMAIL as
     GitHub Variables, then DELETE the GOOGLE_CREDENTIALS secret
  6. Inject Railway env vars (variableCollectionUpsert GraphQL mutation)
  7. github-app-registration job: deploy temporary Cloud Run receiver,
     print the operator URL, poll Secret Manager for credentials, tear down
        ↓
You: visit Actions URL → 2 clicks → done
```

References:
- [`tools/one-shot.sh`](../../tools/one-shot.sh)
- [`.github/workflows/bootstrap.yml`](../../.github/workflows/bootstrap.yml)
- [`src/bootstrap-receiver/main.py`](../../src/bootstrap-receiver/main.py) — the Cloud Run callback service ([R-07](../risk-register.md#r-07-github-app-cloud-run-bootstrap-receiver))

---

## Step 1 — Collect platform credentials (one-time)

Each of these is a one-time browser action because of billing verification, OAuth consent, or hard platform constraints. No local CLI is required for any of them.

### 1a. GCP — project + service account key (first run only)

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a project, link a billing account. Note the **Project ID**.
3. Enable APIs (run in browser-based [Cloud Shell](https://shell.cloud.google.com)):

   ```bash
   gcloud services enable iam.googleapis.com iamcredentials.googleapis.com \
     secretmanager.googleapis.com sts.googleapis.com cloudresourcemanager.googleapis.com \
     run.googleapis.com artifactregistry.googleapis.com \
     --project="${PROJECT_ID}"
   ```

4. Create a temporary service account with `roles/owner` and download a JSON key.
   This key is required **only for the first bootstrap run** and is auto-deleted
   from GitHub Secrets by `bootstrap.yml` once terraform creates the WIF pool.

   ```bash
   gcloud iam service-accounts create bootstrap-bootstrap \
     --project="${PROJECT_ID}"
   gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
     --member="serviceAccount:bootstrap-bootstrap@${PROJECT_ID}.iam.gserviceaccount.com" \
     --role="roles/owner"
   gcloud iam service-accounts keys create key.json \
     --iam-account="bootstrap-bootstrap@${PROJECT_ID}.iam.gserviceaccount.com"
   cat key.json   # copy this JSON → export GOOGLE_CREDENTIALS='...'
   ```

> **WIF supersedes the SA key on the very first run.** After terraform provisions
> the WIF pool, `bootstrap.yml` writes the provider name + SA email back as
> GitHub Variables and deletes the `GOOGLE_CREDENTIALS` secret. Subsequent runs
> use WIF only — no static keys ever live in GitHub or the repository.

### 1b. GitHub App — automated to 2 browser clicks ([R-07](../risk-register.md#r-07-github-app-cloud-run-bootstrap-receiver))

You do nothing here in advance. The `github-app-registration` job in
`bootstrap.yml` deploys a temporary GCP Cloud Run service that serves a
pre-filled GitHub App Manifest form, handles the OAuth callback, and writes
`github-app-id`, `github-app-private-key`, and `github-app-webhook-secret`
directly into Secret Manager.

The Actions step summary will print a URL. Open it, click **Create GitHub App**,
then click **Install** on the resulting page. The Cloud Run service is torn
down automatically.

The only credential you need to set in advance is `GITHUB_TOKEN` (a PAT with
`repo` + `workflow` scopes), which `one-shot.sh` uses to write the GitHub
configuration on your behalf.

### 1c. Railway — account token

1. Sign up at [railway.app](https://railway.app) (GitHub OAuth).
2. Create a project and link your GitHub repo.
3. **Account Settings → Tokens → New Token.** Use an **account token**, not a
   project token — `variableCollectionUpsert` requires account-scope.
4. Note the **API Token**. (Project / Environment / Service IDs can be
   exported later as optional vars; the bootstrap workflow does not require
   them in dry-run.)

### 1d. Cloudflare — API token + Account ID ([R-01](../risk-register.md#r-01-cloudflare-oidc-gap))

1. Log in at [cloudflare.com](https://cloudflare.com), add your domain, follow
   the registrar nameserver instructions.
2. **Profile → API Tokens → Create Token → template: Edit Cloudflare Workers.**
   Scope it to your specific zone + Worker only.
3. Copy the **API Token** (shown once) and the **Account ID** from the
   dashboard right sidebar.

### 1e. OpenRouter — Management API key

1. Sign up at [openrouter.ai](https://openrouter.ai).
2. Add billing credits.
3. **Settings → API Keys → Create Management Key.**

### 1f. Telegram — `@BotFather` ([R-04, ADR-0011 §3 deferred — vendor floor](../adr/0011-silo-isolation-pattern.md))

**Status (2026-05-01, after ADR-0011 Phase D session):** Telegram Bot API 9.6 (April 2026) introduced Managed Bots, but per Telegram's anti-abuse policy a per-bot recipient confirmation tap is **non-removable**. ADR-0011 §3 was deferred until the vendor surfaces a fully programmatic path. R-04 is now classified `HITL_TAP_REQUIRED_PER_CLONE`. The manual flow below remains the working contract.

1. Open Telegram → find `@BotFather`.
2. Send `/newbot`, follow prompts, copy the **HTTP API Token**.
3. Send a message to your new bot, then visit
   `https://api.telegram.org/botYOUR_TOKEN/getUpdates` and note the `chat.id`.

### 1g. Linear — optional / deferred

Skip for the initial bootstrap. Add `LINEAR_API_KEY` and `LINEAR_WEBHOOK_SECRET`
to GCP Secret Manager later when you wire up the Linear integration.

### 1h. `WEBHOOK_URL` — required before GitHub App registration

The GitHub App webhook URL is **baked into the App at registration time** and
cannot be changed later without manual GitHub UI surgery. The bootstrap
workflow fails-closed if `WEBHOOK_URL` is not set.

Predict your n8n webhook URL from the planned Railway service hostname, e.g.:

```bash
export WEBHOOK_URL="https://<n8n-service>-<project>.up.railway.app/webhook/github"
```

`one-shot.sh` writes this as a GitHub repo Variable. If you don't know the
final hostname yet, deploy n8n first (`deploy.yml`), copy the URL from
Railway, then re-run `one-shot.sh` with `WEBHOOK_URL` exported before the
`github-app-registration` job runs.

---

## Step 2 — Run `one-shot.sh`

```bash
export GITHUB_TOKEN=ghp_...
export GCP_PROJECT_ID=my-project
export RAILWAY_API_TOKEN=...
export CLOUDFLARE_API_TOKEN=...
export CLOUDFLARE_ACCOUNT_ID=...
export TELEGRAM_BOT_TOKEN=...
export OPENROUTER_MANAGEMENT_KEY=...
export GOOGLE_CREDENTIALS='{"type":"service_account",...}'   # first run only

./tools/one-shot.sh
```

The script:
- Validates required env vars and aborts if any are missing.
- Encrypts each secret with the repository public key (libsodium sealed box via PyNaCl) and PUTs it via the GitHub REST API.
- Sets all plaintext variables via the GitHub REST API.
- Creates the `bootstrap` GitHub Environment with no required reviewers.
- Triggers `bootstrap.yml` via `workflow_dispatch` and prints the Actions URL.

Optional variables — `RAILWAY_PROJECT_ID`, `RAILWAY_ENVIRONMENT_ID`,
`RAILWAY_*_SERVICE_ID`, `TELEGRAM_CHAT_ID`, `CLOUDFLARE_ZONE_ID`,
`N8N_OWNER_EMAIL`, `APP_NAME`, `GCP_REGION`, `TF_STATE_BUCKET` — are all set
to safe defaults if you don't export them. You can re-run the script any time
to update them.

---

## Step 3 — Two browser clicks

1. Open the Actions URL printed by `one-shot.sh`.
2. When the `github-app-registration` job posts its step summary, click the
   linked URL.
3. Click **Create GitHub App** on the GitHub form.
4. Click **Install** on the page that follows.

The job polls Secret Manager for up to 10 minutes; once `github-app-id` is
written, it advances and the cleanup step deletes the Cloud Run service.

---

## Step 4 — After bootstrap

1. **Trigger the first deploy** by pushing to `main` — `deploy.yml` runs
   automatically and pushes the agent + n8n services to Railway and the edge
   Worker to Cloudflare.
2. **Set `APP_INSTALLATION_ID`** as a GitHub Variable (one click in
   Settings → Variables) once the install completes — the install ID is shown
   on the GitHub App settings page after step 3.
3. **Validate n8n:** `https://YOUR_N8N_URL/healthz` should return
   `{"status":"ok"}`. Then import `src/n8n/workflows/telegram-route.json`,
   `linear-issue.json`, `health-check.json`, and `openrouter-infer.json` via
   the n8n UI and activate them with the correct env vars.
4. **n8n owner account ([R-06](../risk-register.md#r-06-n8n-owner-account-restart-behavior-2170)):**
   `N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true` (n8n ≥2.17.0) creates the owner
   from env vars on first boot. Trigger a Railway redeploy and confirm the
   owner record is not destructively re-created. Record the result in
   `docs/risk-register.md`.

---

## Rollback

See [`rollback.md`](rollback.md). All rollback operations can be triggered
via GitHub Actions or the Railway/GCP dashboards — no local CLI required.
