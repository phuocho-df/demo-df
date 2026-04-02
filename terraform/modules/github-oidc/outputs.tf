output "role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions during deploy"
  value       = aws_iam_role.github_deploy.arn
}

output "terraform_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions for Terraform CI/CD operations"
  value       = aws_iam_role.github_terraform.arn
}
