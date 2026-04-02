variable "app_name" {
  description = "Application name used as prefix for resources"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in org/repo format (e.g. my-org/my-repo) — scopes OIDC trust to this repo's master branch"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN — grants image push permissions to the deploy role"
  type        = string
}

variable "ecs_service_arn" {
  description = "ECS service ARN — grants UpdateService permissions to the deploy role"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN — needed for iam:PassRole when registering task definitions"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN — needed for iam:PassRole when registering task definitions"
  type        = string
}
