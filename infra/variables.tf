variable "project_id" {
  description = "The Google Cloud project to deploy into."
  type        = string
}

variable "region" {
  description = <<-EOT
    Region for Cloud Run, Artifact Registry and the media bucket. Limited to
    the regions where Cloud Storage's always-free tier applies.
  EOT
  type        = string
  default     = "us-central1"

  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1"], var.region)
    error_message = "Use us-central1, us-east1 or us-west1: Cloud Storage's free tier only covers those."
  }
}

variable "firestore_location" {
  description = "Firestore's location. nam5 is the US multi-region; a region (e.g. us-central1) is cheaper per operation but has no free-tier difference."
  type        = string
  default     = "nam5"
}

variable "service_name" {
  description = "The Cloud Run service's name. Part of the API's URL."
  type        = string
  default     = "map-my-friends-api"

  validation {
    # The deterministic URL (SERVICE-PROJECT_NUMBER.REGION.run.app) needs
    # "candidate---SERVICE-PROJECT_NUMBER" to fit a 63-character DNS label.
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}[a-z0-9]$", var.service_name))
    error_message = "Lower-case letters, digits and hyphens, at most 31 characters, so the candidate revision's URL fits in a DNS label."
  }
}

variable "max_instances" {
  description = <<-EOT
    The most Cloud Run instances the API scales to: the cap on what a traffic
    spike can cost. Held at 1 until GCIP (ClickUp 86bb3eu64): Django's users
    and refresh-token blacklist are SQLite on each instance, so with two a
    request that lands on the other one is a random 401, and a username can be
    claimed again there. One instance held about 4x the load test's rate
    (docs/testing.md). After GCIP, allow up to 10.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.max_instances == 1
    error_message = "1 until GCIP: users are per-instance SQLite, so a second instance means random 401s and usernames that can be claimed twice."
  }
}

variable "github_repository" {
  description = "owner/name of the GitHub repository whose release workflow may deploy."
  type        = string
  default     = "b1codes/Map-My-Friends"
}

variable "hosting_site_id" {
  description = "The Firebase Hosting site for the web app; its URL is https://<site>.web.app. Defaults to the project id, Firebase's default site."
  type        = string
  default     = ""
}

variable "api_domain" {
  description = "A custom domain mapped to the API, e.g. api.mapmyfriends.com. Leave empty to use the run.app URL only."
  type        = string
  default     = ""
}

variable "web_domain" {
  description = "A custom domain connected to the Hosting site, e.g. mapmyfriends.com. Leave empty to use web.app only."
  type        = string
  default     = ""
}

variable "initial_image" {
  description = "The image the service is created with. The release workflow deploys the real one; Terraform never changes it afterwards."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "secret_key_version" {
  description = <<-EOT
    The DJANGO_SECRET_KEY generation. Bumping it (to any higher number) makes
    the next apply write a freshly generated key to Secret Manager: the key is
    write-only, so Terraform can't see a change in it any other way. A new key
    invalidates every session and token, so it signs everyone out.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.secret_key_version >= 1
    error_message = "1 or higher. Bump it to rotate the key."
  }
}
