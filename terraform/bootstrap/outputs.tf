output "tf_state_bucket" {
  description = "S3 bucket name for Terraform remote state — use as TF_STATE_BUCKET in GitHub Actions variables"
  value       = aws_s3_bucket.tf_state.bucket
}

output "tf_state_lock_table" {
  description = "DynamoDB table name for Terraform state locking — use as TF_STATE_LOCK_TABLE in GitHub Actions variables"
  value       = aws_dynamodb_table.tf_lock.name
}
