output "service_arn" {
  description = "ECS service ARN"
  value       = aws_ecs_service.app.id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "task_definition_arn" {
  description = "Latest ECS task definition ARN"
  value       = aws_ecs_task_definition.app.arn
}

output "log_group_name" {
  description = "CloudWatch log group name for ECS container logs"
  value       = aws_cloudwatch_log_group.app.name
}

output "autoscaling_target_resource_id" {
  description = "Auto-scaling resource ID (service/cluster/service-name)"
  value       = aws_appautoscaling_target.app.resource_id
}
