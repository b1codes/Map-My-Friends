# Infrastructure (Google Cloud)

Terraform for production: the API on Cloud Run, data in Firestore, uploaded photos in Cloud Storage, and the web app on Firebase Hosting. It's built to cost nothing at no traffic. The API scales to zero, and everything else sits inside a free tier at this app's size.

| File | What it creates |
| --- | --- |
| `cloud_run.tf` | The API service: 1 vCPU, 512 MiB, 8 requests per instance, 0 to `max_instances` (default 3), probes on `/health`, settings as env, `DJANGO_SECRET_KEY` from Secret Manager. Public (the API does its own auth). |
| `artifact_registry.tf` | The image repository. It keeps the 5 most recent images and deletes older ones after 7 days. |
| `firestore.tf` | The `(default)` Firestore database, with delete protection. `terraform destroy` leaves it alone. |
| `storage.tf` | The photo bucket. Objects are readable by URL, the bucket can't be listed, CORS is open to the web app only, and soft delete keeps deletions for 7 days. |
| `secrets.tf` | `DJANGO_SECRET_KEY`, generated and written write-only, so it's never in Terraform's state. |
| `hosting.tf` | The Firebase project and Hosting site for the web app. |
| `iam.tf` | Two service accounts: `api-runtime`, which the service runs as (Firestore data, the bucket's objects, the secret), and `github-deployer`, which the release acts as through Workload Identity Federation. There's no key. Only `release.yml` on `main` in this repository can get a token for it. |
| `apis.tf` | The Google APIs these need. |

What's checked, on every PR and with `make check-infra`, with no GCP project needed: `terraform fmt` and `validate`, `terraform test` (`tests/infra.tftest.hcl`, providers mocked), tflint with the Google ruleset, and `trivy config`. The two deliberate exceptions carry a `#trivy:ignore` with the reason: the bucket's public object reads, and no object versioning.

> **Not ready for real users yet.** Django's own tables (users, the refresh-token blacklist) live in SQLite on the instance's disk, so every account disappears when an instance stops, which happens when it scales to zero. The migration to Google Cloud Identity Platform fixes that (ClickUp 86bb3eu64). Until it lands, a deploy works and passes its smoke test, but nobody stays signed up. The release is switched off until the repository variables below are set.

## Bootstrapping (once)

You need `gcloud` and Terraform 1.11 or newer, and a Google Cloud project with billing enabled.

```sh
PROJECT=your-gcp-project-id
gcloud auth login
gcloud auth application-default login
gcloud config set project "$PROJECT"

# Terraform's state bucket. It's the one thing Terraform can't create for itself.
gcloud services enable storage.googleapis.com
gcloud storage buckets create "gs://$PROJECT-tfstate" \
  --location=us-central1 --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://$PROJECT-tfstate" --versioning

cd infra
cp terraform.tfvars.example terraform.tfvars   # set project_id
terraform init -backend-config="bucket=$PROJECT-tfstate"
terraform apply
```

If the project already has Firebase and its default Hosting site, the apply reports that they exist. Import them, then apply again:

```sh
terraform import google_firebase_project.this "projects/$PROJECT"
terraform import google_firebase_hosting_site.web "projects/$PROJECT/sites/$PROJECT"
```

The service starts on Google's placeholder image. The first release replaces it.

## Connecting the release

`.github/workflows/release.yml` deploys only once these **repository variables** exist (Settings → Secrets and variables → Actions → Variables). They aren't secrets, and each comes from `terraform output`:

| Variable | `terraform output` |
| --- | --- |
| `GCP_PROJECT_ID` | the `project_id` you applied with |
| `GCP_REGION` | `region` |
| `GCP_SERVICE_NAME` | `service_name` |
| `GCP_IMAGE_REPOSITORY` | `image_repository` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `workload_identity_provider` |
| `GCP_DEPLOYER_SERVICE_ACCOUNT` | `deployer_service_account` |
| `API_URL` | `api_url` |
| `CANDIDATE_URL` | `candidate_url` |
| `FIREBASE_HOSTING_SITE` | `hosting_site_id` |

For the hourly production smoke check (`smoke.yml`), also set `SMOKE_BASE_URL` to `api_url`.

What a release does with them is in [docs/deploy.md](../docs/deploy.md).

## Changing things

- **The image or traffic:** don't, from Terraform. It ignores both, and the release owns them.
- **Settings the API reads:** `locals.tf` (`api_env`). A changed value deploys a new revision with the current image on the next `terraform apply`.
- **Rotating `DJANGO_SECRET_KEY`:** bump `secret_data_wo_version` in `secrets.tf` and apply, then redeploy (or `gcloud run services update`) so instances pick up the new version. This signs everyone out.
- **Cost:** `max_instances` caps the API. Firestore and Storage bill by use, past their free tiers.
