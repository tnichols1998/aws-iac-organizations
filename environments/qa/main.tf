terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Variables that will be set via environment variables or command line
variable "organization_config" {
  description = "Path to organization configuration YAML file"
  type        = string
}

variable "environment" {
  description = "Current deployment environment"
  type        = string
  default     = "dev"
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL for development"
  type        = string
  default     = "http://localhost:4566"
}

# Load and parse the organization configuration
locals {
  org_config_raw = file(var.organization_config)
  org_config     = yamldecode(local.org_config_raw)
  env_config     = local.org_config.environments[var.environment]

  # Determine if we're using LocalStack
  is_localstack = local.env_config.target == "localstack"
}

# Provider configuration - dynamically configured for LocalStack or AWS
provider "aws" {
  region = local.env_config.region

  # LocalStack configuration
  dynamic "endpoints" {
    for_each = local.is_localstack ? [1] : []
    content {
      organizations = var.localstack_endpoint
      iam           = var.localstack_endpoint
      s3            = var.localstack_endpoint
      cloudtrail    = var.localstack_endpoint
      guardduty     = var.localstack_endpoint
      securityhub   = var.localstack_endpoint
      config        = var.localstack_endpoint
      sts           = var.localstack_endpoint
    }
  }

  # Skip various checks for LocalStack
  skip_credentials_validation = local.is_localstack
  skip_metadata_api_check     = local.is_localstack
  skip_requesting_account_id  = local.is_localstack

  # Use profile if specified and not using LocalStack
  # Temporarily disabled for GitHub Actions OIDC - will use environment credentials automatically
  # profile = !local.is_localstack && lookup(local.env_config, "profile", null) != null ? local.env_config.profile : null
  profile = null

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "aws-iac-organizations"
      Target      = local.env_config.target
    }
  }
}

# Separate provider for SSO operations - uses same region as main provider
provider "aws" {
  alias  = "sso"
  region = local.env_config.region

  # LocalStack configuration for SSO
  dynamic "endpoints" {
    for_each = local.is_localstack ? [1] : []
    content {
      ssoadmin      = var.localstack_endpoint
      identitystore = var.localstack_endpoint
      sts           = var.localstack_endpoint
    }
  }

  # Skip various checks for LocalStack
  skip_credentials_validation = local.is_localstack
  skip_metadata_api_check     = local.is_localstack
  skip_requesting_account_id  = local.is_localstack

  # Use same credentials as main provider
  profile = null

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "aws-iac-organizations"
      Target      = local.env_config.target
    }
  }
}

# Terraform backend configuration for state management
terraform {
  backend "s3" {
    # Backend configuration will be provided via -backend-config flag
    # See backend-qa.conf for actual configuration
  }
}

# Main organization module
module "organization" {
  source = "../../modules/organization"

  organization_config = local.org_config
  environment         = var.environment
  localstack_endpoint = local.is_localstack ? var.localstack_endpoint : ""
}

# Optional: SSO configuration (if enabled and not LocalStack)
module "sso" {
  count = lookup(local.org_config, "sso", {}).enabled == true && !local.is_localstack ? 1 : 0

  source = "../../modules/sso-permission-set"

  providers = {
    aws.sso = aws.sso
  }

  organization_config = local.org_config
  environment         = var.environment
  account_ids         = module.organization.account_ids

  depends_on = [module.organization]
}

# Note: GitHub OIDC setup is now handled in the bootstrap phase
# See environments/bootstrap/ for OIDC provider and IAM role creation
# This ensures proper separation between root-only bootstrap and CI/CD-managed infrastructure

# Outputs
output "organization_id" {
  description = "The organization ID"
  value       = module.organization.organization_id
}

output "organization_arn" {
  description = "The organization ARN"
  value       = module.organization.organization_arn
}

output "account_ids" {
  description = "Map of account names to their IDs"
  value       = module.organization.account_ids
}

output "organizational_unit_ids" {
  description = "Map of OU names to their IDs"
  value       = module.organization.organizational_unit_ids
}

output "management_account_id" {
  description = "The management account ID"
  value       = module.organization.management_account_id
}

# Development-specific outputs
output "localstack_info" {
  description = "LocalStack deployment information"
  value = local.is_localstack ? {
    endpoint = var.localstack_endpoint
    region   = local.env_config.region
    message  = "Development environment using LocalStack"
  } : null
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    environment    = var.environment
    target         = local.env_config.target
    region         = local.env_config.region
    organization   = local.org_config.metadata.name
    accounts_count = length(local.org_config.accounts)
    ous_count      = length(local.org_config.organizational_units)
  }
}
