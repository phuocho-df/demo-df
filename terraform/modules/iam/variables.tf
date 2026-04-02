variable "app_name" {
  description = "Application name used as prefix for IAM resources"
  type        = string
}

variable "ssm_parameter_arns" {
  description = "List of SSM parameter ARNs the task execution role can read"
  type        = list(string)
}
