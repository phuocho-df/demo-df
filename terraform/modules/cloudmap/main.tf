# Private DNS namespace — ECS tasks register under <app_name>.internal
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "${var.app_name}.internal"
  vpc  = var.vpc_id

  tags = { Name = "${var.app_name}-cloudmap-namespace" }
}

# Service registry — ECS registers each task IP here on startup
resource "aws_service_discovery_service" "app" {
  name = "app"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE" # return all healthy task IPs

    dns_records {
      type = "A"
      ttl  = 10 # short TTL so Nginx picks up new tasks quickly
    }
  }

  # Custom health check — ECS manages task health, Cloud Map trusts ECS
  health_check_custom_config {
    failure_threshold = 1
  }

  tags = { Name = "${var.app_name}-cloudmap-service" }
}
