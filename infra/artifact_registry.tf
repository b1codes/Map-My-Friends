# The API's images. The release pushes one per deployed commit, tagged with
# its SHA. Storage past 0.5 GB is billed, so only recent images are kept.
resource "google_artifact_registry_repository" "images" {
  repository_id = "map-my-friends"
  location      = var.region
  format        = "DOCKER"
  description   = "Production images of the Map My Friends API."

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }

  cleanup_policies {
    id     = "delete-older"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "604800s" # 7 days; the five most recent are kept regardless
    }
  }

  depends_on = [google_project_service.this]
}
