# Quick Start: 1Password AWS Credentials

This is a quick setup guide to get you started with 1Password credential management for AWS.

## 1. Complete 1Password Authentication

First, authenticate with your 1Password account:

```bash
op account add
```

Follow the prompts to connect to your 1Password account.

## 2. Create AWS Credential Items

Create items in your 1Password vault for each AWS profile you need:

### Item Naming Convention
- `AWS-bootstrap` (for bootstrap environment)
- `AWS-qa-petunka-holdings` (for QA with specific org)
- `AWS-prod-petunka-holdings` (for production with specific org)

### Required Fields for Each Item
- **Username**: Your AWS Access Key ID
- **Password**: Your AWS Secret Access Key  
- **region** (custom field): Your preferred AWS region (e.g., `us-east-1`)

## 3. Test the Setup

Verify everything works:

```bash
# List available credentials
scripts/load-credentials.sh --list

# Test loading credentials for bootstrap
source scripts/aws-env.sh bootstrap

# Verify AWS access
aws sts get-caller-identity
```

## 4. Use in Your Workflow

### Development (LocalStack - Default)
```bash
# No AWS credentials needed - uses LocalStack
source scripts/aws-env.sh dev
make deploy ENV=dev ORG_CONFIG=example
```

### QA Environment
```bash
source scripts/aws-env.sh qa petunka-holdings
make deploy ENV=qa ORG_CONFIG=petunka-holdings TARGET=aws
```

### Production (with MFA)
```bash
source scripts/aws-env.sh prod petunka-holdings --session
make deploy ENV=prod ORG_CONFIG=petunka-holdings TARGET=aws
```

## Need Help?

- **Full documentation**: See `docs/1PASSWORD-SETUP.md`
- **List available commands**: `make help`
- **Debug credential loading**: `scripts/load-credentials.sh --list`

## Common Commands Summary

| Command | Purpose |
|---------|---------|
| `source scripts/aws-env.sh ENV [ORG_CONFIG]` | Load environment credentials |
| `scripts/load-credentials.sh --list` | List available credential items |
| `make setup-env ENV=qa ORG_CONFIG=my-org` | Get setup instructions |
| `aws sts get-caller-identity` | Verify loaded credentials |

That's it! You're now set up to use 1Password for secure AWS credential management.
