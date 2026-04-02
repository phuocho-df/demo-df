module "networking" {
  source   = "./modules/networking"
  app_name = var.app_name
}

module "ecr" {
  source   = "./modules/ecr"
  app_name = var.app_name
}

module "ssm" {
  source          = "./modules/ssm"
  app_name        = var.app_name
  secret_key      = var.secret_key
  jwt_signing_key = var.jwt_signing_key
  db_password     = var.db_password
}

module "iam" {
  source             = "./modules/iam"
  app_name           = var.app_name
  ssm_parameter_arns = module.ssm.all_parameter_arns
}

module "rds" {
  source            = "./modules/rds"
  app_name          = var.app_name
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.networking.sg_rds_id
}

module "github_oidc" {
  source   = "./modules/github-oidc"
  app_name = var.app_name

  github_repo = var.github_repo

  ecr_repository_arn      = module.ecr.repository_arn
  ecs_service_arn         = module.ecs.service_arn
  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arn
}

module "bastion" {
  source            = "./modules/bastion"
  app_name          = var.app_name
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = module.networking.sg_bastion_id
  public_key        = var.bastion_public_key
}

module "alb" {
  source            = "./modules/alb"
  app_name          = var.app_name
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.public_subnet_ids
  security_group_id = module.networking.sg_alb_id
  certificate_arn   = var.certificate_arn
}


module "ecs" {
  source   = "./modules/ecs"
  app_name = var.app_name

  aws_region         = var.aws_region
  ecr_repository_url = module.ecr.repository_url
  image_tag          = var.image_tag

  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arn

  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.networking.sg_ecs_id
  target_group_arn  = module.alb.target_group_arn

  # Non-sensitive app config
  allowed_hosts        = "${var.domain_name},${module.alb.alb_dns_name},localhost,127.0.0.1"
  host                 = "https://${var.domain_name}/"
  db_name              = var.db_name
  db_username          = var.db_username
  db_host              = module.rds.endpoint
  db_port              = tostring(module.rds.port)
  cors_allowed_origins = var.cors_allowed_origins

  # SSM secret references
  ssm_secret_key_arn      = module.ssm.secret_key_arn
  ssm_jwt_signing_key_arn = module.ssm.jwt_signing_key_arn
  ssm_db_password_arn     = module.ssm.db_password_arn
}

# Route53 ALIAS record — points domain apex to ALB (no IP hardcoding, auto-updates with ALB)
resource "aws_route53_record" "apex" {
  zone_id = "Z00838981JEIAH0UK6QW6"
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# GitHub Actions secrets — set automatically on every terraform apply
locals {
  repo_name = split("/", var.github_repo)[1]
}

resource "github_actions_secret" "aws_role_arn" {
  repository      = local.repo_name
  secret_name     = "AWS_ROLE_ARN"
  plaintext_value = module.github_oidc.role_arn
}

resource "github_actions_secret" "ecr_repository_url" {
  repository      = local.repo_name
  secret_name     = "ECR_REPOSITORY_URL"
  plaintext_value = module.ecr.repository_url
}

resource "github_actions_secret" "ecs_cluster_name" {
  repository      = local.repo_name
  secret_name     = "ECS_CLUSTER_NAME"
  plaintext_value = module.ecs.cluster_name
}

resource "github_actions_secret" "ecs_service_name" {
  repository      = local.repo_name
  secret_name     = "ECS_SERVICE_NAME"
  plaintext_value = module.ecs.service_name
}

resource "github_actions_secret" "ecs_task_family" {
  repository      = local.repo_name
  secret_name     = "ECS_TASK_FAMILY"
  plaintext_value = var.app_name
}

resource "github_actions_secret" "ecs_container_name" {
  repository      = local.repo_name
  secret_name     = "ECS_CONTAINER_NAME"
  plaintext_value = var.app_name
}

resource "github_actions_secret" "terraform_role_arn" {
  repository      = local.repo_name
  secret_name     = "TERRAFORM_ROLE_ARN"
  plaintext_value = module.github_oidc.terraform_role_arn
}
