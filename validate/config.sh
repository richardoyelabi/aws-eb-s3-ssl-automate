#!/bin/bash

# Configuration validation
# Validates config.env file and variable values

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

validate_config_file() {
    echo ""
    log_info "Validating configuration file..."

    if [ ! -f "$SCRIPT_DIR/config.env" ]; then
        log_fail "Configuration file not found: $SCRIPT_DIR/config.env"
        echo "  Create from example: cp config.env.example config.env"
        return 1
    fi

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    local required_vars=(
        "AWS_REGION"
        "AWS_PROFILE"
        "APP_NAME"
        "ENV_NAME"
        "EB_PLATFORM"
        "DOMAIN_NAME"
        "STATIC_ASSETS_BUCKET"
        "UPLOADS_BUCKET"
        "INSTANCE_TYPE"
    )

    local has_errors=false

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_fail "Required variable not set: $var"
            has_errors=true
        else
            log_success "Variable set: $var = ${!var}"
        fi
    done

    if [ "$has_errors" = true ]; then
        return 1
    fi

    log_success "Configuration file is valid"
    return 0
}

validate_bucket_names() {
    echo ""
    log_info "Validating S3 bucket names..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    local bucket_names=("$STATIC_ASSETS_BUCKET" "$UPLOADS_BUCKET")
    local has_errors=false

    for bucket in "${bucket_names[@]}"; do
        # Check bucket name length (3-63 characters)
        local length=${#bucket}
        if [ $length -lt 3 ] || [ $length -gt 63 ]; then
            log_fail "Invalid bucket name length: $bucket (must be 3-63 characters)"
            has_errors=true
            continue
        fi

        # Check bucket name format (lowercase, numbers, hyphens only)
        if [[ ! $bucket =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
            log_fail "Invalid bucket name format: $bucket (must use lowercase letters, numbers, hyphens)"
            has_errors=true
            continue
        fi

        log_success "Bucket name valid: $bucket"
    done

    if [ "$has_errors" = true ]; then
        return 1
    fi
    return 0
}

# Run all config validation checks
validate_config_file || exit 1
validate_bucket_names || exit 1
