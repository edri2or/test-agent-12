# Rollback Runbook

Procedures for reverting failed deployments and restoring known-good states.

**Critical rule:** Destructive cleanup (dropping databases, terminating core networks, deleting IAM policies) is **always human-gated**. The runtime agent must halt and request human intervention before executing any unrecoverable operation.

---

## Railway Deployment Rollback

### Revert to previous deployment

```bash
# List recent deployments
railway deployments

# Revert to a specific deployment ID
railway rollback DEPLOYMENT_ID

# Or use the Railway dashboard:
# Project → Deployments → click previous successful deployment → Redeploy
```

### Tear down a service (human-executed only)

```bash
# Bring down all services for a project
railway down
# WARNING: This is destructive for stateful services.
# Confirm data is backed up before executing.
```

---

## Cloudflare Workers Rollback

```bash
# List deployed worker versions
wrangler deployments list

# Rollback to previous version
wrangler rollback
```

---

## Terraform State Rollback

### Revert a specific resource

```bash
# View current state
terraform state list

# Manually untaint a resource to prevent replacement
terraform untaint RESOURCE_ADDRESS

# Import previous known-good resource state
terraform import RESOURCE_ADDRESS RESOURCE_ID
```

### Full state recovery (extreme edge case)

```bash
# GCS backend: list state versions
gsutil ls -la gs://YOUR_TF_STATE_BUCKET/

# Restore previous state version (human-executed only)
gsutil cp gs://YOUR_TF_STATE_BUCKET/terraform.tfstate#VERSION \
  gs://YOUR_TF_STATE_BUCKET/terraform.tfstate
```

**Note:** Terraform state recovery can result in orphaned cloud resources. Always review the plan after state restoration. Never automate state file overwrites.

---

## Secret Rotation

If a secret is compromised:

```bash
# Revoke the compromised version
gcloud secrets versions destroy VERSION_ID --secret=SECRET_NAME

# Add a new version
echo -n "NEW_SECRET_VALUE" | gcloud secrets versions add SECRET_NAME --data-file=-

# Force a redeployment to pick up the new secret
railway redeploy
```

**Telegram kill switch:** Revoke the bot token via @BotFather → `/revoke` to immediately sever the runtime agent's HITL interface.

**WIF kill switch:** Delete the WIF provider to sever all CI/CD pipeline authentication:
```bash
gcloud iam workload-identity-pools providers delete github-provider \
  --workload-identity-pool=github-pool \
  --location=global \
  --project=YOUR_PROJECT_ID
```

---

## n8n Workflow Rollback

```bash
# Export current workflows before changes
n8n export:workflow --all --output=./backups/workflows-$(date +%Y%m%d).json

# Import a backed-up workflow set
n8n import:workflow --input=./backups/workflows-YYYYMMDD.json
```

---

## Local Git Rollback

If scaffolding errors occur during build-agent work:

```bash
# Revert local uncommitted changes
git restore .

# Revert to a specific commit (creates a new revert commit — never force-push to main)
git revert COMMIT_SHA

# Reset to a known-good state (local only, before push)
git reset --hard COMMIT_SHA
```

---

## Escalation

If rollback fails or results in an unrecoverable state:

1. STOP all automated processes immediately
2. Revoke the Telegram bot token and WIF provider (kill switches above)
3. Open a Linear issue describing the incident
4. Engage the human operator for manual GCP console recovery
5. Document the incident in `docs/JOURNEY.md` with full timeline

**Claude Code must never attempt automated recovery from unrecoverable state destruction.**
