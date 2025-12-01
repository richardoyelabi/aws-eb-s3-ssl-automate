#!/bin/bash

# Prerequisites validation
# Checks for required tools and basic AWS CLI installation

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.env" 2>/dev/null || true

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

test_aws_cli() {
    echo ""
    log_info "Testing AWS CLI installation..."

    if command -v aws &> /dev/null; then
        local version=$(aws --version 2>&1)
        log_success "AWS CLI is installed: $version"
        return 0
    else
        log_fail "AWS CLI is not installed"
        return 1
    fi
}

test_eb_cli() {
    echo ""
    log_info "Testing EB CLI installation (optional)..."

    if command -v eb &> /dev/null; then
        local version=$(eb --version 2>&1)
        log_success "EB CLI is installed: $version"
        return 0
    else
        log_warn "EB CLI is not installed (recommended for deployment)"
        echo "  Install with: pip install awsebcli"
        return 0
    fi
}

test_jq() {
    echo ""
    log_info "Testing jq installation (optional)..."

    if command -v jq &> /dev/null; then
        local version=$(jq --version 2>&1)
        log_success "jq is installed: $version"
        return 0
    else
        log_warn "jq is not installed (recommended)"
        echo "  Install with: sudo apt-get install jq  # or brew install jq"
        return 0
    fi
}

# Run all prerequisite checks
test_aws_cli || exit 1
test_eb_cli
test_jq
