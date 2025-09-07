#!/bin/bash
#
# AWS Environment Setup for IAC Organizations Project
# This script sets up AWS credentials using 1Password for specific environments
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the main credential loading script
source "$SCRIPT_DIR/load-credentials.sh"

# Default values based on project structure
DEFAULT_VAULT="AWS"

usage() {
    cat << EOF
Usage: $0 ENV [ORG_CONFIG] [OPTIONS]

Set up AWS credentials for the AWS IAC Organizations project.

ARGUMENTS:
    ENV                     Environment (dev, qa, prod, bootstrap)
    ORG_CONFIG             Organization config name (optional, default: example)

OPTIONS:
    -v, --vault VAULT       1Password vault name (default: AWS)
    -s, --session           Load session token (for MFA)
    -t, --target TARGET     Deployment target (aws, localstack) - for dev only
    -h, --help              Show this help message

EXAMPLES:
    # Set up for development with LocalStack (no AWS credentials needed)
    source $0 dev

    # Set up for QA environment
    source $0 qa petunka-holdings

    # Set up for production with MFA session
    source $0 prod petunka-holdings --session

    # Set up bootstrap environment
    source $0 bootstrap

ENVIRONMENT VARIABLES SET:
    AWS_ACCESS_KEY_ID (if not using LocalStack)
    AWS_SECRET_ACCESS_KEY (if not using LocalStack)
    AWS_SESSION_TOKEN (if --session used)
    AWS_PROFILE
    AWS_DEFAULT_REGION
    TF_VAR_environment
    TF_VAR_organization_config (if ORG_CONFIG provided)
    LOCALSTACK_ENDPOINT (if dev + localstack)

EOF
}

setup_localstack_env() {
    echo -e "\033[0;32m[INFO]\033[0m Setting up LocalStack environment variables"
    
    # Set LocalStack-specific environment variables
    export AWS_ACCESS_KEY_ID="test"
    export AWS_SECRET_ACCESS_KEY="test"
    export AWS_DEFAULT_REGION="us-east-1"
    export AWS_PROFILE="localstack"
    export LOCALSTACK_ENDPOINT="http://localhost:4566"
    
    # LocalStack AWS provider configuration
    export TF_VAR_aws_region="us-east-1"
    export TF_VAR_localstack_endpoint="http://localhost:4566"
    
    echo -e "\033[0;32m[INFO]\033[0m LocalStack environment configured"
    echo -e "\033[1;33m[WARN]\033[0m Make sure LocalStack is running: make localstack-start"
}

setup_aws_credentials() {
    local environment="$1"
    local org_config="$2"
    local vault="$3"
    local use_session="$4"
    
    # Determine AWS profile based on environment and org config
    local aws_profile="default"
    
    case "$environment" in
        "bootstrap")
            aws_profile="bootstrap"
            ;;
        "dev")
            aws_profile="dev"
            ;;
        "qa")
            if [ -n "$org_config" ]; then
                aws_profile="qa-${org_config}"
            else
                aws_profile="qa"
            fi
            ;;
        "prod")
            if [ -n "$org_config" ]; then
                aws_profile="prod-${org_config}"
            else
                aws_profile="prod"
            fi
            ;;
    esac
    
    echo -e "\033[0;32m[INFO]\033[0m Loading AWS credentials for profile: $aws_profile"
    
    # Load credentials using the main script
    load_credentials "$vault" "$aws_profile" "$environment" "$use_session"
}

main() {
    local environment=""
    local org_config=""
    local vault="$DEFAULT_VAULT"
    local use_session="false"
    local target=""
    
    # Parse arguments
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    environment="$1"
    shift
    
    # Second argument is org_config if it doesn't start with -
    if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
        org_config="$1"
        shift
    fi
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--vault)
                vault="$2"
                shift 2
                ;;
            -s|--session)
                use_session="true"
                shift
                ;;
            -t|--target)
                target="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo -e "\033[0;31m[ERROR]\033[0m Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate environment
    case "$environment" in
        dev|qa|prod|bootstrap)
            ;;
        *)
            echo -e "\033[0;31m[ERROR]\033[0m Invalid environment: $environment"
            echo -e "\033[0;31m[ERROR]\033[0m Valid environments: dev, qa, prod, bootstrap"
            exit 1
            ;;
    esac
    
    # Set Terraform variables
    export TF_VAR_environment="$environment"
    
    if [ -n "$org_config" ]; then
        export TF_VAR_organization_config="$PROJECT_ROOT/config/organizations/${org_config}.yaml"
        echo -e "\033[0;32m[INFO]\033[0m Using organization config: $org_config"
    fi
    
    # Handle dev environment with LocalStack option
    if [ "$environment" = "dev" ] && [ "$target" = "localstack" ]; then
        setup_localstack_env
        return 0
    fi
    
    # Handle dev environment default to LocalStack based on project rules
    if [ "$environment" = "dev" ] && [ -z "$target" ]; then
        echo -e "\033[1;33m[INFO]\033[0m Development environment detected - defaulting to LocalStack"
        setup_localstack_env
        return 0
    fi
    
    # Set up AWS credentials for non-LocalStack environments
    if command -v op &> /dev/null; then
        setup_aws_credentials "$environment" "$org_config" "$vault" "$use_session"
    else
        echo -e "\033[0;31m[ERROR]\033[0m 1Password CLI not found. Install with: brew install --cask 1password/tap/1password-cli"
        exit 1
    fi
    
    echo -e "\033[0;32m[INFO]\033[0m Environment setup complete for: $environment"
    if [ -n "$org_config" ]; then
        echo -e "\033[0;32m[INFO]\033[0m Organization config: $org_config"
    fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
