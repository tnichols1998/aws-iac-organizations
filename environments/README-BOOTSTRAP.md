# Bootstrap Environments

This project manages **two separate AWS Organizations** and therefore requires separate bootstrap environments to avoid state conflicts.

## Directory Structure

```
environments/
├── bootstrap/          # Legacy - contains mixed state (avoid using)
├── bootstrap-qa/       # QA Organization Bootstrap
├── bootstrap-prod/     # Production Organization Bootstrap
├── dev/               # Development environment (uses LocalStack)  
├── qa/                # QA environment (uses QA organization)
└── prod/              # Production environment (uses Production organization)
```

## AWS Organizations

### QA Organization
- **Management Account**: `737339127994` (`aws.sandbox@petunkaholdings.com`)
- **Profile**: `petunka-sandbox-mgmt-admin`
- **Bootstrap Directory**: `bootstrap-qa/`

### Production Organization  
- **Management Account**: `825200688391` (production management account)
- **Profile**: `petunka-prod-admin` (or similar)
- **Bootstrap Directory**: `bootstrap-prod/`

## Bootstrap Phase Commands

### For QA Organization
```bash
# Navigate to QA bootstrap
cd environments/bootstrap-qa

# Set the correct AWS profile
export AWS_PROFILE=petunka-sandbox-mgmt-admin

# Initialize and apply bootstrap
tofu init
tofu plan
tofu apply
```

### For Production Organization  
```bash
# Navigate to Production bootstrap
cd environments/bootstrap-prod

# Set the correct AWS profile
export AWS_PROFILE=petunka-prod-admin

# Initialize and apply bootstrap
tofu init  
tofu plan
tofu apply
```

## What Bootstrap Creates

Each bootstrap environment creates:
- GitHub OIDC Provider for GitHub Actions
- IAM Role for GitHub Actions with comprehensive AWS Organizations permissions
- Outputs file for GitHub Actions workflows

## State Management

- **QA Bootstrap**: Uses local state in `bootstrap-qa/terraform.tfstate`
- **Production Bootstrap**: Uses local state in `bootstrap-prod/terraform.tfstate`
- **Legacy Bootstrap**: Contains mixed state and should be avoided

## Important Notes

1. **Never run bootstrap commands in the wrong organization** - always verify your AWS profile and account ID first
2. **Each organization's bootstrap is independent** - they do not share resources
3. **Use the correct profile** for each organization before running any commands
4. **The original `bootstrap/` directory** contains mixed state and should not be used

## Verification Commands

Before running bootstrap commands, always verify you're in the correct organization:

```bash
# Check current identity and account
aws sts get-caller-identity

# Verify organization (should show the management account as master)
aws organizations describe-organization
```
