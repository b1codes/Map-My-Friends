#!/usr/bin/env bash
# Checks infra/ (the GCP Terraform): `make check-infra`, and the Validate
# Terraform job in CI. No Google Cloud project or credentials are needed.
#
#   1. terraform fmt: everything is formatted.
#   2. terraform validate: the configuration is internally consistent
#      against the locked providers' schemas.
#   3. terraform test: infra/tests/*.tftest.hcl, with the providers mocked.
#      What the resources must be: cost caps, public exposure, least
#      privilege, who may deploy, what the API needs to start.
#   4. tflint, with the recommended Terraform rules and the Google ruleset.
#   5. trivy config: security misconfigurations at MEDIUM and above. A
#      deliberate exception carries a #trivy:ignore with its reason.
#
# tflint downloads its Google ruleset from GitHub; set GITHUB_TOKEN to avoid
# the anonymous rate limit (CI does).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/tool-images.sh
source "$ROOT/scripts/tool-images.sh"
CACHE="$ROOT/build/infra-cache"
mkdir -p "$CACHE/terraform-plugins" "$CACHE/tflint-plugins" "$CACHE/trivy"

terraform() {
  docker run --rm \
    -v "$ROOT/infra:/infra" -w /infra \
    -v "$CACHE/terraform-plugins:/plugin-cache" \
    -e TF_PLUGIN_CACHE_DIR=/plugin-cache \
    -e TF_IN_AUTOMATION=1 \
    "$TERRAFORM_IMAGE" "$@"
}

echo "== terraform fmt"
terraform fmt -check -recursive -diff

echo "== terraform init (no backend) and validate"
# The lock file pins the providers; init must not change it.
terraform init -backend=false -input=false -lockfile=readonly >/dev/null
terraform validate

echo "== terraform test (providers mocked)"
terraform test

echo "== tflint"
docker run --rm \
  -v "$ROOT/infra:/data" -w /data \
  -v "$CACHE/tflint-plugins:/plugins" \
  -e TFLINT_PLUGIN_DIR=/plugins \
  -e GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
  --entrypoint sh "$TFLINT_IMAGE" \
  -c 'tflint --init >/dev/null && tflint --recursive --format compact'

echo "== trivy config"
docker run --rm \
  -v "$ROOT/infra:/infra:ro" \
  -v "$CACHE/trivy:/root/.cache" \
  "$TRIVY_IMAGE" config --quiet --exit-code 1 \
  --severity MEDIUM,HIGH,CRITICAL /infra

echo "All infra checks passed."
