terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Variables
variable "organization_config" {
  description = "Full organization configuration from YAML"
  type        = any
}

variable "environment" {
  description = "Current deployment environment"
  type        = string
}

variable "account_ids" {
  description = "Map of account names to their IDs"
  type        = map(string)
}

# Local processing
locals {
  github_config = lookup(var.organization_config, "github_actions", {})
  repositories  = lookup(local.github_config, "repositories", [])
  permissions   = lookup(local.github_config, "permissions", {})
}

# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  count = lookup(local.github_config, "enabled", false) ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "GitHubActions-OIDC"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM Role for GitHub Actions (basic implementation)
resource "aws_iam_role" "github_actions" {
  for_each = lookup(local.github_config, "enabled", false) ? toset([var.environment]) : toset([])

  name = "GitHubActions-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              for repo in local.repositories : "repo:${repo.repo}:*"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "GitHubActions-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Basic policy attachment (can be expanded based on permissions config)
resource "aws_iam_role_policy_attachment" "github_actions_basic" {
  for_each = lookup(local.github_config, "enabled", false) ? toset(["ReadOnlyAccess"]) : toset([])

  role       = aws_iam_role.github_actions[var.environment].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Outputs
output "github_oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN"
  value       = lookup(local.github_config, "enabled", false) ? aws_iam_openid_connect_provider.github[0].arn : null
}

output "github_actions_role_arn" {
  description = "GitHub Actions IAM Role ARN"
  value       = lookup(local.github_config, "enabled", false) ? aws_iam_role.github_actions[var.environment].arn : null
}
