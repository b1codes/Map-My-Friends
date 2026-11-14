# The web app (frontend/build/web), deployed by the release with the
# Firebase CLI. Hosting's free tier covers this app's size and traffic.
resource "google_firebase_project" "this" {
  provider = google-beta
  project  = var.project_id

  depends_on = [google_project_service.this]
}

resource "google_firebase_hosting_site" "web" {
  provider = google-beta
  project  = google_firebase_project.this.project
  site_id  = local.hosting_site_id
}
