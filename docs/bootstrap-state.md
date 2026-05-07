# Bootstrap State — Live Snapshot

**Purpose:** ground-truth record of the GCP project that backs this template, captured directly from `gcloud` read-only queries. Every Claude Code session reads this file first (per `CLAUDE.md` Session Protocol) so it knows what already exists before proposing changes. Refresh by re-running the **Refresh command** at the bottom and pasting the output here.

**Last verified:** 2026-05-01 (post-bootstrap.yml run 25213902199 — first autonomous Phase 1 dispatch succeeded; +4 secret containers)
**Reconciled by:** Claude Code (claude-opus-4-7), session `claude/bootstrap-verification-setup-XapRm`

---

## Project metadata

| Field | Value |
|-------|-------|
| `projectId` | `or-infra-templet-admin` |
| `projectNumber` | `974960215714` |
| Display name | Or Infra Template Admin |
| Lifecycle state | `ACTIVE` |
| Created | 2026-04-29T15:50:57Z |
| Billing | ENABLED |
| Billing account | `billingAccounts/014D0F-AC8E0F-5A7EE7` |
| Active region | `us-central1` (matches `bootstrap.yml:63` default) |
| Active operator | `edriorp38@or-infra.com` (`roles/owner`) |

---

## Enabled APIs

The following GCP APIs are **enabled** on the project (29 total — the 25 from pre-handshake state + 4 newly enabled by `tools/grant-autonomy.sh` Step 1: `iam`, `iamcredentials`, `sts`, `cloudresourcemanager`):

```
analyticshub.googleapis.com
artifactregistry.googleapis.com
bigquery.googleapis.com
bigqueryconnection.googleapis.com
bigquerydatapolicy.googleapis.com
bigquerydatatransfer.googleapis.com
bigquerymigration.googleapis.com
bigqueryreservation.googleapis.com
bigquerystorage.googleapis.com
cloudapis.googleapis.com
cloudresourcemanager.googleapis.com
cloudtrace.googleapis.com
dataform.googleapis.com
dataplex.googleapis.com
datastore.googleapis.com
iam.googleapis.com
iamcredentials.googleapis.com
logging.googleapis.com
monitoring.googleapis.com
run.googleapis.com
secretmanager.googleapis.com
servicemanagement.googleapis.com
serviceusage.googleapis.com
sql-component.googleapis.com
storage-api.googleapis.com
storage-component.googleapis.com
storage.googleapis.com
sts.googleapis.com
telemetry.googleapis.com
```

### All required APIs are present

(Previously this section listed `iam`, `iamcredentials`, `sts`, `cloudresourcemanager` as missing. They were enabled by `tools/grant-autonomy.sh:62-73` during the 2026-05-01 handshake.)

---

## Secret Manager inventory

36 secrets present (32 prior + 4 created by `apply-railway-provision.yml` run 25216580152 on 2026-05-01T13:44–13:45Z: `railway-project-id`, `railway-environment-id`, `railway-n8n-service-id`, `railway-agent-service-id` — per ADR-0009 storage pivot from GitHub Variables to GCP Secret Manager). Reconciled against `CLAUDE.md` Secrets Inventory (kebab-case canon). One secret was intentionally deleted on 2026-05-01 — see "Recently deleted secrets (do not recreate)" below.

| Actual name in GCP | Created | Status vs `CLAUDE.md` | Maps to |
|--------------------|---------|----------------------|---------|
| `ANTHROPIC_API_KEY` | 2026-04-29 | Extra (not in CLAUDE.md) | LLM router future use |
| `CLOUDFLARE_ACCOUNT_ADDITIONAL_API` | 2026-04-29 | Extra | Cloudflare auxiliary |
| `CLOUDFLARE_ACCOUNT_ID` | 2026-04-29 | Original (UPPER_SNAKE) — kebab copy below | (replaced by `cloudflare-account-id`) |
| `CLOUDFLARE_API_TOKEN` | 2026-04-29 | Original (UPPER_SNAKE) — kebab copy below | (replaced by `cloudflare-api-token`) |
| `CLOUDFLARE_USER_ADDITIONAL_API` | 2026-04-29 | Extra | Cloudflare auxiliary |
| `CLOUDFLARE_ZONE_ID` | 2026-04-29 | Extra (CLAUDE.md treats as Variable, not Secret) | — |
| `DEEPSEEK_API_KEY` | 2026-05-01 | Extra | LLM router future use |
| `GOOGLE_API_KEY` | 2026-04-29 | Extra | LLM router future use |
| `LINEAR_API_KEY` | 2026-04-29 | Original (UPPER_SNAKE) — kebab copy below | (replaced by `linear-api-key`) |
| `LINEAR_TEAM_ID` | 2026-04-29 | Extra | Linear runtime context |
| `LINEAR_WEBHOOK_SECRET` | 2026-04-29 | Original (UPPER_SNAKE) — kebab copy below | (replaced by `linear-webhook-secret`) |
| `OPENAI_API_KEY` | 2026-04-29 | Extra | LLM router future use |
| `OPENCODE_API_KEY` | 2026-04-29 | Extra | LLM router future use |
| `PERPLEXITY_API_KEY` | 2026-04-29 | Extra | LLM router future use |
| `RAILWAY_TOKEN` | 2026-04-29 | Original (UPPER_SNAKE) — kebab copy below | (replaced by `railway-api-token`) |
| `RAILWAY_WEBHOOK_SECRET` | 2026-04-29 | Extra | Railway webhook auth |
| `STRIPE_API_KEY` | 2026-05-01 | Extra | Payment integration future use |
| `TELEGRAM_BOT_TOKEN` | 2026-05-01 | Original (UPPER_SNAKE) — kebab copy below | (replaced by `telegram-bot-token`) |
| `TELEGRAM_CHAT_ID` | 2026-05-01 | Extra (CLAUDE.md treats as Variable, not Secret) | — |
| `cloudflare-account-id` | 2026-05-01T09:25:38 | ✅ Present (length=32) | `cloudflare-account-id` |
| `cloudflare-api-token` | 2026-05-01T09:25:46 | ✅ Present (length=53) | `cloudflare-api-token` |
| `cloudflare-dns-manager-token` | 2026-04-29 | ✅ Match (kebab-case correct) | (extra) |
| `cloudflare-dns-manager-token-id` | 2026-04-29 | ✅ Match (kebab-case correct) | (extra) |
| `linear-api-key` | 2026-05-01T09:25:54 | ✅ Present (length=48) | `linear-api-key` |
| `linear-webhook-secret` | 2026-05-01T09:26:01 | ✅ Present (length=64) | `linear-webhook-secret` |
| `n8n-admin-password-hash` | 2026-05-01T12:13–12:15 | ✅ Present (bcrypt — generated by bootstrap.yml run 25213902199) | `n8n-admin-password-hash` |
| `n8n-admin-password-plaintext` | 2026-05-01T12:13–12:15 | ✅ Present (sister of `-hash`, generated by bootstrap.yml run 25213902199) | `n8n-admin-password-plaintext` |
| `n8n-encryption-key` | 2026-05-01T12:13–12:15 | ✅ Present (CSPRNG hex, generated by bootstrap.yml run 25213902199) | `n8n-encryption-key` |
| `openrouter-management-key` | 2026-05-01T09:23:50 | ✅ Present (Provisioning Key — verified via `/api/v1/keys` 200) | `openrouter-management-key` |
| `openrouter-runtime-key` | 2026-05-01T12:13–12:15 | ✅ Present (provisioned via Management API — `limit: $10/day`, `limit_reset: daily`, ADR-0004) | `openrouter-runtime-key` |
| `railway-agent-service-id` | 2026-05-01T13:44–13:45 | ✅ Present (created by `apply-railway-provision.yml` run 25216580152, project `ff709798-aa1b-4c52-9a1f-f30b3294f2aa`, ADR-0009) | `railway-agent-service-id` |
| `railway-api-token` | 2026-05-01T09:26:08 | ✅ Present (length=36) | `railway-api-token` |
| `railway-environment-id` | 2026-05-01T13:44–13:45 | ✅ Present (created by `apply-railway-provision.yml` run 25216580152, ADR-0009) | `railway-environment-id` |
| `railway-n8n-service-id` | 2026-05-01T13:44–13:45 | ✅ Present (created by `apply-railway-provision.yml` run 25216580152, ADR-0009) | `railway-n8n-service-id` |
| `railway-project-id` | 2026-05-01T13:44–13:45 | ✅ Present (created by `apply-railway-provision.yml` run 25216580152, value `ff709798-aa1b-4c52-9a1f-f30b3294f2aa`, ADR-0009) | `railway-project-id` |
| `telegram-bot-token` | 2026-05-01T09:26:16 | ✅ Present (length=46) | `telegram-bot-token` |

### Recently deleted secrets (do not recreate)

These secrets were intentionally removed and any future agent session that notices their absence MUST NOT attempt to recreate them. Each row is the canonical answer to "why is this missing?".

| Name | Deleted | Reason | Re-create? |
|------|---------|--------|------------|
| `OPENROUTER_API_KEY` | 2026-05-01 | Orphaned — zero references in code, IaC, or workflows (verified via `grep -rn 'OPENROUTER_API_KEY\|openrouter-api-key' --include='*.{ts,js,json,yml,yaml,tf,sh,py}' .` → 0 results). Superseded by the `openrouter-management-key` (Provisioning) + `openrouter-runtime-key` (auto-minted, $10/day cap) split per ADR-0004. A third uncapped inference key was redundant and a budget/security risk. Operator also revoked the underlying key in the OpenRouter dashboard, so it is no longer usable even if re-imported. | **NO** — runtime split obsoletes it permanently |

### Bootstrap-managed secrets still missing in GCP

Phase 1 of `bootstrap.yml` (run 25213902199) populated `n8n-encryption-key`, `n8n-admin-password-hash`, `n8n-admin-password-plaintext`, and `openrouter-runtime-key` on 2026-05-01. Only the GitHub App quartet remains pending — those are minted by the `github-app-registration` job, which is gated on `vars.GITHUB_ORG && vars.APP_NAME` (`bootstrap.yml:472`) and was therefore skipped in this run.

| Expected name | In `CLAUDE.md` inventory? | Will be auto-created? | Source |
|---------------|---------------------------|----------------------|--------|
| `github-app-private-key` | yes | ✅ Cloud Run receiver (R-07) | `bootstrap.yml:471-636` |
| `github-app-id` | yes | ✅ Cloud Run receiver (R-07) | `bootstrap.yml:471-636` |
| `github-app-webhook-secret` | yes | ✅ Cloud Run receiver (R-07) | `bootstrap.yml:471-636` |
| `github-app-installation-id` | yes | ❌ Operator action — set as GitHub Variable post-install | `bootstrap.yml:659` |

---

## Workload Identity Federation

```
pool:     projects/974960215714/locations/global/workloadIdentityPools/github
provider: projects/974960215714/locations/global/workloadIdentityPools/github/providers/github
issuer:   https://token.actions.githubusercontent.com
attribute_condition: assertion.repository == 'edri2or/autonomous-agent-template-builder'
```

**Status:** ACTIVE since 2026-05-01. Created by `tools/grant-autonomy.sh:121-144`. Sole identity backbone for GitHub Actions → GCP. **No SA keys exist anywhere.**

---

## Service Accounts

```
github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
  display_name: GitHub Actions runtime (WIF)
  created:      2026-05-01 (by tools/grant-autonomy.sh:90-97)
  keys:         NONE (federation-only, OIDC tokens)
```

This SA is the runtime identity bound to the WIF principalSet
`principalSet://iam.googleapis.com/projects/974960215714/locations/global/workloadIdentityPools/github/attribute.repository/edri2or/autonomous-agent-template-builder`
via `roles/iam.workloadIdentityUser` (`tools/grant-autonomy.sh:146-154`).

It carries 9 project-level roles granted by `tools/grant-autonomy.sh:99-119`:
`secretmanager.secretAccessor`, `secretmanager.admin`, `storage.admin`, `iam.serviceAccountAdmin`, `resourcemanager.projectIamAdmin`, `serviceusage.serviceUsageAdmin`, `run.admin`, `artifactregistry.admin`, `iam.workloadIdentityPoolAdmin`.

---

## GCS Buckets

```
gs://or-infra-templet-admin-tfstate
  location:       us-central1
  versioning:     ENABLED
  uniform_access: ENABLED
  created:        2026-05-01 (by tools/grant-autonomy.sh:75-86)
```

This is the Terraform state bucket; created during the trust handshake so `terraform init -backend-config=bucket=...` can succeed on the first bootstrap run.

---

## Artifact Registry

```
EMPTY (registry API now enabled).
```

`bootstrap-images` repo will be created on demand by `bootstrap.yml:511-516` for the GitHub App receiver image.

---

## Cloud Run

```
us-central1: EMPTY
us-east1:    EMPTY
europe-west1: EMPTY
```

The temporary `github-app-bootstrap-receiver` service is created and torn down within a single `bootstrap.yml` run.

---

## Project IAM (current bindings only)

```
roles/owner                          → user:edriorp38@or-infra.com
roles/run.serviceAgent               → service-974960215714@serverless-robot-prod.iam.gserviceaccount.com
roles/pubsub.serviceAgent            → service-974960215714@gcp-sa-pubsub.iam.gserviceaccount.com
roles/containerregistry.ServiceAgent → service-974960215714@containerregistry.iam.gserviceaccount.com

# Granted to runtime SA on 2026-05-01 by tools/grant-autonomy.sh:99-119
roles/secretmanager.secretAccessor   → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
roles/secretmanager.admin            → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
roles/storage.admin                  → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
roles/iam.serviceAccountAdmin        → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
roles/resourcemanager.projectIamAdmin → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
roles/serviceusage.serviceUsageAdmin → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
roles/run.admin                      → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
roles/artifactregistry.admin         → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
roles/iam.workloadIdentityPoolAdmin  → serviceAccount:github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com
```

The runtime SA is what GitHub Actions impersonates after WIF token exchange.

---

## Resolved decisions (post-PR #15)

(Full diagnostic record in `docs/JOURNEY.md` 2026-05-01 entry; ADR in `docs/adr/0006-secret-naming-convention.md`.)

1. **Naming convention.** ✅ Resolved as kebab-case (canonical). Six new kebab-case secrets created in GCP at 2026-05-01T09:25-09:26 by copying values from existing UPPER_SNAKE_CASE originals. Originals retained (other consumers may reference them). See ADR-0006.

2. **`OPENROUTER_API_KEY` classification.** ✅ Resolved as **Extra (vanilla inference)**.
   - Diagnostic: `GET /api/v1/keys` with this key returned `HTTP 401 {"error":{"message":"Invalid management key","code":401}}` → not a Provisioning key.
   - `GET /api/v1/credits` returned `HTTP 200 {"data":{"total_credits":10,"total_usage":1.30933311}}` → valid inference key, account-level credits.
   - Per ADR-0004 the runtime key requires `limit_reset: daily, limit: $10`. Confirmed via Provisioning key listing that the existing key has `limit: null, limit_remaining: null, limit_reset: null` — it is **not** the runtime key. It coexists with the new `openrouter-management-key` and the future auto-minted `openrouter-runtime-key`.
   - A new Provisioning Key was created in OpenRouter UI and stored as `openrouter-management-key` in GCP.

## GitHub Variables and Secrets (post-handshake)

`tools/grant-autonomy.sh` populated the following on 2026-05-01:

**Variables** (plaintext, public IDs):
- `GCP_PROJECT_ID = or-infra-templet-admin`
- `GCP_REGION = us-central1`
- `GCP_WORKLOAD_IDENTITY_PROVIDER = projects/974960215714/locations/global/workloadIdentityPools/github/providers/github`
- `GCP_SERVICE_ACCOUNT_EMAIL = github-actions-runner@or-infra-templet-admin.iam.gserviceaccount.com`
- `TF_STATE_BUCKET = or-infra-templet-admin-tfstate`
- `N8N_OWNER_EMAIL = ops@example.com`

**Secrets** (libsodium sealed-box, synced from GCP Secret Manager):
- `TELEGRAM_BOT_TOKEN` ← `telegram-bot-token`
- `CLOUDFLARE_API_TOKEN` ← `cloudflare-api-token`
- `OPENROUTER_MANAGEMENT_KEY` ← `openrouter-management-key`
- `RAILWAY_API_TOKEN` ← `railway-api-token`

The presence of `GCP_WORKLOAD_IDENTITY_PROVIDER` is the canonical session-start signal that autonomy is granted (per `CLAUDE.md` Session-start verification ritual).

---

## Handshake completed (per ADR-0007 Inviolable Autonomy Contract)

**The single permitted operator action has been performed.** `tools/grant-autonomy.sh` ran successfully on 2026-05-01 in GCP Cloud Shell as `edriorp38@or-infra.com`. Output banner: `✅ AUTONOMY GRANTED`.

Per ADR-0007, future Claude Code sessions on this repo MUST NOT request any further operator action. The Forbidden Words list in `CLAUDE.md` applies in full from this point forward.

---

## Test clone for ADR-0011 §1 validation (Q-Path, 2026-05-01T15:43–15:47Z)

**Purpose:** live end-to-end test of ADR-0011 §1 (auto-create per-clone GCP project via `tools/grant-autonomy.sh`'s new Step 0 added in Phase C / PR #32). Operator triggered `gh repo create --template` + `bash tools/grant-autonomy.sh` with the new env vars. The test clone exists permanently as proof of silo isolation; it is NOT cleaned up (per ADR-0009 non-destructive failure semantics — even though no failure occurred here, deletion is unwarranted).

**Test clone identity:**

| Resource | Value |
|----------|-------|
| GitHub repo | `edri2or/autonomous-agent-test-clone` |
| GCP project ID | `or-test-clone-001` |
| GCP project number | `995534842856` |
| Created at | `2026-05-01T15:43:26.445Z` |
| Lifecycle state | `ACTIVE` |
| Parent | folder `667201164106` ("factory") under org `905978345393` (or-infra.com) |
| Billing | `billingAccounts/014D0F-AC8E0F-5A7EE7` (enabled) |
| WIF pool | `projects/995534842856/locations/global/workloadIdentityPools/github` (ACTIVE) |
| WIF provider | `projects/995534842856/locations/global/workloadIdentityPools/github/providers/github` |
| WIF attribute condition | `assertion.repository == 'edri2or/autonomous-agent-test-clone'` (repo-scoped) |
| Runtime SA | `github-actions-runner@or-test-clone-001.iam.gserviceaccount.com` |
| TF state bucket | `gs://or-test-clone-001-tfstate` (US-CENTRAL1) |
| Secrets in clone's GCP | 0 (operator did not pre-populate; bootstrap.yml Phase 1 will mint n8n + openrouter on first dispatch) |

**GitHub Variables on `edri2or/autonomous-agent-test-clone` (set by grant-autonomy.sh:174-180):**

| Variable | Value |
|----------|-------|
| `GCP_PROJECT_ID` | `or-test-clone-001` |
| `GCP_REGION` | `us-central1` |
| `GCP_SERVICE_ACCOUNT_EMAIL` | `github-actions-runner@or-test-clone-001.iam.gserviceaccount.com` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/995534842856/locations/global/workloadIdentityPools/github/providers/github` |
| `N8N_OWNER_EMAIL` | `ops@example.com` (default) |
| `TF_STATE_BUCKET` | `or-test-clone-001-tfstate` |

**Critical isolation invariant — verified live at 2026-05-01T15:47Z:**

| Check | Result |
|-------|--------|
| Secret count in `or-infra-templet-admin` (BEFORE the test) | 36 |
| Secret count in `or-infra-templet-admin` (AFTER the test) | **36 (unchanged)** |
| Secret count in `or-test-clone-001` (AFTER the test) | 0 |

**Zero spillover. Project boundary holds.** This proves ADR-0011 §1 + ADR-0010 §1 ("GCP project boundary IS the secret namespace boundary") in production.

**Operator-side prereqs that this test exercised:**

- Operator's existing org-level roles on `905978345393`: `projectCreator`, `organizationViewer`, `organizationAdmin`, `folderAdmin`, `billing.admin`, `billing.user` (and more) — all already in place from prior or-infra-templet-admin bootstrap. No new grants required.
- One-time `is_template=true` set on the source repo via `gh api -X PATCH ... -F is_template=true` (NEW one-time step, captured here for future runbook reference).

**Latent issue surfaced (and worked around):**

`gcloud storage buckets update gs://or-test-clone-001-tfstate --versioning` failed with `GcsApiError('')` immediately after bucket creation (eventual-consistency race). Manual rerun (5-second sleep + retry) succeeded. **Tracked for fix in `docs/plans/adr-0012-phase-e-github-driven-clone.md` §E.2 Change 3** (split create+update into independent idempotent gates so the next `grant-autonomy.sh` run automatically retries the versioning step).

---

## Refresh command

To regenerate this snapshot, run the following in Cloud Shell with `gcloud` already authenticated:

```bash
PROJECT="or-infra-templet-admin"
REGION="us-central1"

set +e
echo "=== BEGIN PROJECT_META ==="
gcloud projects describe "$PROJECT" --format="yaml(projectId,projectNumber,name,lifecycleState,createTime)"
gcloud beta billing projects describe "$PROJECT" --format="yaml(billingEnabled,billingAccountName)"
echo "=== END PROJECT_META ==="

echo "=== BEGIN ENABLED_APIS ==="
gcloud services list --enabled --project="$PROJECT" --format="value(config.name)"
echo "=== END ENABLED_APIS ==="

echo "=== BEGIN SECRETS_LIST ==="
gcloud secrets list --project="$PROJECT" --format="table(name,createTime)"
echo "=== END SECRETS_LIST ==="

echo "=== BEGIN WIF ==="
gcloud iam workload-identity-pools list --location=global --project="$PROJECT"
echo "=== END WIF ==="

echo "=== BEGIN SERVICE_ACCOUNTS ==="
gcloud iam service-accounts list --project="$PROJECT"
echo "=== END SERVICE_ACCOUNTS ==="

echo "=== BEGIN GCS ==="
gcloud storage buckets list --project="$PROJECT" --format="value(name)"
echo "=== END GCS ==="

echo "=== BEGIN ARTIFACTS ==="
gcloud artifacts repositories list --project="$PROJECT"
echo "=== END ARTIFACTS ==="

echo "=== BEGIN CLOUD_RUN ==="
for r in us-central1 us-east1 europe-west1; do
  echo "--- $r ---"; gcloud run services list --region="$r" --project="$PROJECT" 2>/dev/null
done
echo "=== END CLOUD_RUN ==="

echo "=== BEGIN IAM ==="
gcloud projects get-iam-policy "$PROJECT" --format="yaml(bindings)"
echo "=== END IAM ==="
```

The command is **read-only**. No `versions access`, no `create`, no mutation. Paste output back to Claude Code; it will diff against this file and update it.
