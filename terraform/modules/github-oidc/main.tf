# GitHub Actions OIDC provider — allows GitHub Actions to assume AWS roles
# without long-lived IAM credentials stored in GitHub Secrets
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's current OIDC certificate thumbprints
  # AWS also validates via JWKS but the API requires at least one thumbprint
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = { Name = "${var.app_name}-github-oidc" }
}

# Trust policy — only GitHub Actions on the master branch of the configured repo can assume this role
data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to main and master branches of the specific repo
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [
        "repo:${var.github_repo}:ref:refs/heads/master",
        "repo:${var.github_repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.app_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = { Name = "${var.app_name}-github-deploy" }
}

# Least-privilege deploy policy: ECR push + ECS task def registration + service update
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
    resources = [var.ecr_repository_arn]
  }

  # ECS task definition — DescribeTaskDefinition has no resource-level support
  statement {
    sid    = "ECSTaskDef"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"]
  }

  # ECS service update scoped to this app's service only
  statement {
    sid    = "ECSService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [var.ecs_service_arn]
  }

  # PassRole required so ECS can attach execution and task roles to new task def revisions
  statement {
    sid     = "IAMPassRole"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      var.task_execution_role_arn,
      var.task_role_arn,
    ]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.app_name}-github-deploy-policy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

# Terraform role — assumed by GitHub Actions terraform-ci/cd/destroy workflows
# Needs broad permissions to create/modify/destroy all managed AWS resources
resource "aws_iam_role" "github_terraform" {
  name               = "${var.app_name}-github-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = { Name = "${var.app_name}-github-terraform" }
}

resource "aws_iam_role_policy_attachment" "github_terraform_admin" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
