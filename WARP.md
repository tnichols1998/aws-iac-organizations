# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a generalized, reusable Infrastructure as Code solution for managing AWS Organizations with multi-environment deployment support, including LocalStack for development and testing. The project creates and manages AWS Organizations, Organizational Units, member accounts, Service Control Policies, and tag policies using Terraform.

## Two-Phase Deployment

This project uses a **two-phase deployment approach** for enhanced security:

### Phase 1: Bootstrap (Root Account Only)
```bash
# Navigate to bootstrap environment
cd environments/bootstrap

# Initialize and apply bootstrap (creates OIDC + IAM roles)
tofu init
tofu plan
tofu apply
```

### Phase 2: Main Infrastructure (GitHub Actions or OIDC)
```bash
# Using GitHub Actions or OIDC-assumed role
cd environments/qa
export TF_VAR_organization_config="../../config/organizations/petunka-holdings.yaml"
export TF_VAR_environment="qa"
tofu plan
tofu apply
```

See `BOOTSTRAP.md` for detailed setup instructions.

## Common Commands

### Development with LocalStack
```bash
# Start LocalStack for local development
make localstack-start

# Deploy to LocalStack (cost-free development)
make deploy ENV=dev TARGET=localstack ORG_CONFIG=example

# Inspect LocalStack resources
make localstack-inspect

# Stop LocalStack
make localstack-stop
```

### Configuration Management
```bash
# Validate organization configuration
make validate ORG_CONFIG=my-org

# List available organization configurations
make list-configs

# Copy example config to create new one
make copy-config NEW_CONFIG=my-org

# Generate terraform vars from YAML config
make generate-tfvars ORG_CONFIG=my-org
```

### Multi-Environment Deployment
```bash
# Plan deployment changes
make plan ENV=prod ORG_CONFIG=my-org AWS_PROFILE=my-profile

# Deploy to AWS
make deploy ENV=prod TARGET=aws ORG_CONFIG=my-org AWS_PROFILE=my-profile

# Deploy different organization configs
make deploy ENV=prod ORG_CONFIG=petunka-holdings AWS_PROFILE=petunka-admin
make deploy ENV=dev ORG_CONFIG=personal-accounts TARGET=localstack
```

### Testing and Validation
```bash
# Run configuration validation
python scripts/validate-config.py config/organizations/my-org.yaml

# Run tests
make test ORG_CONFIG=my-org ENV=dev

# Setup development environment
make setup-dev
```

### Resource Management
```bash
# Import existing AWS resources
make import ENV=prod ORG_CONFIG=my-org RESOURCE_TYPE=account RESOURCE_ID=123456789012

# Clean terraform cache
make clean ENV=dev

# Destroy infrastructure (with confirmation)
make destroy ENV=dev
```

## Architecture

### Multi-Environment Support
- **Development (LocalStack)**: Cost-free local development using LocalStack with full AWS Organizations API support
- **QA Environment**: Real AWS deployment for integration testing
- **Production Environment**: Production-ready AWS organization deployment

### Configuration-Driven Design
The project uses YAML configuration files in `config/organizations/` to define:
- Organization metadata and settings
- Environment-specific deployment targets (AWS vs LocalStack)
- Organizational Units structure
- Member accounts with email assignments
- Service Control Policies and tag policies
- SSO permission sets and group assignments
- GitHub Actions OIDC configuration

### Terraform Module Architecture
- **`modules/organization/`**: Core organization setup, creates AWS Organizations, OUs, and member accounts
- **`modules/scp-baseline/`**: Service Control Policies for security baseline (region restrictions, prevent org changes, etc.)
- **`modules/tag-policy/`**: Tag policy management for consistent resource tagging
- **`environments/dev/`**: Environment-specific Terraform configurations with dynamic provider setup

### Key Design Patterns
- **Environment-aware provider configuration**: Automatically configures AWS provider for LocalStack vs real AWS
- **YAML-to-Terraform bridge**: Configuration loaded as YAML, parsed and passed to Terraform modules
- **Multi-tenancy support**: Single codebase supports multiple organization configurations
- **Safety mechanisms**: Prevent accidental account deletion, confirmation prompts for destructive operations

## Development Workflow

### Local Development Process
1. Start LocalStack: `make localstack-start`
2. Create/modify organization config in `config/organizations/`
3. Validate configuration: `make validate ORG_CONFIG=your-config`
4. Deploy to LocalStack: `make deploy ENV=dev TARGET=localstack ORG_CONFIG=your-config`
5. Test and iterate rapidly with zero AWS costs

### Configuration Structure
Organization configs follow a standard schema with sections for:
- `metadata`: Organization name and description
- `environments`: Environment-specific settings (target, region, profile)
- `organization`: Core AWS Organizations settings (feature_set, regions, service principals)
- `organizational_units`: OU structure and descriptions
- `accounts`: Member accounts with email addresses and OU assignments
- `policies`: Service Control Policies and tag policies
- `sso`: Identity Center permission sets and group assignments (optional)
- `github_actions`: OIDC configuration for CI/CD (optional)

### Environment Variables and Credentials
- **LocalStack**: Uses test credentials automatically
- **AWS Environments**: Uses AWS profiles specified in organization config
- **GitHub Actions**: Uses IAM roles with OIDC provider for each environment

### Validation and Safety
- Configuration validation script prevents deployment of invalid configs
- Built-in safety mechanisms prevent accidental organization changes
- Terraform lifecycle rules prevent accidental account deletion
- Environment-specific SCPs provide guardrails

## Important Files and Directories

- `config/organizations/*.yaml`: Organization configuration files (example.yaml, petunka-holdings.yaml, personal-accounts.yaml)
- `Makefile`: Main automation interface with all deployment commands
- `scripts/validate-config.py`: Python-based configuration validation
- `scripts/localstack-setup.sh`: LocalStack management script
- `modules/`: Reusable Terraform modules for organization components
- `environments/`: Environment-specific Terraform configurations
- `requirements-dev.txt`: Python dependencies for validation scripts

## Security Considerations

When working with this codebase:
- Never commit AWS credentials or real organization identifiers
- Use LocalStack for all development and testing
- Validate configurations before deployment to prevent organization disruption
- Be extremely cautious with destroy operations in production
- Review Service Control Policies before applying to ensure they don't lock out users

## LocalStack Integration

This project has extensive LocalStack support for development. LocalStack provides:
- Full AWS Organizations API simulation
- No AWS costs during development
- Fast iteration cycles
- Safe testing of organization changes
- Consistent behavior with real AWS Organizations API

The LocalStack integration includes automatic endpoint configuration, test credentials, and specialized provider settings for seamless local development.
