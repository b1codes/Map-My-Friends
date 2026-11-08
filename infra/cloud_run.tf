# The API. One instance is the shape the load test measured
# (docker-compose.perf.yml): 1 vCPU, 512 MiB, gunicorn with 8 threads, so 8
# requests at a time. It scales to zero when idle and stops at max_instances.
#
# Terraform creates the service and owns its settings. The release workflow
# owns which image runs and where traffic goes, so Terraform ignores those.
resource "google_cloud_run_v2_service" "api" {
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = true

  template {
    service_account                  = google_service_account.api.email
    max_instance_request_concurrency = 8
    timeout                          = "30s"

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances
    }

    containers {
      image = var.initial_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # Billed only while handling requests.
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # config/health.py. The image answers in about 2 s from a cold start.
      startup_probe {
        http_get {
          path = "/health"
        }
        period_seconds    = 2
        timeout_seconds   = 1
        failure_threshold = 15
      }

      liveness_probe {
        http_get {
          path = "/health"
        }
        period_seconds    = 30
        timeout_seconds   = 2
        failure_threshold = 3
      }

      dynamic "env" {
        for_each = local.api_env
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name = "DJANGO_SECRET_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.django_secret_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      traffic,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_service.this,
    google_secret_manager_secret_iam_member.api_reads_secret_key,
    google_secret_manager_secret_version.django_secret_key,
  ]
}

# The API is public; it does its own authentication.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
