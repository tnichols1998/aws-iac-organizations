terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "organization_root_id" {
  description = "The organization root ID to attach policies to"
  type        = string
}

variable "organization_config" {
  description = "Full organization configuration from YAML"
  type        = any
}

variable "environment" {
  description = "Current deployment environment"
  type        = string
}

# Local processing
locals {
  org_config = var.organization_config.organization
  policies   = lookup(var.organization_config, "policies", {})
  
  # Default SCPs that should always be applied
  default_scps = [
    "prevent_org_changes",
    "region_restrictions", 
    "prevent_security_service_disabling"
  ]
  
  # Get SCPs from config or use defaults
  scp_policies = lookup(local.policies, "service_control_policies", [])
}

# Prevent organization changes and security service disabling
resource "aws_organizations_policy" "prevent_org_changes" {
  name        = "PreventOrganizationChanges"
  description = "Prevent leaving organization and disabling security services"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PreventLeavingOrganization"
        Effect = "Deny"
        Action = [
          "organizations:LeaveOrganization",
          "organizations:CloseAccount"
        ]
        Resource = "*"
      },
      {
        Sid    = "PreventDisablingSecurityServices"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DeleteInvitations",
          "guardduty:DeleteMembers",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:DisassociateMembers",
          "guardduty:StopMonitoringMembers",
          "securityhub:DeleteInvitations",
          "securityhub:DisableSecurityHub",
          "securityhub:DisassociateFromMasterAccount",
          "securityhub:DeleteMembers",
          "securityhub:DisassociateMembers",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = {
    Name        = "PreventOrganizationChanges"
    Environment = var.environment
    ManagedBy   = "terraform"
    PolicyType  = "ServiceControlPolicy"
  }
}

resource "aws_organizations_policy_attachment" "prevent_org_changes" {
  policy_id = aws_organizations_policy.prevent_org_changes.id
  target_id = var.organization_root_id
}

# Region restrictions
resource "aws_organizations_policy" "region_restrictions" {
  name        = "RestrictRegions"
  description = "Restrict access to approved regions only"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RestrictRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "cloudfront:*",
          "waf:*",
          "wafv2:*",
          "waf-regional:*",
          "trustedadvisor:*",
          "support:*",
          "budgets:*",
          "ce:*",
          "health:*",
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = local.org_config.allowed_regions
          }
          ArnNotLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::*:role/OrganizationAccountAccessRole",
              "arn:aws:iam::*:role/AWSControlTowerExecution",
              "arn:aws:iam::*:role/AWSServiceRole*"
            ]
          }
        }
      }
    ]
  })
  
  tags = {
    Name        = "RestrictRegions"
    Environment = var.environment
    ManagedBy   = "terraform"
    PolicyType  = "ServiceControlPolicy"
  }
}

resource "aws_organizations_policy_attachment" "region_restrictions" {
  policy_id = aws_organizations_policy.region_restrictions.id
  target_id = var.organization_root_id
}

# Prevent public S3 buckets
resource "aws_organizations_policy" "prevent_public_s3" {
  name        = "PreventPublicS3"
  description = "Prevent creation of public S3 buckets"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PreventPublicS3Buckets"
        Effect = "Deny"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:DeleteBucketPublicAccessBlock",
          "s3:PutBucketPolicy",
          "s3:PutBucketAcl",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "arn:aws:s3:::*/*",
          "arn:aws:s3:::*"
        ]
        Condition = {
          StringNotEquals = {
            "s3:x-amz-acl" = "private"
          }
        }
      },
      {
        Sid    = "PreventPublicBucketPolicy"
        Effect = "Deny"
        Action = [
          "s3:PutBucketPolicy"
        ]
        Resource = "arn:aws:s3:::*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
  
  tags = {
    Name        = "PreventPublicS3"
    Environment = var.environment
    ManagedBy   = "terraform"
    PolicyType  = "ServiceControlPolicy"
  }
}

resource "aws_organizations_policy_attachment" "prevent_public_s3" {
  policy_id = aws_organizations_policy.prevent_public_s3.id
  target_id = var.organization_root_id
}

# Environment-specific restrictions for non-production
resource "aws_organizations_policy" "non_production_restrictions" {
  count = var.environment != "prod" ? 1 : 0
  
  name        = "NonProductionRestrictions"
  description = "Additional restrictions for development and testing environments"
  type        = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RestrictExpensiveServices"
        Effect = "Deny"
        Action = [
          "redshift:*",
          "elasticsearch:*",
          "es:*",
          "rds:CreateDBCluster",
          "rds:CreateDBInstance",
          "ec2:RunInstances"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringNotLike" = {
            "ec2:InstanceType" = [
              "t2.*",
              "t3.*",
              "t3a.*",
              "t4g.*"
            ]
          }
        }
      }
    ]
  })
  
  tags = {
    Name        = "NonProductionRestrictions"
    Environment = var.environment
    ManagedBy   = "terraform"
    PolicyType  = "ServiceControlPolicy"
  }
}

resource "aws_organizations_policy_attachment" "non_production_restrictions" {
  count = var.environment != "prod" ? 1 : 0
  
  policy_id = aws_organizations_policy.non_production_restrictions[0].id
  target_id = var.organization_root_id
}

# Outputs
output "policy_ids" {
  description = "Map of SCP policy names to their IDs"
  value = merge(
    {
      prevent_org_changes    = aws_organizations_policy.prevent_org_changes.id
      region_restrictions    = aws_organizations_policy.region_restrictions.id
      prevent_public_s3      = aws_organizations_policy.prevent_public_s3.id
    },
    var.environment != "prod" ? {
      non_production_restrictions = aws_organizations_policy.non_production_restrictions[0].id
    } : {}
  )
}

output "policy_arns" {
  description = "Map of SCP policy names to their ARNs"
  value = merge(
    {
      prevent_org_changes    = aws_organizations_policy.prevent_org_changes.arn
      region_restrictions    = aws_organizations_policy.region_restrictions.arn
      prevent_public_s3      = aws_organizations_policy.prevent_public_s3.arn
    },
    var.environment != "prod" ? {
      non_production_restrictions = aws_organizations_policy.non_production_restrictions[0].arn
    } : {}
  )
}
