# Two service accounts, each with only what it needs.
#
# api: what the Cloud Run service runs as. Firestore data, the media bucket's
# objects (storage.tf) and the secret key (secrets.tf). Nothing else.
resource "google_service_account" "api" {
  account_id   = "api-runtime"
  display_name = "Map My Friends API (Cloud Run)"
}

resource "google_project_iam_member" "api_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = google_service_account.api.member
}

# deployer: what the release workflow acts as, through Workload Identity
# Federation (no key exists). It pushes images, deploys revisions of this
# one service, and deploys Firestore rules and indexes and the web app.
resource "google_service_account" "deployer" {
  account_id   = "github-deployer"
  display_name = "GitHub Actions release workflow"
}

resource "google_artifact_registry_repository_iam_member" "deployer_pushes" {
  repository = google_artifact_registry_repository.images.name
  location   = google_artifact_registry_repository.images.location
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.deployer.member
}

resource "google_cloud_run_v2_service_iam_member" "deployer_deploys" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.developer"
  member   = google_service_account.deployer.member
}

# A revision runs as the api account, so deploying one needs actAs on it.
resource "google_service_account_iam_member" "deployer_acts_as_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.deployer.member
}

# firebase deploy --only firestore,hosting. These roles only exist at
# project level.
resource "google_project_iam_member" "deployer_firebase" {
  for_each = toset([
    "roles/datastore.indexAdmin",
    "roles/firebaserules.admin",
    "roles/firebasehosting.admin",
    "roles/firebase.viewer",
    "roles/serviceusage.serviceUsageConsumer",
  ])

  project = var.project_id
  role    = each.value
  member  = google_service_account.deployer.member
}

# GitHub's OIDC tokens, accepted only from this repository's release
# workflow, as it runs on main.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.workflow"   = "assertion.workflow_ref"
  }

  attribute_condition = join(" && ", [
    "assertion.repository == '${var.github_repository}'",
    "assertion.ref == 'refs/heads/main'",
    "assertion.workflow_ref == '${var.github_repository}/.github/workflows/release.yml@refs/heads/main'",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_impersonates_deployer" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}
