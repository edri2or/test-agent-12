terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  # Remote state stored in GCS. Human operator must create the bucket
  # before running terraform init. Never store state locally.
  backend "gcs" {
    # bucket is set via -backend-config or TF_CLI_ARGS_init
    # prefix = "terraform/state"
    # Do not hardcode bucket name here — set via backend config file.
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  # Authentication via WIF/ADC — no service account key files
}

# Cloudflare provider authentication uses the token retrieved from
# GCP Secret Manager at apply time. Never hardcoded.
provider "cloudflare" {
  # api_token sourced from environment variable CLOUDFLARE_API_TOKEN
  # which is injected by the CI workflow from GCP Secret Manager (R-01)
}
