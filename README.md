# AWS IAC Organizations - Generalized Multi-Environment AWS Organizations Management

A reusable, importable Infrastructure as Code solution for managing AWS Organizations with multi-environment deployment support, including localstack for development and testing.

## Features

- **Multi-Environment Support**: Deploy to dev, qa, and prod environments
- **LocalStack Compatible**: Full support for localstack development/testing
- **Flexible Configuration**: YAML-based configuration for accounts, OUs, and policies  
- **Multiple Credential Providers**: AWS SSO profiles locally, GitHub environment variables for CI/CD
- **Modular Design**: Reusable Terraform modules for common patterns
- **Security Baseline**: Built-in SCPs and security best practices
- **Multi-Tenancy**: Support for different organization structures

## Quick Start

1. **Clone and Configure**
   ```bash
   git clone <repository-url>
   cd aws-iac-organizations
   cp config/organizations/example.yaml config/organizations/my-org.yaml
   # Edit my-org.yaml with your organization structure
   ```

2. **Deploy to Development (LocalStack)**
   ```bash
   make deploy ENV=dev TARGET=localstack ORG_CONFIG=my-org
   ```

3. **Deploy to Production (AWS)**
   ```bash  
   make deploy ENV=prod TARGET=aws ORG_CONFIG=my-org AWS_PROFILE=my-prod-profile
   ```

## Configuration Schema

Organizations are defined in YAML configuration files under `config/organizations/`:

```yaml
# config/organizations/my-org.yaml
metadata:
  name: "my-organization"
  description: "My Company AWS Organization"
  
environments:
  dev:
    target: localstack
    endpoint: http://localhost:4566
    region: us-east-1
  qa: 
    target: aws
    profile: my-qa-profile
    region: us-west-2
  prod:
    target: aws  
    profile: my-prod-profile
    region: us-west-2

organization:
  feature_set: ALL
  default_region: us-west-2
  allowed_regions: [us-west-2, us-east-1]
  service_access_principals:
    - sso.amazonaws.com
    - cloudtrail.amazonaws.com
    - guardduty.amazonaws.com
    - securityhub.amazonaws.com

organizational_units:
  - name: Security
    description: Security and compliance accounts
  - name: SharedServices  
    description: Shared infrastructure and services
  - name: Businesses
    description: Business workload accounts
  - name: Sandbox
    description: Development and experimentation

accounts:
  - name: security-tooling
    email: security@mycompany.com
    ou: Security
    description: Security tooling and monitoring
    
  - name: log-archive
    email: logs@mycompany.com  
    ou: Security
    description: Centralized log archive
    
  - name: shared-services
    email: shared@mycompany.com
    ou: SharedServices
    description: Shared DNS, networking, CI/CD
    
  - name: production
    email: prod@mycompany.com
    ou: Businesses
    description: Production workloads
    
  - name: development
    email: dev@mycompany.com
    ou: Sandbox
    description: Development environment

policies:
  tag_policies:
    - name: StandardTags
      required_tags: [Environment, BusinessUnit, Owner, CostCenter]
      
  service_control_policies:
    - baseline_security
    - region_restrictions
    - prevent_org_changes

sso:
  permission_sets:
    - name: PowerUser
      managed_policies: [arn:aws:iam::aws:policy/PowerUserAccess]
      session_duration: PT12H
    - name: ReadOnly
      managed_policies: [arn:aws:iam::aws:policy/ReadOnlyAccess] 
      session_duration: PT8H

github_actions:
  enabled: true
  repos: [my-org/infrastructure, my-org/applications]
```

## Directory Structure

```
aws-iac-organizations/
├── config/
│   ├── organizations/           # Organization configuration files
│   │   ├── example.yaml        # Example configuration
│   │   └── schemas/            # JSON schemas for validation
│   └── environments/           # Environment-specific overrides
│       ├── dev.yaml
│       ├── qa.yaml  
│       └── prod.yaml
├── modules/                    # Reusable Terraform modules
│   ├── organization/           # Core organization setup
│   ├── organizational-unit/    # OU management
│   ├── account/               # Account creation and management
│   ├── scp-baseline/          # Service Control Policies
│   ├── sso-permission-set/    # SSO permission sets
│   ├── tag-policy/            # Tag policy management
│   └── github-oidc/           # GitHub Actions OIDC setup
├── environments/              # Environment-specific deployments
│   ├── dev/                   # Development environment
│   ├── qa/                    # QA environment
│   └── prod/                  # Production environment
├── scripts/                   # Automation and utility scripts
│   ├── deploy.sh              # Main deployment script
│   ├── validate-config.py     # Configuration validation
│   └── localstack-setup.sh    # LocalStack initialization
├── tests/                     # Testing framework
│   ├── integration/           # Integration tests
│   └── unit/                  # Unit tests
└── docs/                      # Documentation
    ├── configuration.md       # Configuration guide
    ├── deployment.md          # Deployment guide
    └── troubleshooting.md     # Troubleshooting guide
```

## Environment Support

### Development (LocalStack)
- Perfect for local development and testing
- No AWS costs
- Full AWS Organizations API support
- Fast iteration cycles

### QA Environment  
- Deploy to real AWS for integration testing
- Use separate AWS account/organization
- Automated testing pipeline

### Production Environment
- Production AWS organization
- Enhanced security and monitoring
- Multi-region support

## Credential Management

### Local Development
- AWS SSO profiles configured in `~/.aws/config`
- Profile specified in organization config or command line
- LocalStack uses default credentials (or none)

### GitHub Actions CI/CD
Environment variables for each environment:
```yaml
# GitHub Secrets
AWS_ROLE_ARN_DEV: arn:aws:iam::DEV-ACCOUNT:role/GitHubActions
AWS_ROLE_ARN_QA: arn:aws:iam::QA-ACCOUNT:role/GitHubActions  
AWS_ROLE_ARN_PROD: arn:aws:iam::PROD-ACCOUNT:role/GitHubActions
```

## Usage Examples

### Deploy Specific Organization Config
```bash
make deploy ENV=prod ORG_CONFIG=petunka-holdings
make deploy ENV=dev ORG_CONFIG=personal-accounts
```

### Validate Configuration
```bash
make validate ORG_CONFIG=my-org
```

### Plan Changes
```bash
make plan ENV=qa ORG_CONFIG=my-org
```

### Import Existing Resources  
```bash
make import ENV=prod ORG_CONFIG=my-org RESOURCE_TYPE=account RESOURCE_ID=123456789012
```

## Contributing

1. Add your organization configuration under `config/organizations/`
2. Test with localstack: `make test ENV=dev ORG_CONFIG=your-org`  
3. Validate configuration: `make validate ORG_CONFIG=your-org`
4. Submit PR with configuration and any new modules needed

## LocalStack Development

The project includes full LocalStack support for development:

1. **Start LocalStack**
   ```bash
   make localstack-start
   ```

2. **Deploy to LocalStack**
   ```bash
   make deploy ENV=dev TARGET=localstack ORG_CONFIG=example
   ```

3. **Inspect Resources**
   ```bash
   make localstack-inspect
   ```

## License

MIT License - see LICENSE file for details.
