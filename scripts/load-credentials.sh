#!/bin/bash
#
# AWS Credential Management with 1Password
# This script loads AWS credentials from 1Password and sets environment variables
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_VAULT="AWS"
DEFAULT_PROFILE="default"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Load AWS credentials from 1Password and export as environment variables.

OPTIONS:
    -p, --profile PROFILE    AWS profile name (default: default)
    -v, --vault VAULT        1Password vault name (default: AWS)
    -e, --environment ENV    Environment (dev, qa, prod)
    -s, --session            Load session token (for MFA/assume role)
    -l, --list               List available credential items in vault
    -h, --help              Show this help message

EXAMPLES:
    # Load default AWS credentials
    source $0

    # Load credentials for specific profile
    source $0 --profile petunka-admin

    # Load credentials for specific environment
    source $0 --environment prod --profile production

    # Load session credentials with MFA token
    source $0 --profile admin --session

    # List available credential items
    $0 --list

ENVIRONMENT VARIABLES SET:
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN (if --session flag is used)
    AWS_PROFILE
    AWS_DEFAULT_REGION

EOF
}

log() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

check_1password_auth() {
    if ! op account list > /dev/null 2>&1; then
        error "1Password CLI not authenticated. Run: op account add"
    fi
}

check_1password_cli() {
    if ! command -v op &> /dev/null; then
        error "1Password CLI not found. Install with: brew install --cask 1password/tap/1password-cli"
    fi
}

list_credentials() {
    local vault=${1:-$DEFAULT_VAULT}
    log "Available AWS credential items in vault '$vault':"
    echo
    
    if ! op item list --vault="$vault" --categories=Login,Password,Server 2>/dev/null; then
        warn "Vault '$vault' not found or no items available"
        echo
        log "Available vaults:"
        op vault list --format=table
        return 1
    fi
}

get_credential_item() {
    local vault="$1"
    local profile="$2"
    local environment="$3"
    
    # Try different naming patterns for 1Password items
    local item_patterns=(
        "AWS-${profile}"
        "AWS-${profile}-${environment}"
        "${profile}"
        "${profile}-${environment}"
        "aws-${profile}"
        "aws-${profile}-${environment}"
    )
    
    for pattern in "${item_patterns[@]}"; do
        if op item get "$pattern" --vault="$vault" &>/dev/null; then
            echo "$pattern"
            return 0
        fi
    done
    
    return 1
}

load_credentials() {
    local vault="$1"
    local profile="$2"
    local environment="$3"
    local use_session="$4"
    
    log "Loading AWS credentials for profile: $profile"
    
    # Find the credential item
    local item_name
    if ! item_name=$(get_credential_item "$vault" "$profile" "$environment"); then
        error "Could not find AWS credentials for profile '$profile' in vault '$vault'"
    fi
    
    log "Found credential item: $item_name"
    
    # Get credentials from 1Password
    local access_key
    local secret_key
    local session_token=""
    local region=""
    
    # Try to get access key (multiple possible field names)
    for field in "Access Key ID" "access_key_id" "username" "AWS_ACCESS_KEY_ID"; do
        if access_key=$(op item get "$item_name" --vault="$vault" --fields="$field" 2>/dev/null); then
            break
        fi
    done
    
    # Try to get secret key (multiple possible field names)
    for field in "Secret Access Key" "secret_access_key" "password" "AWS_SECRET_ACCESS_KEY"; do
        if secret_key=$(op item get "$item_name" --vault="$vault" --fields="$field" 2>/dev/null); then
            break
        fi
    done
    
    # Try to get session token if requested
    if [ "$use_session" = "true" ]; then
        for field in "Session Token" "session_token" "AWS_SESSION_TOKEN"; do
            if session_token=$(op item get "$item_name" --vault="$vault" --fields="$field" 2>/dev/null); then
                break
            fi
        done
    fi
    
    # Try to get region
    for field in "region" "aws_region" "AWS_DEFAULT_REGION"; do
        if region=$(op item get "$item_name" --vault="$vault" --fields="$field" 2>/dev/null); then
            break
        fi
    done
    
    # Validate required credentials
    if [ -z "$access_key" ] || [ -z "$secret_key" ]; then
        error "Could not retrieve AWS Access Key ID or Secret Access Key from 1Password item '$item_name'"
    fi
    
    # Export environment variables
    export AWS_ACCESS_KEY_ID="$access_key"
    export AWS_SECRET_ACCESS_KEY="$secret_key"
    export AWS_PROFILE="$profile"
    
    if [ -n "$session_token" ]; then
        export AWS_SESSION_TOKEN="$session_token"
        log "Loaded AWS credentials with session token for profile: $profile"
    else
        log "Loaded AWS credentials for profile: $profile"
    fi
    
    if [ -n "$region" ]; then
        export AWS_DEFAULT_REGION="$region"
        log "Set default region: $region"
    fi
    
    # Verify credentials work
    log "Verifying AWS credentials..."
    if ! aws sts get-caller-identity &>/dev/null; then
        warn "Credentials loaded but AWS STS verification failed. Check your credentials and permissions."
    else
        log "AWS credentials verified successfully"
    fi
}

main() {
    local vault="$DEFAULT_VAULT"
    local profile="$DEFAULT_PROFILE"
    local environment=""
    local use_session="false"
    local list_mode="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--profile)
                profile="$2"
                shift 2
                ;;
            -v|--vault)
                vault="$2"
                shift 2
                ;;
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -s|--session)
                use_session="true"
                shift
                ;;
            -l|--list)
                list_mode="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Check prerequisites
    check_1password_cli
    check_1password_auth
    
    if [ "$list_mode" = "true" ]; then
        list_credentials "$vault"
        return 0
    fi
    
    # Load credentials
    load_credentials "$vault" "$profile" "$environment" "$use_session"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
