# Two-Phase Bootstrap Deployment Guide

This project uses a **two-phase deployment approach** to securely manage AWS Organizations infrastructure:

## Phase 1: Bootstrap (Root Account Required)
**What**: Creates minimal OIDC provider and GitHub Actions IAM role
**Who**: Must be run by organization root account holder
**When**: One-time setup, or when adding new repositories

## Phase 2: Main Infrastructure (GitHub Actions)  
**What**: Deploys all organization resources (SSO, SCPs, accounts, etc.)
**Who**: Executed by GitHub Actions using OIDC credentials
**When**: Every infrastructure change via CI/CD

---

## 🔐 Phase 1: Bootstrap Setup

### Prerequisites
- Access to AWS organization root account
- AWS CLI configured with root account credentials
- Terraform/OpenTofu installed

### Step 1: Navigate to Bootstrap Environment
```bash
cd environments/bootstrap
```

### Step 2: Initialize Terraform (Root Account)
```bash
# Uses local backend for bootstrap
tofu init
```

### Step 3: Review Bootstrap Plan
```bash
# Review what will be created
tofu plan
```

The bootstrap will create:
- **GitHub OIDC Provider**: Allows GitHub Actions to authenticate to AWS
- **GitHubActions-OrganizationAdmin Role**: Comprehensive permissions for infrastructure management
- **IAM Policies**: Full access to Organizations, IAM, SSO, and supporting services

### Step 4: Apply Bootstrap (Root Account Only)
```bash
# Apply with root account credentials
tofu apply
```

### Step 5: Note the Outputs
After successful apply, note these important outputs:
```bash
# GitHub Actions Role ARN - add this to your GitHub repository secrets
github_actions_role_arn = "arn:aws:iam::ACCOUNT:role/GitHubActions-OrganizationAdmin"

# OIDC Provider ARN  
github_oidc_provider_arn = "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
```

---

## 🚀 Phase 2: Main Infrastructure (CI/CD)

### GitHub Repository Setup

#### 1. Add GitHub Secrets
Add these secrets to your GitHub repository:

```
AWS_ROLE_ARN: arn:aws:iam::ACCOUNT:role/GitHubActions-OrganizationAdmin  
AWS_REGION: us-west-2
```

#### 2. Create GitHub Actions Workflow
Example `.github/workflows/terraform.yml`:

```yaml
name: Deploy AWS Organizations Infrastructure

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      
    steps:
    - uses: actions/checkout@v4
    
    - name: Configure AWS credentials via OIDC
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        role-session-name: github-actions-terraform
        aws-region: ${{ secrets.AWS_REGION }}
        
    - name: Setup OpenTofu
      uses: opentofu/setup-opentofu@v1
      with:
        tofu_version: "1.6.0"
        
    - name: Terraform Init
      run: |
        cd environments/qa
        tofu init
        
    - name: Terraform Plan
      run: |
        cd environments/qa
        export TF_VAR_organization_config="../../config/organizations/petunka-holdings.yaml"
        export TF_VAR_environment="qa"
        tofu plan
        
    - name: Terraform Apply
      if: github.ref == 'refs/heads/main'
      run: |
        cd environments/qa  
        export TF_VAR_organization_config="../../config/organizations/petunka-holdings.yaml"
        export TF_VAR_environment="qa"
        tofu apply -auto-approve
```

### Local Development After Bootstrap

Once bootstrap is complete, you can also run the main infrastructure locally using the same OIDC role:

```bash
# Configure AWS to use the OIDC role (requires aws-cli v2)
aws configure set role_arn arn:aws:iam::ACCOUNT:role/GitHubActions-OrganizationAdmin
aws configure set web_identity_token_file ~/.aws/web-identity-token
aws configure set role_session_name local-development

# Then run terraform as normal
cd environments/qa
export TF_VAR_organization_config="../../config/organizations/petunka-holdings.yaml"
export TF_VAR_environment="qa"
tofu init
tofu plan
tofu apply
```

---

## 🔄 Phase Responsibilities

### Bootstrap Phase (Root Account)
✅ **Creates**:
- GitHub OIDC Provider
- GitHubActions-OrganizationAdmin IAM Role
- Comprehensive IAM policies for infrastructure management

❌ **Does NOT manage**:
- Organization structure
- SSO Permission Sets  
- Service Control Policies
- Tag Policies
- Member accounts or OUs

### Main Infrastructure Phase (GitHub Actions)
✅ **Manages**:
- AWS Organization configuration
- Organizational Units (OUs)
- Member accounts
- SSO Permission Sets and assignments
- Service Control Policies  
- Tag Policies
- All ongoing infrastructure changes

❌ **Cannot access**:
- Bootstrap-managed OIDC provider
- Bootstrap-managed IAM roles
- Root account exclusive operations

---

## 🔒 Security Model

### Principle of Least Privilege
- **Root account**: Only used for initial OIDC setup
- **GitHub Actions**: Has comprehensive permissions but operates through OIDC
- **OIDC constraints**: Role can only be assumed by specified GitHub repositories

### Repository Security
The GitHubActions-OrganizationAdmin role trust policy restricts access to:
- `petunka-holdings/infrastructure`
- `petunka-holdings/marketing-platform`  
- `petunka-holdings/coaching-platform`

### Credential Security
- ✅ No long-lived AWS access keys
- ✅ Short-lived tokens via OIDC
- ✅ Repository-specific access controls
- ✅ Audit trail through CloudTrail

---

## 🛠️ Troubleshooting

### Bootstrap Issues
```bash
# Check if you're using root account
aws sts get-caller-identity

# Ensure you have organization permissions
aws organizations describe-organization
```

### GitHub Actions Issues  
```bash
# Verify OIDC provider exists
aws iam get-open-id-connect-provider --open-id-connect-provider-arn <OIDC_ARN>

# Check role trust policy
aws iam get-role --role-name GitHubActions-OrganizationAdmin
```

### Permission Issues
The GitHub Actions role has comprehensive permissions including:
- `organizations:*` - Full organization management
- `iam:*` - Full IAM management  
- `sso:*`, `sso-admin:*`, `identitystore:*` - Full SSO management
- State management permissions for S3 and DynamoDB

---

## 🔄 Adding New Repositories

To grant additional repositories access to the OIDC role:

1. **Update bootstrap configuration**:
```hcl
variable "github_repositories" {
  default = [
    "petunka-holdings/infrastructure",
    "petunka-holdings/marketing-platform", 
    "petunka-holdings/coaching-platform",
    "petunka-holdings/NEW-REPOSITORY"  # Add here
  ]
}
```

2. **Re-run bootstrap** (requires root account):
```bash
cd environments/bootstrap
tofu plan  # Review changes
tofu apply # Apply updates
```

The role trust policy will be updated to include the new repository.

---

## 📋 Summary

This two-phase approach provides:
- **Security**: Minimal root account exposure
- **Automation**: CI/CD for infrastructure changes  
- **Auditability**: All changes tracked in Git
- **Scalability**: Easy to add new repositories/environments
- **Compliance**: Proper separation of duties
