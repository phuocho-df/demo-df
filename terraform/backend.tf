# Partial backend configuration — dynamic values (bucket, region, dynamodb_table)
# are injected at runtime via -backend-config flags in CI/CD workflows.
# See .github/workflows/terraform-ci.yml and terraform-cd.yml for the init step.
terraform {
  backend "s3" {
    key     = "terraform.tfstate"
    encrypt = true
  }
}
