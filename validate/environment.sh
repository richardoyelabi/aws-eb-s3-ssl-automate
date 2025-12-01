#!/bin/bash

# Environment readiness validation
# Checks for existing AWS resources that might conflict

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.env"

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

check_existing_resources() {
    echo ""
    log_info "Checking for existing resources..."

    # Check if application exists
    if aws elasticbeanstalk describe-applications \
        --application-names "$APP_NAME" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null | grep -q "$APP_NAME"; then
        log_warn "Application already exists: $APP_NAME"
    else
        log_info "Application does not exist (will be created): $APP_NAME"
    fi

    # Check if environment exists
    if aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-names "$ENV_NAME" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null | grep -q "$ENV_NAME"; then
        log_warn "Environment already exists: $ENV_NAME"
    else
        log_info "Environment does not exist (will be created): $ENV_NAME"
    fi

    # Check if buckets exist
    for bucket in "$STATIC_ASSETS_BUCKET" "$UPLOADS_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" --profile "$AWS_PROFILE" 2>/dev/null; then
            log_warn "Bucket already exists: $bucket"
        else
            log_info "Bucket does not exist (will be created): $bucket"
        fi
    done
}

# Run environment checks (non-blocking)
check_existing_resources
