# 1Password Integration for AWS Credentials

This document explains how to set up and use 1Password for managing AWS credentials in the AWS IAC Organizations project.

## Overview

The 1Password integration provides a secure way to store and retrieve AWS credentials without hardcoding them in configuration files or relying on web-based SSO logins for local development. This is particularly useful for:

- Storing multiple AWS account credentials securely
- Quick switching between different AWS profiles
- Avoiding the need for web-based SSO authentication during development
- Maintaining credential security with encrypted storage

## Prerequisites

1. **1Password Account**: You need an active 1Password account
2. **1Password Desktop App**: Install from [1password.com](https://1password.com)
3. **1Password CLI**: Already installed via the setup script

## Initial Setup

### 1. Authenticate 1Password CLI

First, you need to connect your 1Password account to the CLI:

```bash
# Add your 1Password account
op account add

# Follow the prompts to enter:
# - Your 1Password sign-in address (e.g., mycompany.1password.com)
# - Your email address
# - Your Master Password or authenticate via the desktop app
```

### 2. Create AWS Vault in 1Password

Create a dedicated vault for AWS credentials (recommended but optional):

1. Open 1Password desktop app
2. Create a new vault called "AWS" (or use an existing vault)
3. This vault will store all your AWS credential items

### 3. Store AWS Credentials

For each AWS profile you want to use, create a new item in your 1Password vault:

#### Item Structure

Create items using one of these naming patterns:
- `AWS-{profile-name}` (recommended)
- `aws-{profile-name}`
- `{profile-name}`

For environment-specific credentials:
- `AWS-{profile-name}-{environment}`
- `aws-{profile-name}-{environment}`

#### Required Fields

Each credential item should contain:

| Field Name | Description | 1Password Field Type |
|------------|-------------|---------------------|
| `Access Key ID` or `username` | AWS Access Key ID | Text or Username |
| `Secret Access Key` or `password` | AWS Secret Access Key | Password |
| `region` (optional) | Default AWS region | Text |
| `Session Token` (optional) | For temporary/MFA credentials | Text |

#### Example Items

```
Item: AWS-bootstrap
- Username: AKIAIOSFODNN7EXAMPLE
- Password: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
- region: us-east-1

Item: AWS-qa-petunka-holdings
- Username: AKIAI44QH8DHBEXAMPLE
- Password: je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
- region: us-west-2

Item: AWS-prod-petunka-holdings
- Username: AKIAI44QH8DHBEXAMPLE
- Password: je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
- region: us-west-2
- Session Token: (for MFA-protected access)
```

## Usage

### Basic Usage

#### 1. Using the Project-Specific Script

The easiest way to load credentials:

```bash
# Development environment (defaults to LocalStack - no AWS credentials needed)
source scripts/aws-env.sh dev

# QA environment
source scripts/aws-env.sh qa petunka-holdings

# Production environment with MFA session
source scripts/aws-env.sh prod petunka-holdings --session

# Bootstrap environment
source scripts/aws-env.sh bootstrap
```

#### 2. Using the Generic Script

For more flexibility:

```bash
# Load default profile
source scripts/load-credentials.sh

# Load specific profile
source scripts/load-credentials.sh --profile petunka-admin

# Load with session token (for MFA)
source scripts/load-credentials.sh --profile admin --session

# Use different vault
source scripts/load-credentials.sh --profile dev --vault MyCompanyAWS
```

#### 3. Using Make Commands

```bash
# Get setup instructions
make setup-env ENV=qa ORG_CONFIG=petunka-holdings

# This will output the command to run:
# source scripts/aws-env.sh qa petunka-holdings --vault AWS
```

### Advanced Usage

#### List Available Credentials

```bash
# List all AWS items in default vault
scripts/load-credentials.sh --list

# List items in specific vault
scripts/load-credentials.sh --list --vault MyCompanyAWS
```

#### Environment-Specific Profiles

The system automatically maps environments to credential profiles:

| Environment | Profile Pattern | Example |
|-------------|----------------|---------|
| `bootstrap` | `bootstrap` | `AWS-bootstrap` |
| `dev` | `dev` | `AWS-dev` |
| `qa` | `qa-{org_config}` | `AWS-qa-petunka-holdings` |
| `prod` | `prod-{org_config}` | `AWS-prod-petunka-holdings` |

#### Session Tokens and MFA

For accounts requiring MFA or assume role operations:

```bash
# Load credentials with session token
source scripts/aws-env.sh prod petunka-holdings --session

# Or with the generic script
source scripts/load-credentials.sh --profile prod-admin --session
```

## Integration with Existing Workflow

### LocalStack Development

For development with LocalStack (recommended per project rules):

```bash
# Automatically uses LocalStack - no real AWS credentials needed
source scripts/aws-env.sh dev
make deploy ENV=dev ORG_CONFIG=example TARGET=localstack
```

### Real AWS Environments

For QA and Production deployments:

```bash
# Load credentials and deploy
source scripts/aws-env.sh qa petunka-holdings
make deploy ENV=qa ORG_CONFIG=petunka-holdings TARGET=aws

# For production with MFA
source scripts/aws-env.sh prod petunka-holdings --session
make deploy ENV=prod ORG_CONFIG=petunka-holdings TARGET=aws
```

### Environment Variables Set

When credentials are loaded, the following environment variables are set:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (if session flag used)
- `AWS_PROFILE`
- `AWS_DEFAULT_REGION` (if specified in 1Password)
- `TF_VAR_environment`
- `TF_VAR_organization_config` (if org config specified)
- `LOCALSTACK_ENDPOINT` (for LocalStack development)

## Security Best Practices

### 1. Use Item Templates

Create a template item in 1Password with the standard field names to ensure consistency.

### 2. Regular Credential Rotation

Regularly rotate AWS access keys and update the corresponding 1Password items.

### 3. Separate Credentials by Environment

Use different AWS credentials for different environments (dev, qa, prod) and store them as separate 1Password items.

### 4. Limit Permissions

Each AWS credential should have minimal required permissions:
- Development: Limited to development resources
- QA: Limited to QA environment resources  
- Production: Full permissions but with MFA requirement

### 5. Use Session Tokens for Production

For production environments, use temporary credentials with session tokens:

```bash
# Generate session token with MFA first, then store in 1Password
aws sts get-session-token --serial-number arn:aws:iam::ACCOUNT:mfa/USERNAME --token-code 123456
```

## Troubleshooting

### Common Issues

#### 1Password CLI Not Authenticated

```bash
# Error: 1Password CLI not authenticated
op account add
```

#### Credential Item Not Found

```bash
# List available items to verify naming
scripts/load-credentials.sh --list

# Check if vault name is correct
scripts/load-credentials.sh --list --vault YourVaultName
```

#### AWS STS Verification Failed

```bash
# Verify credentials manually
aws sts get-caller-identity

# Check if credentials are expired or invalid
# Update credentials in 1Password if needed
```

#### Permission Denied

- Verify AWS credentials have necessary permissions
- For production, ensure MFA session token is current
- Check AWS account access policies

### Debugging

Enable verbose output:

```bash
# Enable debug mode for troubleshooting
set -x
source scripts/load-credentials.sh --profile your-profile
set +x
```

## Migration from Existing Setup

If you're currently using AWS CLI profiles or environment variables:

### 1. Export Existing Credentials

```bash
# List current AWS profiles
aws configure list-profiles

# View current credentials (be careful not to expose in logs)
aws configure get aws_access_key_id --profile your-profile
```

### 2. Create 1Password Items

For each existing profile:
1. Create new 1Password item using naming convention
2. Copy access key ID and secret access key
3. Add region and any session tokens
4. Test the new setup

### 3. Remove Old Credentials

After verifying 1Password integration works:
```bash
# Remove AWS CLI profiles
rm ~/.aws/credentials
rm ~/.aws/config

# Or selectively remove profiles
aws configure --profile old-profile remove
```

## Example Workflow

Complete workflow for deploying to production:

```bash
# 1. Set up credentials
source scripts/aws-env.sh prod petunka-holdings --session

# 2. Verify credentials
aws sts get-caller-identity

# 3. Validate configuration
make validate ORG_CONFIG=petunka-holdings

# 4. Plan deployment
make plan ENV=prod ORG_CONFIG=petunka-holdings TARGET=aws

# 5. Deploy (with confirmation)
make deploy ENV=prod ORG_CONFIG=petunka-holdings TARGET=aws
```

## Support

For issues specific to 1Password:
- [1Password CLI Documentation](https://developer.1password.com/docs/cli)
- [1Password Support](https://support.1password.com)

For issues with this integration:
- Check the troubleshooting section above
- Verify your 1Password item structure matches the expected format
- Test with the `--list` flag to verify vault access
