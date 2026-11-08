# tflint for infra/ (make lint-infra, and the Validate Terraform CI job).
# The Terraform language's recommended rules, plus the Google ruleset, which
# checks values the provider only rejects at apply time (machine types,
# regions, IAM role names, ...).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
