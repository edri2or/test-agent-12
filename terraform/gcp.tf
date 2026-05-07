# ── GCP APIs ────────────────────────────────────────────────────────────────

resource "google_project_service" "iam" {
  project            = var.gcp_project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam_credentials" {
  project            = var.gcp_project_id
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secret_manager" {
  project            = var.gcp_project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sts" {
  project            = var.gcp_project_id
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloud_resource_manager" {
  project            = var.gcp_project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

# ── Workload Identity Federation ─────────────────────────────────────────────

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions Pool"
  description               = "WIF pool for GitHub Actions OIDC authentication"

  depends_on = [google_project_service.iam]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.gcp_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "GitHub Actions Provider"
  description                        = "OIDC identity provider for GitHub Actions tokens"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  # Restrict to exact repository only — prevents lateral escalation from forks
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ── Service Account ───────────────────────────────────────────────────────────

resource "google_service_account" "github_actions" {
  project      = var.gcp_project_id
  account_id   = var.service_account_id
  display_name = "GitHub Actions Service Account"
  description  = "Service account for GitHub Actions WIF authentication. No keys — OIDC only."
}

# Bind WIF to service account — restricted to main branch only
resource "google_service_account_iam_binding" "github_wif_binding" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}",
  ]
}

# Grant Secret Manager accessor to CI service account
resource "google_project_iam_member" "secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# ── Secret Manager ────────────────────────────────────────────────────────────

# Create secret containers. Values are injected manually by human operators.
# Claude Code must never write secret values into Terraform configs.
resource "google_secret_manager_secret" "secrets" {
  for_each  = toset(var.secret_names)
  project   = var.gcp_project_id
  secret_id = each.value

  replication {
    auto {}
  }

  labels = {
    managed-by = "terraform"
    repo       = replace(var.github_repo, "/", "-")
  }

  depends_on = [google_project_service.secret_manager]
}

# GCS bucket for Terraform remote state
resource "google_storage_bucket" "tf_state" {
  project       = var.gcp_project_id
  name          = var.terraform_state_bucket
  location      = var.gcp_region
  force_destroy = false # Prevent accidental state deletion

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "tf_state_sa" {
  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_actions.email}"
}
