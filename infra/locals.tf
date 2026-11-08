locals {
  hosting_site_id = var.hosting_site_id != "" ? var.hosting_site_id : var.project_id

  # Cloud Run's deterministic URL, and the URL of the revision a release
  # starts with no traffic and smoke-tests (tag "candidate").
  api_host           = "${var.service_name}-${data.google_project.this.number}.${var.region}.run.app"
  candidate_tag      = "candidate"
  api_candidate_host = "${local.candidate_tag}---${local.api_host}"
  api_hosts          = compact([local.api_host, local.api_candidate_host, var.api_domain])

  web_origins = compact([
    "https://${local.hosting_site_id}.web.app",
    "https://${local.hosting_site_id}.firebaseapp.com",
    var.web_domain != "" ? "https://${var.web_domain}" : "",
  ])

  # The API's configuration. config/settings.py documents each variable; the
  # production image's checks (scripts/prod-image.sh) run with the same set.
  api_env = {
    DJANGO_DEBUG         = "False"
    ALLOWED_HOSTS        = join(",", local.api_hosts)
    CORS_ALLOWED_ORIGINS = join(",", local.web_origins)
    CSRF_TRUSTED_ORIGINS = join(",", local.web_origins)
    SECURE_SSL_REDIRECT  = "True"
    # Cloud Run's front end appends the connecting address to
    # X-Forwarded-For, so the client is the last entry: one proxy.
    DJANGO_NUM_PROXIES   = "1"
    FIRESTORE_PROJECT_ID = var.project_id
    GS_BUCKET_NAME       = google_storage_bucket.media.name
  }

  services = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "firebaserules.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ])
}
