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
}

# Deploy role policy — attached after ECR/ECS/IAM exist (not during bootstrap)
data "aws_iam_policy_document" "github_deploy" {
  # ECR auth token is account-scoped — no resource restriction possible
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # ECR image push/pull scoped to this app's repository only
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [module.ecr.repository_arn]
  }

  statement {
    sid    = "ECSTaskDef"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECSService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [module.ecs.service_arn]
  }

  # PassRole required so ECS can attach execution and task roles to new task def revisions
  statement {
    sid     = "IAMPassRole"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      module.iam.task_execution_role_arn,
      module.iam.task_role_arn,
    ]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.app_name}-github-deploy-policy"
  role   = module.github_oidc.deploy_role_id
  policy = data.aws_iam_policy_document.github_deploy.json
}

module "cloudmap" {
  source   = "./modules/cloudmap"
  app_name = var.app_name
  vpc_id   = module.networking.vpc_id
}

# tfsec:ignore:aws-ec2-add-description-to-security-group-rule — descriptions already present on each ingress/egress block
# Security group for reverse proxy — allows HTTP/HTTPS from internet, outbound to ALB
resource "aws_security_group" "reverse_proxy" {
  name        = "${var.app_name}-reverse-proxy-sg"
  description = "Allow HTTP/HTTPS inbound, all outbound"
  vpc_id      = module.networking.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tfsec:ignore:aws-ec2-no-public-ingress-sgr
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tfsec:ignore:aws-ec2-no-public-ingress-sgr
  }

  egress {
    description = "All outbound traffic to ALB and internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # tfsec:ignore:aws-ec2-no-public-egress-sgr
  }

  tags = { Name = "${var.app_name}-reverse-proxy-sg" }
}

# Allow reverse proxy EC2 to reach ECS tasks directly (Cloud Map path)
resource "aws_security_group_rule" "ecs_from_reverse_proxy" {
  type                     = "ingress"
  description              = "HTTP from reverse proxy (Cloud Map direct routing)"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = module.networking.sg_ecs_id
  source_security_group_id = aws_security_group.reverse_proxy.id
}

module "reverse_proxy" {
  source            = "./modules/reverse-proxy"
  app_name          = var.app_name
  subnet_id         = module.networking.public_subnet_ids[0]
  security_group_id = aws_security_group.reverse_proxy.id
  domain_name       = var.domain_name
  upstream_url      = module.cloudmap.service_dns # resolve ECS task IPs via Cloud Map
  certbot_email     = var.certbot_email
  cert_bucket       = "${var.app_name}-letsencrypt-cert"
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

  alarm_email = var.alarm_email

  cloudmap_service_arn = module.cloudmap.service_arn
}

# Route53 weighted record — ALB (weight=100, primary traffic)
resource "aws_route53_record" "apex_alb" {
  zone_id        = "Z00838981JEIAH0UK6QW6"
  name           = var.domain_name
  type           = "A"
  set_identifier = "alb"

  weighted_routing_policy {
    weight = 50
  }

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# Route53 weighted record — Reverse Proxy EIP (weight=0, standby — increase to shift traffic)
resource "aws_route53_record" "apex_proxy" {
  zone_id        = "Z00838981JEIAH0UK6QW6"
  name           = var.domain_name
  type           = "A"
  ttl            = 60
  set_identifier = "reverse-proxy"

  weighted_routing_policy {
    weight = 50
  }

  records = [module.reverse_proxy.public_ip]
}

# Route53 health check — monitors /api/health endpoint over HTTPS
resource "aws_route53_health_check" "api" {
  fqdn              = var.domain_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/api/health"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "${var.app_name}-api-health-check" }
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
