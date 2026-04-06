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
