output "wif_provider_name" {
  description = "Full WIF provider resource name — set as GCP_WORKLOAD_IDENTITY_PROVIDER in GitHub repository variables"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "GitHub Actions service account email — set as GCP_SERVICE_ACCOUNT_EMAIL in GitHub repository variables"
  value       = google_service_account.github_actions.email
}

output "secret_manager_project" {
  description = "GCP project containing Secret Manager secrets"
  value       = var.gcp_project_id
}

output "terraform_state_bucket" {
  description = "GCS bucket for Terraform remote state"
  value       = google_storage_bucket.tf_state.name
}

output "created_secrets" {
  description = "Secret Manager secret IDs created (values must be injected manually by human operator)"
  value       = [for s in google_secret_manager_secret.secrets : s.secret_id]
}

output "next_steps" {
  description = "Required human actions after terraform apply"
  value = <<-EOT
    HUMAN ACTIONS REQUIRED AFTER TERRAFORM APPLY:

    1. Set GitHub repository variables:
       GCP_WORKLOAD_IDENTITY_PROVIDER = ${google_iam_workload_identity_pool_provider.github.name}
       GCP_SERVICE_ACCOUNT_EMAIL      = ${google_service_account.github_actions.email}
       GCP_PROJECT_ID                 = ${var.gcp_project_id}

    2. Inject secrets into GCP Secret Manager (see docs/runbooks/bootstrap.md):
       - github-app-private-key
       - cloudflare-api-token
       - n8n-encryption-key
       - telegram-bot-token
       - openrouter-management-key
       (All other secrets listed in .env.example)

    3. Update cloudflare DNS records with actual Railway egress IPs after deployment.

    NEVER run terraform apply without reviewing the plan output first.
  EOT
}
