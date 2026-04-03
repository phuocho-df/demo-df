output "role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions during deploy"
  value       = aws_iam_role.github_deploy.arn
}

output "deploy_role_id" {
  description = "ID of the deploy IAM role — used to attach the deploy policy from main.tf"
  value       = aws_iam_role.github_deploy.id
}

output "terraform_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions for Terraform CI/CD operations"
  value       = aws_iam_role.github_terraform.arn
}
