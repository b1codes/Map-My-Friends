# The (default) database: the free tier only applies to it. Its indexes and
# rules are deployed by the release, from firestore.indexes.json and
# firestore.rules, before the new code takes traffic.
resource "google_firestore_database" "default" {
  name        = "(default)"
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"

  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  # terraform destroy leaves the data alone.
  deletion_policy = "ABANDON"

  depends_on = [google_project_service.this]
}
