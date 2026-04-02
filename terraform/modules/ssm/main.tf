resource "aws_ssm_parameter" "secret_key" {
  name  = "/${var.app_name}/SECRET_KEY"
  type  = "SecureString"
  value = var.secret_key

  tags = { Name = "${var.app_name}-secret-key" }
}

resource "aws_ssm_parameter" "jwt_signing_key" {
  name  = "/${var.app_name}/JWT_SIGNING_KEY"
  type  = "SecureString"
  value = var.jwt_signing_key

  tags = { Name = "${var.app_name}-jwt-signing-key" }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.app_name}/DB_PASSWORD"
  type  = "SecureString"
  value = var.db_password

  tags = { Name = "${var.app_name}-db-password" }
}
