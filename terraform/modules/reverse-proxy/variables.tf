variable "app_name" {
  description = "Application name used as prefix for resources"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID where the reverse proxy EC2 instance will be launched"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID to attach to the reverse proxy instance"
  type        = string
}

variable "domain_name" {
  description = "Domain name the reverse proxy will serve (used in Nginx server_name)"
  type        = string
}

variable "upstream_url" {
  description = "ALB DNS name or upstream URL to proxy traffic to"
  type        = string
}

variable "certbot_email" {
  description = "Email address for Let's Encrypt certificate notifications and recovery"
  type        = string
}

variable "cert_bucket" {
  description = "S3 bucket name for Let's Encrypt cert backup/restore (managed outside Terraform)"
  type        = string
}

variable "certbot_staging" {
  description = "Use Let's Encrypt staging environment — avoids rate limits during testing, certs not trusted by browsers"
  type        = bool
  default     = false
}
