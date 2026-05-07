# Cloudflare resources — DNS zone and Workers scaffold
#
# RISK R-01: Native OIDC for Cloudflare Workers CI/CD is not officially supported
# without complex workarounds. The deployment workflow uses the Cloudflare API token
# retrieved from GCP Secret Manager at CI runtime. The token is never stored in
# this Terraform configuration or in GitHub Secrets.
#
# This file only manages DNS records and static Worker configuration.
# Worker script deployment is handled by wrangler-action in .github/workflows/deploy.yml.

# Only provision Cloudflare resources if a zone ID is provided
locals {
  cloudflare_enabled = var.cloudflare_zone_id != ""
}

# DNS zone data source — zone must be created manually in Cloudflare dashboard
# (DNS nameserver configuration requires registrar interaction — HUMAN_REQUIRED)
data "cloudflare_zone" "main" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
}

# DNS A record for the agent API.
# Per ADR-0011 §2: name is namespaced by `var.clone_slug` so two clones
# sharing the same Cloudflare zone do not collide on the `api` subdomain.
resource "cloudflare_record" "agent_api" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "${var.clone_slug}-api"
  value   = "192.0.2.1" # Replace with Railway egress IP after provisioning
  type    = "A"
  proxied = true
  comment = "Agent API for clone ${var.clone_slug} — proxied via Cloudflare. Update value after Railway provisioning."

  lifecycle {
    ignore_changes = [value] # Allow manual IP updates without triggering replace
  }
}

# DNS CNAME for the n8n orchestrator (per-clone, ADR-0011 §2).
resource "cloudflare_record" "n8n" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "${var.clone_slug}-n8n"
  value   = "railway.app" # Replace with actual Railway domain after provisioning
  type    = "CNAME"
  proxied = false
  comment = "n8n orchestrator for clone ${var.clone_slug} — update target after Railway provisioning."

  lifecycle {
    ignore_changes = [value]
  }
}

# Cloudflare Worker script placeholder. Per ADR-0011 §2: per-clone Worker
# name avoids account-level uniqueness collisions. Actual deployment via
# wrangler-action in CI (deploy.yml renders wrangler.toml's `name` field
# from the same `${CLONE_SLUG}` env), not via Terraform — avoids storing
# API tokens in Terraform state.
resource "cloudflare_worker_script" "edge_router" {
  count      = local.cloudflare_enabled ? 1 : 0
  account_id = var.cloudflare_zone_id # Use zone_id as proxy for account scope
  name       = "${var.clone_slug}-edge"
  content    = file("${path.module}/../src/worker/edge-router.js")

  lifecycle {
    # Deployments are managed by wrangler-action in CI, not Terraform apply.
    # Prevent Terraform from overwriting wrangler-managed deployments.
    ignore_changes = [content]
  }
}
