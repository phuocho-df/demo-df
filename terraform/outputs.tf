output "github_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC deploy — set as AWS_ROLE_ARN secret in GitHub"
  value       = module.github_oidc.role_arn
}

output "github_terraform_role_arn" {
  description = "IAM role ARN for Terraform CI/CD — set as TERRAFORM_ROLE_ARN secret in GitHub"
  value       = module.github_oidc.terraform_role_arn
}

output "bastion_public_ip" {
  description = "Bastion host public IP — SSH tunnel entry point for RDS migration"
  value       = module.bastion.public_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL — use this to build and push your Docker image"
  value       = module.ecr.repository_url
}

output "alb_dns_name" {
  description = "ALB DNS name — point your domain CNAME here"
  value       = module.alb.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint hostname"
  value       = module.rds.endpoint
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for ECS container logs"
  value       = module.ecs.log_group_name
}

output "docker_push_commands" {
  description = "Commands to build and push your Docker image to ECR"
  value       = <<-EOT
    # Authenticate Docker to ECR (replace REGION with your aws_region value)
    aws ecr get-login-password --region REGION | docker login --username AWS --password-stdin ${module.ecr.repository_url}

    # Build and push
    docker build -t ${module.ecr.repository_url}:latest .
    docker push ${module.ecr.repository_url}:latest
  EOT
}
