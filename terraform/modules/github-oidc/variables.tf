variable "app_name" {
  description = "Application name used as prefix for resources"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in org/repo format (e.g. my-org/my-repo) — scopes OIDC trust to this repo's master branch"
  type        = string
}

