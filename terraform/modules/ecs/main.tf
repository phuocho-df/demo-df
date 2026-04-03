# tfsec:ignore:aws-cloudwatch-log-group-customer-key — KMS encryption not required for app logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.app_name}/ecs"
  retention_in_days = 7 # Minimal retention to keep CloudWatch cost low

  tags = { Name = "${var.app_name}-logs" }
}

# tfsec:ignore:aws-ecs-enable-container-insight — container insights disabled intentionally (cost)
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"

  # Disable Container Insights to avoid extra CloudWatch cost (~$0.30/GB)
  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = { Name = "${var.app_name}-cluster" }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # Smallest Fargate size: 256 CPU / 512 MB — sufficient for Django + Gunicorn
  cpu    = 256
  memory = 512

  execution_role_arn = var.task_execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode([{
    name      = var.app_name
    image     = "${var.ecr_repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    # Non-sensitive environment variables passed as plain values
    environment = [
      { name = "ENV", value = "production" },
      { name = "ALLOWED_HOSTS", value = var.allowed_hosts },
      { name = "HOST", value = var.host },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_USERNAME", value = var.db_username },
      { name = "DB_HOST", value = var.db_host },
      { name = "DB_PORT", value = var.db_port },
      { name = "CORS_ALLOWED_ORIGINS", value = var.cors_allowed_origins },
    ]

    # Sensitive values pulled from SSM Parameter Store at runtime
    secrets = [
      { name = "SECRET_KEY", valueFrom = var.ssm_secret_key_arn },
      { name = "JWT_SIGNING_KEY", valueFrom = var.ssm_jwt_signing_key_arn },
      { name = "DB_PASSWORD", valueFrom = var.ssm_db_password_arn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:80/api/v1/docs || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 60 # Allow time for Django migrations on cold start
    }
  }])

  tags = { Name = "${var.app_name}-task" }
}

resource "aws_ecs_service" "app" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count = 1

  # Fargate Spot: up to 70% cheaper than on-demand — suitable for low-traffic workloads.
  # AWS may reclaim Spot capacity with 2-min notice; circuit breaker handles failover.
  # Switch to launch_type = "FARGATE" if uptime is critical.
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    # Tasks in private subnets — outbound internet via NAT Gateway
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.app_name
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Ignore task_definition changes so image updates via CI/CD don't cause drift
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Name = "${var.app_name}-service" }
}

# SNS topic for CloudWatch alarm notifications
resource "aws_sns_topic" "alarms" {
  name = "${var.app_name}-alarms"
  tags = { Name = "${var.app_name}-alarms" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# CloudWatch alarm — ECS CPU utilization high
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.app_name}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "ECS CPU utilization > 85% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  tags = { Name = "${var.app_name}-ecs-cpu-high" }
}

# CloudWatch alarm — ECS memory utilization high
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${var.app_name}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "ECS memory utilization > 85% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  tags = { Name = "${var.app_name}-ecs-memory-high" }
}

# Auto-scaling target — tracks the ECS service desired count
resource "aws_appautoscaling_target" "app" {
  max_capacity       = var.max_capacity
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale out when average CPU > 70% for 2 consecutive periods
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.app_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70
    scale_out_cooldown = 60
    scale_in_cooldown  = 120
  }
}

# Scale out when average memory > 80% for 2 consecutive periods
resource "aws_appautoscaling_policy" "memory" {
  name               = "${var.app_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80
    scale_out_cooldown = 60
    scale_in_cooldown  = 120
  }
}
