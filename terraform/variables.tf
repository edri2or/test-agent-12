variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (org/repo format)"
  type        = string
}

variable "github_main_branch" {
  description = "Main branch name to restrict WIF binding"
  type        = string
  default     = "main"
}

variable "wif_pool_id" {
  description = "Workload Identity Pool ID"
  type        = string
  default     = "github-pool"
}

variable "wif_provider_id" {
  description = "Workload Identity Provider ID"
  type        = string
  default     = "github-provider"
}

variable "service_account_id" {
  description = "Service account ID for GitHub Actions"
  type        = string
  default     = "github-actions-sa"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare DNS zone ID"
  type        = string
  default     = ""
}

variable "clone_slug" {
  description = "Per-clone slug derived from github.event.repository.name. Namespaces Cloudflare DNS records and the Worker name so two clones cohabiting an operator's Cloudflare account do not collide on `api`/`n8n`/`autonomous-agent-edge`. See ADR-0011 §2."
  type        = string
  default     = "agent"
}

variable "cloudflare_domain" {
  description = "Root domain managed by Cloudflare"
  type        = string
  default     = ""
}

variable "railway_project_id" {
  description = "Railway project ID for service references"
  type        = string
  default     = ""
}

variable "terraform_state_bucket" {
  description = "GCS bucket name for Terraform remote state"
  type        = string
}

variable "secret_names" {
  description = "List of secret names to create in GCP Secret Manager"
  type        = list(string)
  default = [
    "github-app-id",
    "github-app-installation-id",
    "github-app-private-key",
    "github-app-webhook-secret", # written by Cloud Run bootstrap-receiver (R-07)
    "cloudflare-api-token",
    "cloudflare-account-id",
    "n8n-encryption-key",
    "n8n-admin-password-hash", # bcrypt hash for N8N_INSTANCE_OWNER_PASSWORD_HASH (n8n >=2.17.0)
    "telegram-bot-token",
    "openrouter-management-key",
    "openrouter-runtime-key", # downstream key with daily $10 cap (ADR-0004); provisioned by tools/provision-openrouter-runtime-key.sh
    "linear-api-key",
    "linear-webhook-secret",
    "railway-api-token",
    # UPPER_CASE names used by n8n/Railway deployment workflows
    "RAILWAY_TOKEN",
    "N8N_OWNER_PASSWORD",
    "N8N_ENCRYPTION_KEY",
    "N8N_BASIC_AUTH_PASSWORD",
    "N8N_SECRETS_BROKER_TOKEN",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_CHAT_ID",
    "OPENROUTER_API_KEY",
    "RAILWAY_PROJECT_ID",
    "RAILWAY_ENVIRONMENT_ID",
    "GITHUB_APP_ID",
    "GITHUB_APP_PRIVATE_KEY",
    "GITHUB_PAT_ACTIONS_WRITE",
    "GITHUB_PAT_SKILL_SYNC",
    "CLOUDFLARE_TOKEN",
    "CLOUDFLARE_ZONE_ID",
  ]
}
