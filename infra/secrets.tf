# DJANGO_SECRET_KEY: signs every session and JWT, so it never appears in
# config or in Terraform's state. It's generated as an ephemeral value and
# written to Secret Manager write-only. To rotate it (which signs everyone
# out), bump var.secret_key_version (variables.tf) and apply.
ephemeral "random_password" "django_secret_key" {
  length  = 64
  special = false
}

resource "google_secret_manager_secret" "django_secret_key" {
  secret_id = "django-secret-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "django_secret_key" {
  secret                 = google_secret_manager_secret.django_secret_key.id
  secret_data_wo         = ephemeral.random_password.django_secret_key.result
  secret_data_wo_version = var.secret_key_version
}

resource "google_secret_manager_secret_iam_member" "api_reads_secret_key" {
  secret_id = google_secret_manager_secret.django_secret_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.api.member
}
