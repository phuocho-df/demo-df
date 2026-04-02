variable "app_name" {
  description = "Application name used as prefix for resources"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID where the bastion EC2 instance will be launched"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID to attach to the bastion instance"
  type        = string
}

variable "public_key" {
  description = "SSH public key content for the bastion key pair (e.g. contents of ~/.ssh/id_rsa.pub)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}
