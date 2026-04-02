output "role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions during deploy"
  value       = aws_iam_role.github_deploy.arn
}
