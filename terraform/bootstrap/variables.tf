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
