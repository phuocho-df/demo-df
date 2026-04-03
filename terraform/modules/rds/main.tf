resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.app_name}-db-subnet-group" }
}

# tfsec:ignore:aws-rds-enable-performance-insights — disabled intentionally to reduce cost
# tfsec:ignore:aws-rds-enable-iam-auth — IAM auth not required for this app's connection pattern
resource "aws_db_instance" "main" {
  identifier        = "${var.app_name}-db"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]

  # Single-AZ, no standby — saves ~$15/month vs Multi-AZ
  multi_az = false

  # Minimal backup retention (7 days)
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # Skip final snapshot on destroy for dev ease; set true for production safety
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.app_name}-db-final-snapshot"
  deletion_protection     = false # tfsec:ignore:aws-rds-enable-deletion-protection — dev env, intentional

  # Disable enhanced monitoring (saves ~$0.30/hour)
  monitoring_interval = 0

  storage_encrypted          = true
  auto_minor_version_upgrade = true
  publicly_accessible        = false

  tags = { Name = "${var.app_name}-db" }
}
