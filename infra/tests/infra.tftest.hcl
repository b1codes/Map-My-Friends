# What the infrastructure must be, checked with the providers mocked: no
# Google Cloud project or credentials are needed, and nothing is created.
# `make test-infra`, and the Validate Terraform job in CI.
#
# Each run applies the configuration against the mocks and asserts on the
# resulting resources. They cover what costs money (scaling caps, scale to
# zero, image retention), what's exposed (public reads, CORS, who may deploy),
# and what the API needs to start (its settings, its secret, its probes).

# Computed values the provider would return, where a random mock string
# wouldn't pass the provider's own validation (IAM members, account names).
mock_provider "google" {
  override_data {
    target = data.google_project.this
    values = {
      number = "123456789012"
    }
  }

  override_resource {
    target = google_service_account.api
    values = {
      email  = "api-runtime@mmf-test.iam.gserviceaccount.com"
      member = "serviceAccount:api-runtime@mmf-test.iam.gserviceaccount.com"
      name   = "projects/mmf-test/serviceAccounts/api-runtime@mmf-test.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target = google_service_account.deployer
    values = {
      email  = "github-deployer@mmf-test.iam.gserviceaccount.com"
      member = "serviceAccount:github-deployer@mmf-test.iam.gserviceaccount.com"
      name   = "projects/mmf-test/serviceAccounts/github-deployer@mmf-test.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target = google_iam_workload_identity_pool.github
    values = {
      name = "projects/123456789012/locations/global/workloadIdentityPools/github"
    }
  }
}

mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "mmf-test"
}

run "the_api_scales_to_zero_and_stops_at_the_cap" {
  assert {
    condition     = google_cloud_run_v2_service.api.template[0].scaling[0].min_instance_count == 0
    error_message = "The API must scale to zero when idle; a warm instance is billed around the clock."
  }
  assert {
    condition     = google_cloud_run_v2_service.api.template[0].scaling[0].max_instance_count == 3
    error_message = "The API must stop at max_instances, the cap on what a spike can cost."
  }
  assert {
    condition     = google_cloud_run_v2_service.api.template[0].containers[0].resources[0].cpu_idle
    error_message = "CPU must be billed only while handling requests."
  }
}

run "an_instance_is_the_shape_the_load_test_measured" {
  assert {
    condition = (
      google_cloud_run_v2_service.api.template[0].containers[0].resources[0].limits.cpu == "1" &&
      google_cloud_run_v2_service.api.template[0].containers[0].resources[0].limits.memory == "512Mi"
    )
    error_message = "One instance is 1 vCPU and 512 MiB, as docker-compose.perf.yml runs it."
  }
  assert {
    condition     = google_cloud_run_v2_service.api.template[0].max_instance_request_concurrency == 8
    error_message = "Concurrency matches gunicorn's 8 threads (backend/gunicorn.conf.py)."
  }
}

run "probes_call_health" {
  assert {
    condition     = google_cloud_run_v2_service.api.template[0].containers[0].startup_probe[0].http_get[0].path == "/health"
    error_message = "The startup probe must call /health (config/health.py)."
  }
  assert {
    condition     = google_cloud_run_v2_service.api.template[0].containers[0].liveness_probe[0].http_get[0].path == "/health"
    error_message = "The liveness probe must call /health."
  }
}

run "the_api_runs_with_production_settings" {
  assert {
    condition = alltrue([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value == "False" if e.name == "DJANGO_DEBUG"
    ]) && contains([for e in google_cloud_run_v2_service.api.template[0].containers[0].env : e.name], "DJANGO_DEBUG")
    error_message = "DJANGO_DEBUG must be set, to False."
  }
  assert {
    condition = one([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value if e.name == "ALLOWED_HOSTS"
    ]) == "map-my-friends-api-123456789012.us-central1.run.app,candidate---map-my-friends-api-123456789012.us-central1.run.app"
    error_message = "ALLOWED_HOSTS must be the service's URL and its candidate revision's, nothing wider."
  }
  assert {
    condition = one([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value if e.name == "CORS_ALLOWED_ORIGINS"
    ]) == "https://mmf-test.web.app,https://mmf-test.firebaseapp.com"
    error_message = "CORS must allow only the web app's origins."
  }
  assert {
    condition = one([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value if e.name == "SECURE_SSL_REDIRECT"
    ]) == "True"
    error_message = "Plain HTTP must be redirected to HTTPS."
  }
  assert {
    condition = one([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value if e.name == "DJANGO_NUM_PROXIES"
    ]) == "1"
    error_message = "One proxy (Cloud Run's front end) sits in front of the API; the throttles key on the address it saw."
  }
  assert {
    condition = one([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value if e.name == "GS_BUCKET_NAME"
    ]) == "mmf-test-media"
    error_message = "Uploads must go to the media bucket; the instance's disk doesn't last."
  }
}

run "the_secret_key_comes_from_secret_manager_only" {
  assert {
    condition = one([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value_source[0].secret_key_ref[0].secret if e.name == "DJANGO_SECRET_KEY"
    ]) == "django-secret-key"
    error_message = "DJANGO_SECRET_KEY must be read from Secret Manager."
  }
  assert {
    condition = alltrue([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value == null || e.value == "" if e.name == "DJANGO_SECRET_KEY"
    ])
    error_message = "DJANGO_SECRET_KEY must never be a plain value in the service's config."
  }
  assert {
    condition     = google_secret_manager_secret_version.django_secret_key.secret_data == null
    error_message = "The key is written write-only, so it's never in Terraform's state."
  }
  assert {
    condition     = google_secret_manager_secret_version.django_secret_key.secret_data_wo_version == "1"
    error_message = "The key starts at version 1 (secret_key_version's default)."
  }
}

run "bumping_secret_key_version_rotates_the_key" {
  # A write-only value isn't compared with what's stored, so changing
  # secret_data_wo_version is the only thing that writes a new key.
  variables {
    secret_key_version = 2
  }

  assert {
    condition     = google_secret_manager_secret_version.django_secret_key.secret_data_wo_version == "2"
    error_message = "secret_key_version must reach secret_data_wo_version, or bumping it rotates nothing."
  }
}

run "terraform_leaves_the_image_and_traffic_to_the_release" {
  # Ignoring them is what lets the release deploy without Terraform undoing
  # it. The check is on the config text, since lifecycle isn't an attribute.
  assert {
    condition = (
      strcontains(file("${path.module}/cloud_run.tf"), "template[0].containers[0].image,") &&
      strcontains(file("${path.module}/cloud_run.tf"), "traffic,")
    )
    error_message = "cloud_run.tf must ignore changes to the image and traffic."
  }
}

run "photos_are_readable_by_url_but_the_bucket_cant_be_listed" {
  assert {
    condition     = google_storage_bucket.media.uniform_bucket_level_access
    error_message = "The bucket uses IAM only, no per-object ACLs."
  }
  assert {
    condition = (
      google_storage_bucket_iam_member.media_public_read.member == "allUsers" &&
      google_storage_bucket_iam_member.media_public_read.role == "roles/storage.legacyObjectReader"
    )
    error_message = "allUsers gets object reads (objects.get) only. objectViewer would let anyone list every photo."
  }
  assert {
    condition     = toset(google_storage_bucket.media.cors[0].origin) == toset(["https://mmf-test.web.app", "https://mmf-test.firebaseapp.com"])
    error_message = "Only the web app's origins may fetch photos cross-origin."
  }
  assert {
    condition     = toset(google_storage_bucket.media.cors[0].method) == toset(["GET", "HEAD"])
    error_message = "CORS on the bucket allows reads only."
  }
  assert {
    condition     = google_storage_bucket.media.force_destroy == false
    error_message = "terraform destroy must not delete everyone's photos."
  }
}

run "the_api_account_has_only_what_it_needs" {
  assert {
    condition     = google_project_iam_member.api_firestore.role == "roles/datastore.user"
    error_message = "The API's only project-wide role is Firestore data access."
  }
  assert {
    condition     = google_storage_bucket_iam_member.media_api.role == "roles/storage.objectUser"
    error_message = "The API manages objects in the media bucket, and nothing else in Storage."
  }
  assert {
    condition     = google_cloud_run_v2_service.api.template[0].service_account == google_service_account.api.email
    error_message = "The service must run as its own account, not the default compute one (Editor)."
  }
}

run "no_account_is_granted_owner_or_editor" {
  assert {
    condition = alltrue([
      for m in concat(
        [google_project_iam_member.api_firestore],
        values(google_project_iam_member.deployer_firebase),
      ) : !contains(["roles/owner", "roles/editor"], m.role)
    ])
    error_message = "No account gets Owner or Editor."
  }
}

run "only_the_release_workflow_on_main_can_deploy" {
  assert {
    condition = (
      strcontains(google_iam_workload_identity_pool_provider.github.attribute_condition, "assertion.repository == 'b1codes/Map-My-Friends'") &&
      strcontains(google_iam_workload_identity_pool_provider.github.attribute_condition, "assertion.ref == 'refs/heads/main'") &&
      strcontains(google_iam_workload_identity_pool_provider.github.attribute_condition, "assertion.workflow_ref == 'b1codes/Map-My-Friends/.github/workflows/release.yml@refs/heads/main'")
    )
    error_message = "GitHub tokens must be accepted only from release.yml, on main, in this repository: a PR's workflow must not be able to deploy."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.oidc[0].issuer_uri == "https://token.actions.githubusercontent.com"
    error_message = "Only GitHub's OIDC issuer."
  }
  assert {
    condition     = google_cloud_run_v2_service_iam_member.deployer_deploys.role == "roles/run.developer"
    error_message = "The deployer can deploy this one service, not administer Cloud Run."
  }
}

run "old_images_are_cleaned_up" {
  assert {
    condition     = google_artifact_registry_repository.images.cleanup_policy_dry_run == false
    error_message = "Cleanup must actually delete, not only report."
  }
  assert {
    condition     = length(google_artifact_registry_repository.images.cleanup_policies) == 2
    error_message = "Keep the 5 most recent images and delete older ones."
  }
}

run "firestore_is_the_free_default_database_and_protected" {
  assert {
    condition     = google_firestore_database.default.name == "(default)"
    error_message = "Firestore's free tier only applies to the (default) database."
  }
  assert {
    condition     = google_firestore_database.default.delete_protection_state == "DELETE_PROTECTION_ENABLED"
    error_message = "The database must have delete protection."
  }
  assert {
    condition     = google_firestore_database.default.deletion_policy == "ABANDON"
    error_message = "terraform destroy must leave the data alone."
  }
}

run "custom_domains_are_added_to_hosts_and_origins" {
  variables {
    api_domain = "api.mapmyfriends.com"
    web_domain = "mapmyfriends.com"
  }

  assert {
    condition = endswith(one([
      for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
      e.value if e.name == "ALLOWED_HOSTS"
    ]), ",api.mapmyfriends.com")
    error_message = "A custom API domain is an allowed host."
  }
  assert {
    condition     = contains(google_storage_bucket.media.cors[0].origin, "https://mapmyfriends.com")
    error_message = "A custom web domain may fetch photos."
  }
}

run "a_region_outside_the_free_tier_is_refused" {
  command = plan
  variables {
    region = "europe-west1"
  }
  expect_failures = [var.region]
}

run "the_instance_cap_is_bounded" {
  command = plan
  variables {
    max_instances = 50
  }
  expect_failures = [var.max_instances]
}

run "a_service_name_too_long_for_the_candidate_url_is_refused" {
  command = plan
  variables {
    service_name = "map-my-friends-api-with-a-very-long-name"
  }
  expect_failures = [var.service_name]
}

run "a_secret_key_version_below_one_is_refused" {
  command = plan
  variables {
    secret_key_version = 0
  }
  expect_failures = [var.secret_key_version]
}
