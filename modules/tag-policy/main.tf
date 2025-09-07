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
  policies     = lookup(var.organization_config, "policies", {})
  tag_policies = lookup(local.policies, "tag_policies", [])

  # Default tag policy configuration
  default_tags = {
    Environment = {
      tag_value = {
        "@@assign" = ["dev", "staging", "qa", "prod", "sandbox"]
      }
    }
    ManagedBy = {
      tag_value = {
        "@@assign" = ["terraform", "manual", "cloudformation"]
      }
    }
    Owner = {
      tag_value = {
        "@@assign" = "*"
      }
    }
  }
}

# Create tag policies from configuration
resource "aws_organizations_policy" "tag_policies" {
  for_each = {
    for policy in local.tag_policies : policy.name => policy
  }

  name        = each.value.name
  description = lookup(each.value, "description", "Tag policy for ${each.value.name}")
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = merge(
      local.default_tags,
      {
        for tag in lookup(each.value, "required_tags", []) : tag => {
          tag_value = {
            "@@assign" = lookup(
              lookup(each.value, "tag_values", {}),
              tag,
              "*"
            )
          }
        }
      }
    )
  })

  tags = {
    Name        = each.value.name
    Environment = var.environment
    ManagedBy   = "terraform"
    PolicyType  = "TagPolicy"
  }
}

# Attach tag policies to the organization root
resource "aws_organizations_policy_attachment" "tag_policies" {
  for_each = {
    for policy in local.tag_policies : policy.name => policy
  }

  policy_id = aws_organizations_policy.tag_policies[each.key].id
  target_id = var.organization_root_id
}

# Create a default organization-wide tag policy if none specified
resource "aws_organizations_policy" "default_tag_policy" {
  count = length(local.tag_policies) == 0 ? 1 : 0

  name        = "${var.organization_config.metadata.name}-standard-tags"
  description = "Standard tagging policy for ${var.organization_config.metadata.name}"
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = merge(
      local.default_tags,
      {
        # Add organization-specific tags
        Organization = {
          tag_value = {
            "@@assign" = [var.organization_config.metadata.name]
          }
        }
      }
    )
  })

  tags = {
    Name        = "${var.organization_config.metadata.name}-standard-tags"
    Environment = var.environment
    ManagedBy   = "terraform"
    PolicyType  = "TagPolicy"
  }
}

resource "aws_organizations_policy_attachment" "default_tag_policy" {
  count = length(local.tag_policies) == 0 ? 1 : 0

  policy_id = aws_organizations_policy.default_tag_policy[0].id
  target_id = var.organization_root_id
}

# Outputs
output "tag_policy_ids" {
  description = "Map of tag policy names to their IDs"
  value = merge(
    {
      for name, policy in aws_organizations_policy.tag_policies : name => policy.id
    },
    length(local.tag_policies) == 0 ? {
      default = aws_organizations_policy.default_tag_policy[0].id
    } : {}
  )
}

output "tag_policy_arns" {
  description = "Map of tag policy names to their ARNs"
  value = merge(
    {
      for name, policy in aws_organizations_policy.tag_policies : name => policy.arn
    },
    length(local.tag_policies) == 0 ? {
      default = aws_organizations_policy.default_tag_policy[0].arn
    } : {}
  )
}
