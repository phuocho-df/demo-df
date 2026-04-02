output "secret_key_arn" {
  description = "ARN of the SECRET_KEY SSM parameter"
  value       = aws_ssm_parameter.secret_key.arn
}

output "jwt_signing_key_arn" {
  description = "ARN of the JWT_SIGNING_KEY SSM parameter"
  value       = aws_ssm_parameter.jwt_signing_key.arn
}

output "db_password_arn" {
  description = "ARN of the DB_PASSWORD SSM parameter"
  value       = aws_ssm_parameter.db_password.arn
}

output "all_parameter_arns" {
  description = "All SSM parameter ARNs (for IAM policy)"
  value = [
    aws_ssm_parameter.secret_key.arn,
    aws_ssm_parameter.jwt_signing_key.arn,
    aws_ssm_parameter.db_password.arn,
  ]
}
