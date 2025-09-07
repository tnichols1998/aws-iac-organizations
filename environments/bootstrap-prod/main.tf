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
  description = "Path to organization configuration YAML file"
  type        = string
  default     = "../../config/organizations/petunka-holdings.yaml"
}

variable "environment" {
  description = "Environment name (used for naming and tagging)"
  type        = string
  default     = "bootstrap"
}

variable "github_repositories" {
  description = "List of GitHub repositories that can assume the OIDC role"
  type        = list(string)
  default = [
    "tnichols1998/aws-iac-organizations"
  ]
}

# Load organization configuration
locals {
  org_config_raw = file(var.organization_config)
  org_config     = yamldecode(local.org_config_raw)
}

# Provider configuration
provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "aws-iac-organizations-bootstrap"
      Phase       = "bootstrap"
    }
  }
}

# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's thumbprints - these are stable and rarely change
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "GitHubActions-OIDC"
    Description = "OIDC provider for GitHub Actions"
  }
}

# IAM Role for GitHub Actions with comprehensive permissions for infrastructure management
resource "aws_iam_role" "github_actions_admin" {
  name = "GitHubActions-OrganizationAdmin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              for repo in var.github_repositories : "repo:${repo}:*"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "GitHubActions-OrganizationAdmin"
    Description = "Admin role for GitHub Actions to manage AWS Organizations infrastructure"
    Purpose     = "CI/CD Infrastructure Management"
  }
}

# Custom policy for GitHub Actions with comprehensive AWS Organizations permissions
resource "aws_iam_role_policy" "github_actions_organizations" {
  name = "GitHubActions-OrganizationsManagement"
  role = aws_iam_role.github_actions_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OrganizationsFullAccess"
        Effect = "Allow"
        Action = [
          "organizations:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMFullAccess"
        Effect = "Allow"
        Action = [
          "iam:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSOFullAccess"
        Effect = "Allow"
        Action = [
          "sso:*",
          "sso-admin:*",
          "identitystore:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudTrailAccess"
        Effect = "Allow"
        Action = [
          "cloudtrail:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "GuardDutyAccess"
        Effect = "Allow"
        Action = [
          "guardduty:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecurityHubAccess"
        Effect = "Allow"
        Action = [
          "securityhub:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ConfigAccess"
        Effect = "Allow"
        Action = [
          "config:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:CreateBucket",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock"
        ]
        Resource = [
          "arn:aws:s3:::terraform-state-*",
          "arn:aws:s3:::terraform-state-*/*"
        ]
      },
      {
        Sid    = "DynamoDBStateAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:CreateTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:UpdateTimeToLive"
        ]
        Resource = [
          "arn:aws:dynamodb:*:*:table/terraform-state-lock-*"
        ]
      },
      {
        Sid    = "ReadOnlyAccess"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "sts:AssumeRole",
          "ec2:DescribeRegions",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      }
    ]
  })
}

# Outputs for use in GitHub Actions
output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions admin role"
  value       = aws_iam_role.github_actions_admin.arn
}

output "organization_info" {
  description = "Organization information for reference"
  value = {
    organization_name = local.org_config.metadata.name
    environments      = keys(local.org_config.environments)
  }
}

# Create outputs file for GitHub Actions workflows
resource "local_file" "github_outputs" {
  content = templatefile("${path.module}/github-outputs.tpl", {
    github_actions_role_arn = aws_iam_role.github_actions_admin.arn
    organization_name       = local.org_config.metadata.name
    region                  = "us-west-2"
  })
  filename = "${path.module}/../../.github/workflows/terraform-outputs.yml"
}
