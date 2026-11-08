# The release workflow reads these as repository variables (infra/README.md,
# Connecting the release).

output "api_url" {
  description = "The API's URL (the app's API_BASE_URL is this plus /api/)."
  value       = "https://${local.api_host}"
}

output "candidate_url" {
  description = "The URL of the revision a release smoke-tests before moving traffic to it."
  value       = "https://${local.api_candidate_host}"
}

output "web_url" {
  description = "The web app's URL."
  value       = "https://${local.hosting_site_id}.web.app"
}

output "service_name" {
  value = google_cloud_run_v2_service.api.name
}

output "region" {
  value = var.region
}

output "image_repository" {
  description = "Where the release pushes the API's images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}/api"
}

output "media_bucket" {
  value = google_storage_bucket.media.name
}

output "hosting_site_id" {
  value = google_firebase_hosting_site.web.site_id
}

output "deployer_service_account" {
  description = "GCP_DEPLOYER_SERVICE_ACCOUNT for the release workflow."
  value       = google_service_account.deployer.email
}

output "workload_identity_provider" {
  description = "GCP_WORKLOAD_IDENTITY_PROVIDER for the release workflow."
  value       = google_iam_workload_identity_pool_provider.github.name
}
