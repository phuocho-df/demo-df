variable "app_name" {
  description = "Application name used as prefix for all resources"
  type        = string
  default     = "django-template"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain name for ACM certificate and ALB (e.g. dfdemo.space)"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy from ECR"
  type        = string
  default     = "latest"
}

# Database
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "project_name"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

# Application secrets
variable "secret_key" {
  description = "Django SECRET_KEY"
  type        = string
  sensitive   = true
}

variable "jwt_signing_key" {
  description = "JWT signing key for djangorestframework-simplejwt"
  type        = string
  sensitive   = true
}

variable "cors_allowed_origins" {
  description = "Comma-separated list of allowed CORS origins (e.g. https://dfdemo.space)"
  type        = string
}

# Bastion host
variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS — created manually in AWS Console"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token with repo scope — used to set Actions secrets via Terraform"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository in org/repo format — scopes OIDC trust to master branch (e.g. my-org/my-repo)"
  type        = string
}

variable "bastion_public_key" {
  description = "SSH public key content for the bastion host key pair (paste contents of ~/.ssh/id_rsa.pub)"
  type        = string
}

variable "alarm_email" {
  description = "Email address to receive CloudWatch alarm notifications (optional)"
  type        = string
  default     = null
}

variable "certbot_email" {
  description = "Email address for Let's Encrypt certificate registration (required for reverse proxy SSL)"
  type        = string
  default     = ""
}

variable "certbot_staging" {
  description = "Use Let's Encrypt staging environment (true = staging/test, false = production cert)"
  type        = bool
  default     = false
}
