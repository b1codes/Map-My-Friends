# Uploaded photos (config/settings.py, GS_BUCKET_NAME).
#
# Decided with the user: each object is readable by anyone with its URL, and
# nobody can list the bucket. Names are random UUIDs, so the URL is the
# secret; signed URLs would cost an IAM call per photo per API response.
# No object versioning: names are never reused, so nothing is overwritten,
# and a deleted photo is kept for 7 days by soft delete below.
#trivy:ignore:AVD-GCP-0078 Objects are never overwritten; soft delete covers deletions.
resource "google_storage_bucket" "media" {
  name     = "${var.project_id}-media"
  location = upper(var.region)

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  # "inherited" rather than "enforced", so allUsers can be granted object
  # reads below. That grant is the only public one.
  public_access_prevention = "inherited"
  force_destroy            = false

  # A deleted photo can be restored for 7 days (the default, set here so the
  # versioning decision above can rely on it).
  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  # Flutter web fetches images over XHR, so the browser needs CORS from the
  # bucket for the web app's origins. Reads only.
  cors {
    origin          = local.web_origins
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }

  depends_on = [google_project_service.this]
}

# Object reads by URL. legacyObjectReader is storage.objects.get alone;
# objectViewer would also grant storage.objects.list, so anyone could
# enumerate every photo's name.
#trivy:ignore:AVD-GCP-0001 Public object reads are deliberate (see above); listing stays private.
resource "google_storage_bucket_iam_member" "media_public_read" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.legacyObjectReader"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "media_api" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectUser"
  member = google_service_account.api.member
}
