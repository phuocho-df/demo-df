variable "app_name" {
  description = "Application name used as prefix for ECS resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in CloudWatch log configuration)"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the Docker image"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task IAM role"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for ECS tasks (outbound via NAT Gateway)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the ALB target group"
  type        = string
}

# Non-sensitive environment variables
variable "allowed_hosts" {
  description = "Django ALLOWED_HOSTS value"
  type        = string
}

variable "host" {
  description = "Django HOST base URL"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL username"
  type        = string
}

variable "db_host" {
  description = "RDS endpoint hostname"
  type        = string
}

variable "db_port" {
  description = "RDS port"
  type        = string
  default     = "5432"
}

variable "cors_allowed_origins" {
  description = "Comma-separated CORS allowed origins"
  type        = string
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 2
}

variable "alarm_email" {
  description = "Email address to receive CloudWatch alarm notifications (optional)"
  type        = string
  default     = null
}

# SSM parameter ARNs for secrets (injected via valueFrom)
variable "ssm_secret_key_arn" {
  description = "SSM parameter ARN for Django SECRET_KEY"
  type        = string
}

variable "ssm_jwt_signing_key_arn" {
  description = "SSM parameter ARN for JWT_SIGNING_KEY"
  type        = string
}

variable "ssm_db_password_arn" {
  description = "SSM parameter ARN for DB_PASSWORD"
  type        = string
}

variable "cloudmap_service_arn" {
  description = "Cloud Map service ARN for ECS task registration (optional — null disables Cloud Map)"
  type        = string
  default     = null
}
