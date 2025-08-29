terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Variables for organization configuration
variable "organization_config" {
  description = "Full organization configuration from YAML"
  type        = any
}

variable "environment" {
  description = "Current deployment environment"
  type        = string
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL for development"
  type        = string
  default     = ""
}

# Local processing of configuration
locals {
  org_config = var.organization_config.organization
  accounts   = var.organization_config.accounts
  ous        = var.organization_config.organizational_units
  
  # Environment-specific settings
  env_config = var.organization_config.environments[var.environment]
  
  # Dynamic provider configuration for LocalStack vs AWS
  is_localstack = local.env_config.target == "localstack"
}

# Provider configuration based on environment
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
      configuration_aliases = [aws.organizations]
    }
  }
}

# Main AWS Organizations setup
resource "aws_organizations_organization" "this" {
  feature_set = local.org_config.feature_set
  
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY"
  ]
  
  aws_service_access_principals = local.org_config.service_access_principals
  
  tags = {
    Name        = var.organization_config.metadata.name
    Description = var.organization_config.metadata.description
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Create Organizational Units dynamically
resource "aws_organizations_organizational_unit" "ous" {
  for_each = {
    for ou in local.ous : ou.name => ou
  }
  
  name      = each.value.name
  parent_id = aws_organizations_organization.this.roots[0].id
  
  tags = {
    Name        = each.value.name
    Description = lookup(each.value, "description", "")
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Create a mapping of OU names to IDs
locals {
  ou_id_map = {
    for ou_name, ou_resource in aws_organizations_organizational_unit.ous :
    ou_name => ou_resource.id
  }
}

# Create member accounts
resource "aws_organizations_account" "members" {
  for_each = {
    for account in local.accounts : account.name => account
  }
  
  name  = each.value.name
  email = each.value.email
  
  # Place account in specified OU or root
  parent_id = lookup(each.value, "ou", null) != null ? local.ou_id_map[each.value.ou] : aws_organizations_organization.this.roots[0].id
  
  # Prevent account closure on destroy for safety
  close_on_deletion = false
  
  tags = {
    Name        = each.value.name
    Description = lookup(each.value, "description", "")
    Environment = var.environment
    OU          = lookup(each.value, "ou", "Root")
    ManagedBy   = "terraform"
  }
  
  lifecycle {
    # Prevent accidental account deletion
    prevent_destroy = true
  }
}

# Service Control Policies
module "scp_baseline" {
  source = "../scp-baseline"
  
  organization_root_id = aws_organizations_organization.this.roots[0].id
  organization_config  = var.organization_config
  environment         = var.environment
  
  depends_on = [aws_organizations_organization.this]
}

# Tag Policies
module "tag_policies" {
  source = "../tag-policy"
  
  organization_root_id = aws_organizations_organization.this.roots[0].id
  organization_config  = var.organization_config
  environment         = var.environment
  
  depends_on = [aws_organizations_organization.this]
}

# Outputs
output "organization_id" {
  description = "The organization ID"
  value       = aws_organizations_organization.this.id
}

output "organization_arn" {
  description = "The organization ARN"
  value       = aws_organizations_organization.this.arn
}

output "organization_root_id" {
  description = "The organization root ID"
  value       = aws_organizations_organization.this.roots[0].id
}

output "organizational_unit_ids" {
  description = "Map of OU names to their IDs"
  value       = local.ou_id_map
}

output "account_ids" {
  description = "Map of account names to their IDs"
  value = {
    for account_name, account_resource in aws_organizations_account.members :
    account_name => account_resource.id
  }
}

output "account_arns" {
  description = "Map of account names to their ARNs"
  value = {
    for account_name, account_resource in aws_organizations_account.members :
    account_name => account_resource.arn
  }
}

# Output useful information for other modules
output "management_account_id" {
  description = "The management account ID"
  value       = aws_organizations_organization.this.master_account_id
}

output "all_account_ids" {
  description = "List of all account IDs including management account"
  value = concat(
    [aws_organizations_organization.this.master_account_id],
    values({
      for account_name, account_resource in aws_organizations_account.members :
      account_name => account_resource.id
    })
  )
}

# Security-specific outputs for downstream modules
output "security_account_ids" {
  description = "List of security account IDs"
  value = [
    for account_name, account_resource in aws_organizations_account.members :
    account_resource.id
    if try(local.accounts[index(local.accounts.*.name, account_name)].ou, "") == "Security"
  ]
}

output "business_account_ids" {
  description = "List of business account IDs"
  value = [
    for account_name, account_resource in aws_organizations_account.members :
    account_resource.id
    if try(local.accounts[index(local.accounts.*.name, account_name)].ou, "") == "Businesses"
  ]
}
