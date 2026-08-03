# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint is static and required by AWS
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

# IAM Role that GitHub Actions will assume
resource "aws_iam_role" "github_actions_role" {
  name = "${var.project_name}-${var.environment}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/*"
          }
        }
      }
    ]
  })
}

# Policies for the GitHub Actions Role
# 1. ECR access to push images
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# 2. ECS access to force new deployments
resource "aws_iam_policy" "github_actions_ecs_deploy" {
  name        = "${var.project_name}-${var.environment}-github-actions-ecs-policy"
  description = "Allows GitHub Actions to deploy to ECS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = [
          "arn:aws:ecs:${var.aws_region}:*:service/${var.project_name}-${var.environment}-cluster/${var.project_name}-${var.environment}-backend-service",
          "arn:aws:ecs:${var.aws_region}:*:service/${var.project_name}-${var.environment}-cluster/${var.project_name}-${var.environment}-cms-service",
          "arn:aws:ecs:${var.aws_region}:*:service/${var.project_name}-${var.environment}-cluster/${var.project_name}-${var.environment}-keycloak-service",
          "arn:aws:ecs:${var.aws_region}:*:service/${var.project_name}-${var.environment}-cluster/${var.project_name}-${var.environment}-analytics-service"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecs" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_actions_ecs_deploy.arn
}

output "github_actions_role_arn" {
  description = "Role ARN to use in GitHub Actions for OIDC authentication"
  value       = aws_iam_role.github_actions_role.arn
}
