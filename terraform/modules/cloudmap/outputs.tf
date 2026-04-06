output "service_arn" {
  description = "Cloud Map service ARN — used by ECS service_registries"
  value       = aws_service_discovery_service.app.arn
}

output "service_dns" {
  description = "DNS name tasks register under (use as Nginx upstream)"
  value       = "app.${aws_service_discovery_private_dns_namespace.main.name}"
}
