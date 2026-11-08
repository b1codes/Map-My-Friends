# Map My Friends on Google Cloud: the API on Cloud Run, data in Firestore,
# uploads in Cloud Storage, the web app on Firebase Hosting. infra/README.md
# covers bootstrapping, applying, and how the release workflow deploys onto
# what this creates.
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.8"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # State lives in a Cloud Storage bucket created once by hand, before the
  # first apply (infra/README.md, Bootstrapping). The bucket is given at init:
  #   terraform init -backend-config="bucket=<project-id>-tfstate"
  backend "gcs" {
    prefix = "map-my-friends"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Firebase project and Hosting site resources are only in the beta provider.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
}
