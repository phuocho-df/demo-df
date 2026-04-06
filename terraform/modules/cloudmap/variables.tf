variable "app_name" {
  description = "Application name used as prefix for Cloud Map resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the private DNS namespace"
  type        = string
}
