resource "google_project_service" "this" {
  for_each = local.services

  service = each.value
  # Turning an API off would break whatever else in the project uses it.
  disable_on_destroy = false
}
