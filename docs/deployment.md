# Deployment Guide

This guide provides step-by-step instructions for deploying AWS Organizations using the generalized aws-iac-organizations framework.

## Prerequisites

### Required Tools

1. **Terraform/OpenTofu** (>= 1.6.0)
   ```bash
   # Install OpenTofu (recommended)
   brew install opentofu
   
   # Or install Terraform
   brew install terraform
   ```

2. **AWS CLI** (>= 2.0)
   ```bash
   brew install awscli
   ```

3. **Python** (>= 3.8)
   ```bash
   python3 --version
   pip install -r requirements-dev.txt
   ```

4. **Docker** (for LocalStack development)
   - Install Docker Desktop

### AWS Prerequisites

1. **AWS Account Access**: Administrative access to your AWS root account
2. **Email Addresses**: Unique email addresses for each sub-account
3. **AWS SSO Setup** (optional but recommended): IAM Identity Center configured
4. **Billing Understanding**: Account creation may incur costs

## Configuration Setup

### 1. Create Your Organization Configuration

```bash
# Copy example configuration
make copy-config NEW_CONFIG=my-org

# Edit the configuration
vim config/organizations/my-org.yaml
```

### 2. Validate Configuration

```bash
# Validate your configuration
make validate ORG_CONFIG=my-org

# Check for warnings and errors
python scripts/validate-config.py config/organizations/my-org.yaml --strict
```

## Development Deployment (LocalStack)

Perfect for testing and development without AWS costs.

### 1. Start LocalStack

```bash
# Start LocalStack
make localstack-start

# Verify it's running
make localstack-inspect
```

### 2. Deploy to LocalStack

```bash
# Deploy your organization to LocalStack
make deploy ENV=dev TARGET=localstack ORG_CONFIG=my-org

# Inspect the deployed resources
make localstack-inspect
```

### 3. Test Changes

```bash
# Make changes to your configuration
vim config/organizations/my-org.yaml

# Plan the changes
make plan ENV=dev TARGET=localstack ORG_CONFIG=my-org

# Apply the changes
make deploy ENV=dev TARGET=localstack ORG_CONFIG=my-org
```

## QA Environment Deployment

Deploy to a real AWS environment for integration testing.

### 1. Configure AWS Profile

```bash
# Configure AWS SSO profile for QA
aws configure sso --profile my-org-qa-admin

# Test access
aws sts get-caller-identity --profile my-org-qa-admin
```

### 2. Update Configuration

```yaml
# In config/organizations/my-org.yaml
environments:
  qa:
    target: aws
    profile: my-org-qa-admin
    region: us-west-2
```

### 3. Deploy to QA

```bash
# Deploy to QA environment
make deploy ENV=qa ORG_CONFIG=my-org AWS_PROFILE=my-org-qa-admin

# Verify deployment
aws organizations describe-organization --profile my-org-qa-admin
```

## Production Deployment

Deploy to your production AWS organization.

### 1. Configure Production Profile

```bash
# Configure AWS SSO profile for production
aws configure sso --profile my-org-prod-admin

# Verify access
aws sts get-caller-identity --profile my-org-prod-admin
```

### 2. Production Configuration

```yaml
# In config/organizations/my-org.yaml
environments:
  prod:
    target: aws
    profile: my-org-prod-admin
    region: us-west-2
```

### 3. Deploy to Production

```bash
# First, plan the deployment
make plan ENV=prod ORG_CONFIG=my-org AWS_PROFILE=my-org-prod-admin

# Review the plan carefully, then deploy
make deploy ENV=prod ORG_CONFIG=my-org AWS_PROFILE=my-org-prod-admin
```

## Multi-Organization Deployment

Deploy multiple organization configurations.

### Example: Deploying Both Petunka Holdings and Personal Accounts

```bash
# Deploy Petunka Holdings to production
make deploy ENV=prod ORG_CONFIG=petunka-holdings AWS_PROFILE=petunka-prod-admin

# Deploy Personal Accounts to a different organization
make deploy ENV=prod ORG_CONFIG=personal-accounts AWS_PROFILE=personal-prod-admin
```

## GitHub Actions CI/CD

Set up automated deployment with GitHub Actions.

### 1. Create IAM Roles for GitHub Actions

For each environment (dev, qa, prod), create an IAM role that GitHub Actions can assume:

```bash
# Example for development environment
aws iam create-role \
  --role-name GitHubActions-aws-iac-organizations-dev \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::ACCOUNT-ID:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
            "token.actions.githubusercontent.com:sub": "repo:YOUR-ORG/aws-iac-organizations:ref:refs/heads/main"
          }
        }
      }
    ]
  }' \
  --profile my-org-dev-admin
```

### 2. Configure GitHub Secrets

Add these secrets to your GitHub repository:

- `AWS_ROLE_ARN_DEV`: `arn:aws:iam::DEV-ACCOUNT:role/GitHubActions-aws-iac-organizations-dev`
- `AWS_ROLE_ARN_QA`: `arn:aws:iam::QA-ACCOUNT:role/GitHubActions-aws-iac-organizations-qa`
- `AWS_ROLE_ARN_PROD`: `arn:aws:iam::PROD-ACCOUNT:role/GitHubActions-aws-iac-organizations-prod`

### 3. Push to Deploy

```bash
# Push to main branch to trigger deployment
git add .
git commit -m "Deploy organization configuration"
git push origin main
```

## Troubleshooting

### Common Issues

#### 1. Account Creation Limits

**Error**: "You have reached the maximum number of accounts"

**Solution**: AWS has limits on account creation. Contact AWS Support to request limit increases.

#### 2. Email Already in Use

**Error**: "The email address is already associated with an account"

**Solution**: Use unique email addresses for each account. Consider using email aliases (e.g., `admin+dev@example.com`).

#### 3. Organization Service Access

**Error**: "Service access is not enabled"

**Solution**: Enable service access for required services:

```bash
aws organizations enable-aws-service-access --service-principal sso.amazonaws.com
aws organizations enable-aws-service-access --service-principal cloudtrail.amazonaws.com
```

#### 4. Permission Denied

**Error**: "User is not authorized to perform organizations:CreateOrganization"

**Solution**: Ensure you're using the management account with appropriate permissions.

### LocalStack Issues

#### 1. LocalStack Not Starting

```bash
# Check Docker is running
docker info

# Check LocalStack logs
make localstack-logs

# Reset LocalStack
make localstack-reset
```

#### 2. Services Not Available

```bash
# Check LocalStack health
curl http://localhost:4566/health

# Restart with more services
# Edit scripts/localstack-setup.sh to add more services
```

### Terraform State Issues

#### 1. State Lock

**Error**: "Error acquiring the state lock"

**Solution**: 
```bash
# Force unlock (use carefully)
cd environments/prod
terraform force-unlock LOCK_ID
```

#### 2. State Drift

```bash
# Import existing resources
make import ENV=prod RESOURCE_TYPE=aws_organizations_account.members RESOURCE_ID=123456789012
```

## Monitoring and Maintenance

### Regular Tasks

1. **Review Organization Structure**
   ```bash
   # List all accounts
   aws organizations list-accounts --profile my-org-prod-admin
   
   # Review organizational units
   aws organizations list-organizational-units-for-parent \
     --parent-id r-xxxx --profile my-org-prod-admin
   ```

2. **Update Configurations**
   ```bash
   # Validate before applying
   make validate ORG_CONFIG=my-org
   
   # Plan changes
   make plan ENV=prod ORG_CONFIG=my-org
   ```

3. **Monitor Costs**
   - Set up AWS Budgets
   - Review Cost Explorer regularly
   - Monitor account-level costs

### Backup and Recovery

1. **Configuration Backup**
   ```bash
   # Version control is your backup
   git add config/
   git commit -m "Backup organization configuration"
   git push
   ```

2. **State Backup**
   - Terraform state is stored in S3 (configured in backend)
   - Enable versioning on state bucket
   - Set up cross-region replication

## Advanced Topics

### Custom Modules

Create custom modules for specific needs:

```hcl
# modules/custom-security/main.tf
module "custom_scp" {
  source = "../scp-baseline"
  # Custom configuration
}
```

### Multiple Regions

Configure multi-region deployments:

```yaml
# config/organizations/my-org.yaml
organization:
  allowed_regions: [us-west-2, us-east-1, eu-west-1]
  
environments:
  prod-us:
    target: aws
    profile: my-org-prod-admin
    region: us-west-2
    
  prod-eu:
    target: aws
    profile: my-org-prod-admin
    region: eu-west-1
```

### Integration with Control Tower

```yaml
# For organizations using AWS Control Tower
organization:
  feature_set: ALL
  service_access_principals:
    - controltower.amazonaws.com
    - sso.amazonaws.com
```

## Security Best Practices

1. **Principle of Least Privilege**: Use minimal required permissions
2. **MFA Required**: Enable MFA for all administrative access
3. **Audit Logging**: Ensure CloudTrail is enabled
4. **Regular Reviews**: Review permissions and access quarterly
5. **Automation**: Use IaC and avoid manual changes

## Support

For issues and questions:

1. Check the [Troubleshooting section](#troubleshooting)
2. Review the [GitHub Issues](https://github.com/your-org/aws-iac-organizations/issues)
3. Consult AWS Organizations documentation
4. Contact your AWS support team
