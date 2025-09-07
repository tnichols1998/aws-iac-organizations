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
  sso_config = lookup(var.organization_config, "sso", {})
  permission_sets = lookup(local.sso_config, "permission_sets", [])
  group_assignments = lookup(local.sso_config, "group_assignments", [])
}

# Get SSO Instance
data "aws_ssoadmin_instances" "this" {}

# Create Permission Sets
resource "aws_ssoadmin_permission_set" "this" {
  for_each = {
    for ps in local.permission_sets : ps.name => ps
  }

  name             = each.value.name
  description      = lookup(each.value, "description", "")
  instance_arn     = length(data.aws_ssoadmin_instances.this.arns) > 0 ? tolist(data.aws_ssoadmin_instances.this.arns)[0] : "arn:aws:sso:::instance/ssoins-668462304bce6bb7"
  session_duration = lookup(each.value, "session_duration", "PT8H")

  tags = {
    Name        = each.value.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Attach AWS Managed Policies to Permission Sets
resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = {
    for item in flatten([
      for ps_name, ps in {
        for ps in local.permission_sets : ps.name => ps
      } : [
        for policy in lookup(ps, "managed_policies", []) : {
          permission_set_name = ps_name
          policy_arn         = policy
          key               = "${ps_name}-${replace(policy, ":", "-")}"
        }
      ]
    ]) : item.key => item
  }

  instance_arn       = length(data.aws_ssoadmin_instances.this.arns) > 0 ? tolist(data.aws_ssoadmin_instances.this.arns)[0] : "arn:aws:sso:::instance/ssoins-668462304bce6bb7"
  managed_policy_arn = each.value.policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set_name].arn
}

# Account Assignments (commented out for now - requires manual group creation in Identity Center)
# resource "aws_ssoadmin_account_assignment" "this" {
#   for_each = {
#     for item in flatten([
#       for assignment in local.group_assignments : [
#         for account in assignment.accounts : {
#           group_name          = assignment.group_name
#           permission_set_name = assignment.permission_set
#           account_name        = account
#           key                = "${assignment.group_name}-${assignment.permission_set}-${account}"
#         }
#       ]
#     ]) : item.key => item
#   }
# 
#   instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
#   permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set_name].arn
#   principal_id       = data.aws_identitystore_group.groups[each.value.group_name].group_id
#   principal_type     = "GROUP"
#   target_id          = var.account_ids[each.value.account_name]
#   target_type        = "AWS_ACCOUNT"
# }

# Outputs
output "permission_set_arns" {
  description = "Map of permission set names to their ARNs"
  value = {
    for name, ps in aws_ssoadmin_permission_set.this : name => ps.arn
  }
}

output "sso_instance_arn" {
  description = "SSO Instance ARN"
  value = length(data.aws_ssoadmin_instances.this.arns) > 0 ? tolist(data.aws_ssoadmin_instances.this.arns)[0] : null
}
