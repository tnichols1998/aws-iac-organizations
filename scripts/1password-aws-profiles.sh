#!/bin/bash
#
# 1Password to AWS CLI Profiles Integration
# Syncs AWS credentials from 1Password to standard AWS CLI profiles
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_VAULT="AWS"
AWS_DIR="${HOME}/.aws"
CREDENTIALS_FILE="${AWS_DIR}/credentials"
CONFIG_FILE="${AWS_DIR}/config"

usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Manage AWS CLI profiles using 1Password for credential storage.

COMMANDS:
    sync                     Sync all AWS credentials from 1Password to AWS CLI profiles
    sync-profile PROFILE     Sync specific profile from 1Password
    list                     List available AWS profiles in 1Password
    setup PROFILE            Interactive setup for new AWS profile
    remove PROFILE           Remove AWS CLI profile
    backup                   Backup current AWS credentials
    restore                  Restore AWS credentials from backup

OPTIONS:
    -v, --vault VAULT        1Password vault name (default: AWS)
    -f, --force              Force overwrite existing profiles
    -d, --dry-run            Show what would be done without making changes
    -b, --backup             Create backup before making changes
    -h, --help              Show this help message

EXAMPLES:
    # Sync all AWS profiles from 1Password
    $0 sync

    # Sync specific profile
    $0 sync-profile production

    # List available profiles in 1Password
    $0 list

    # Interactive setup for new profile
    $0 setup my-new-profile

    # Backup current AWS credentials before syncing
    $0 sync --backup

AWS CLI PROFILE STRUCTURE:
    1Password items should be named: AWS-{profile-name}
    Examples: AWS-default, AWS-production, AWS-development, AWS-qa

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

debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $*" >&2
    fi
}

check_prerequisites() {
    # Check 1Password CLI
    if ! command -v op &> /dev/null; then
        error "1Password CLI not found. Install with: brew install --cask 1password/tap/1password-cli"
    fi
    
    # Check 1Password authentication
    if ! op account list > /dev/null 2>&1; then
        error "1Password CLI not authenticated. Run: op account add"
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        warn "AWS CLI not found. Install with: brew install awscli"
    fi
    
    # Create AWS directory if it doesn't exist
    mkdir -p "$AWS_DIR"
}

backup_aws_config() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_dir="${AWS_DIR}/backups/${timestamp}"
    
    log "Creating backup of AWS configuration..."
    mkdir -p "$backup_dir"
    
    if [ -f "$CREDENTIALS_FILE" ]; then
        cp "$CREDENTIALS_FILE" "$backup_dir/credentials"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$timestamp"
    fi
    
    log "Backup created at: $backup_dir"
    echo "$backup_dir" # Return backup path for potential restoration
}

restore_aws_config() {
    local backup_dir="$1"
    
    if [ ! -d "$backup_dir" ]; then
        error "Backup directory not found: $backup_dir"
    fi
    
    log "Restoring AWS configuration from: $backup_dir"
    
    if [ -f "$backup_dir/credentials" ]; then
        cp "$backup_dir/credentials" "$CREDENTIALS_FILE"
        log "Restored credentials file"
    fi
    
    # Find and restore config backup
    local config_backup=$(find "$AWS_DIR" -name "config.backup.*" | sort | tail -n 1)
    if [ -n "$config_backup" ] && [ -f "$config_backup" ]; then
        cp "$config_backup" "$CONFIG_FILE"
        log "Restored config file"
    fi
    
    log "AWS configuration restored successfully"
}

list_1password_profiles() {
    local vault="$1"
    
    log "Available AWS profiles in 1Password vault '$vault':"
    echo
    
    # List items that match AWS profile patterns
    if ! op item list --vault="$vault" --format=json 2>/dev/null | jq -r '.[] | select(.title | test("^(AWS-|aws-|[a-z0-9-]+)")) | .title' | sort; then
        warn "No AWS credential items found in vault '$vault'"
        echo
        log "Available vaults:"
        op vault list --format=table
        return 1
    fi
}

get_1password_credentials() {
    local vault="$1"
    local profile="$2"
    
    # Try different naming patterns for 1Password items
    local item_patterns=(
        "AWS-${profile}"
        "aws-${profile}"
        "${profile}"
    )
    
    local item_name=""
    for pattern in "${item_patterns[@]}"; do
        if op item get "$pattern" --vault="$vault" &>/dev/null; then
            item_name="$pattern"
            break
        fi
    done
    
    if [ -z "$item_name" ]; then
        error "Could not find 1Password item for profile '$profile' in vault '$vault'"
    fi
    
    debug "Found 1Password item: $item_name"
    
    # Get credentials from 1Password
    local access_key=""
    local secret_key=""
    local region=""
    local output_format=""
    local session_token=""
    
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
    
    # Try to get region
    for field in "region" "aws_region" "AWS_DEFAULT_REGION" "default_region"; do
        if region=$(op item get "$item_name" --vault="$vault" --fields="$field" 2>/dev/null); then
            break
        fi
    done
    
    # Try to get output format
    for field in "output" "output_format" "aws_output_format"; do
        if output_format=$(op item get "$item_name" --vault="$vault" --fields="$field" 2>/dev/null); then
            break
        fi
    done
    
    # Try to get session token
    for field in "Session Token" "session_token" "AWS_SESSION_TOKEN"; do
        if session_token=$(op item get "$item_name" --vault="$vault" --fields="$field" 2>/dev/null); then
            break
        fi
    done
    
    # Validate required credentials
    if [ -z "$access_key" ] || [ -z "$secret_key" ]; then
        error "Could not retrieve AWS Access Key ID or Secret Access Key from 1Password item '$item_name'"
    fi
    
    # Return credentials as JSON for easier parsing
    jq -n \
        --arg access_key "$access_key" \
        --arg secret_key "$secret_key" \
        --arg region "${region:-us-east-1}" \
        --arg output "${output_format:-json}" \
        --arg session_token "$session_token" \
        '{
            access_key: $access_key,
            secret_key: $secret_key,
            region: $region,
            output: $output,
            session_token: ($session_token | if . == "" then null else . end)
        }'
}

create_aws_profile() {
    local profile="$1"
    local credentials_json="$2"
    local dry_run="${3:-false}"
    
    local access_key=$(echo "$credentials_json" | jq -r '.access_key')
    local secret_key=$(echo "$credentials_json" | jq -r '.secret_key')
    local region=$(echo "$credentials_json" | jq -r '.region')
    local output=$(echo "$credentials_json" | jq -r '.output')
    local session_token=$(echo "$credentials_json" | jq -r '.session_token // empty')
    
    if [ "$dry_run" = "true" ]; then
        log "[DRY RUN] Would create/update AWS profile: $profile"
        log "[DRY RUN] Region: $region, Output: $output"
        if [ -n "$session_token" ]; then
            log "[DRY RUN] Would include session token"
        fi
        return 0
    fi
    
    log "Creating/updating AWS profile: $profile"
    
    # Update credentials file
    aws configure set aws_access_key_id "$access_key" --profile "$profile"
    aws configure set aws_secret_access_key "$secret_key" --profile "$profile"
    
    if [ -n "$session_token" ]; then
        aws configure set aws_session_token "$session_token" --profile "$profile"
    fi
    
    # Update config file
    aws configure set region "$region" --profile "$profile"
    aws configure set output "$output" --profile "$profile"
    
    log "AWS profile '$profile' updated successfully"
}

sync_profile() {
    local vault="$1"
    local profile="$2"
    local force="${3:-false}"
    local dry_run="${4:-false}"
    
    # Check if profile already exists
    if aws configure list-profiles 2>/dev/null | grep -q "^${profile}$"; then
        if [ "$force" != "true" ] && [ "$dry_run" != "true" ]; then
            read -p "Profile '$profile' already exists. Overwrite? (y/N): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                log "Skipping profile: $profile"
                return 0
            fi
        fi
    fi
    
    # Get credentials from 1Password
    local credentials
    if ! credentials=$(get_1password_credentials "$vault" "$profile"); then
        error "Failed to get credentials for profile: $profile"
    fi
    
    # Create AWS profile
    create_aws_profile "$profile" "$credentials" "$dry_run"
}

sync_all_profiles() {
    local vault="$1"
    local force="${2:-false}"
    local dry_run="${3:-false}"
    
    log "Syncing all AWS profiles from 1Password vault: $vault"
    
    # Get list of AWS items from 1Password
    local items
    if ! items=$(op item list --vault="$vault" --format=json 2>/dev/null); then
        error "Could not list items in vault '$vault'"
    fi
    
    # Extract profile names from item titles
    local profiles
    profiles=$(echo "$items" | jq -r '.[] | select(.title | test("^(AWS-|aws-)")) | .title | sub("^(AWS-|aws-)"; "")')
    
    if [ -z "$profiles" ]; then
        warn "No AWS credential items found in vault '$vault'"
        return 1
    fi
    
    # Sync each profile
    while IFS= read -r profile; do
        if [ -n "$profile" ]; then
            sync_profile "$vault" "$profile" "$force" "$dry_run"
        fi
    done <<< "$profiles"
    
    log "Profile sync completed"
}

setup_interactive_profile() {
    local profile="$1"
    local vault="$2"
    
    log "Interactive setup for AWS profile: $profile"
    echo
    
    # Check if 1Password item exists
    local item_name="AWS-${profile}"
    if op item get "$item_name" --vault="$vault" &>/dev/null; then
        log "1Password item '$item_name' already exists"
        read -p "Update existing item? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            return 0
        fi
    else
        log "Creating new 1Password item: $item_name"
    fi
    
    # Collect credential information
    read -p "AWS Access Key ID: " access_key
    read -s -p "AWS Secret Access Key: " secret_key
    echo
    read -p "Default region (us-east-1): " region
    region=${region:-us-east-1}
    read -p "Default output format (json): " output_format
    output_format=${output_format:-json}
    
    # Create or update 1Password item
    if op item get "$item_name" --vault="$vault" &>/dev/null; then
        # Update existing item
        op item edit "$item_name" --vault="$vault" \
            username="$access_key" \
            password="$secret_key" \
            region="$region" \
            output="$output_format"
    else
        # Create new item
        op item create --category=Login --vault="$vault" --title="$item_name" \
            username="$access_key" \
            password="$secret_key" \
            region[text]="$region" \
            output[text]="$output_format"
    fi
    
    log "1Password item created/updated: $item_name"
    
    # Sync to AWS profile
    sync_profile "$vault" "$profile" "true" "false"
}

remove_aws_profile() {
    local profile="$1"
    
    if ! aws configure list-profiles 2>/dev/null | grep -q "^${profile}$"; then
        warn "AWS profile '$profile' does not exist"
        return 0
    fi
    
    log "Removing AWS profile: $profile"
    
    # Remove from credentials file
    aws configure set aws_access_key_id "" --profile "$profile"
    aws configure set aws_secret_access_key "" --profile "$profile"
    aws configure set aws_session_token "" --profile "$profile"
    
    # Remove from config file  
    aws configure set region "" --profile "$profile"
    aws configure set output "" --profile "$profile"
    
    log "AWS profile '$profile' removed"
}

main() {
    local command=""
    local vault="$DEFAULT_VAULT"
    local force="false"
    local dry_run="false"
    local backup="false"
    local profile=""
    
    # Parse arguments
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    command="$1"
    shift
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--vault)
                vault="$2"
                shift 2
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -b|--backup)
                backup="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                if [ -z "$profile" ]; then
                    profile="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Check prerequisites
    check_prerequisites
    
    # Create backup if requested
    local backup_path=""
    if [ "$backup" = "true" ]; then
        backup_path=$(backup_aws_config)
    fi
    
    # Execute command
    case "$command" in
        sync)
            sync_all_profiles "$vault" "$force" "$dry_run"
            ;;
        sync-profile)
            if [ -z "$profile" ]; then
                error "Profile name required for sync-profile command"
            fi
            sync_profile "$vault" "$profile" "$force" "$dry_run"
            ;;
        list)
            list_1password_profiles "$vault"
            ;;
        setup)
            if [ -z "$profile" ]; then
                error "Profile name required for setup command"
            fi
            setup_interactive_profile "$profile" "$vault"
            ;;
        remove)
            if [ -z "$profile" ]; then
                error "Profile name required for remove command"
            fi
            remove_aws_profile "$profile"
            ;;
        backup)
            backup_aws_config
            ;;
        restore)
            if [ -z "$profile" ]; then
                # List available backups
                log "Available backups:"
                find "${AWS_DIR}/backups" -type d -name "*" 2>/dev/null | sort -r | head -10
            else
                restore_aws_config "$profile"
            fi
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
}

main "$@"
