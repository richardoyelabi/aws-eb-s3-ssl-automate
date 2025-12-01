#!/bin/bash

# AWS permissions validation
# Checks AWS credentials and IAM permissions

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

test_aws_credentials() {
    echo ""
    log_info "Testing AWS credentials..."

    if [ -z "$AWS_PROFILE" ]; then
        log_warn "AWS_PROFILE not set, using default"
        AWS_PROFILE="default"
    fi

    if [ -z "$AWS_REGION" ]; then
        log_warn "AWS_REGION not set, using us-east-1"
        AWS_REGION="us-east-1"
    fi

    if aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
        local account_id=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
        local user_arn=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Arn --output text)
        log_success "AWS credentials are valid"
        echo "  Account ID: $account_id"
        echo "  User/Role: $user_arn"
        echo "  Region: $AWS_REGION"
        echo "  Profile: $AWS_PROFILE"
        return 0
    else
        log_fail "AWS credentials are not valid or not configured"
        echo "  Configure with: aws configure --profile $AWS_PROFILE"
        return 1
    fi
}

test_iam_permissions() {
    echo ""
    log_info "Testing IAM permissions..."

    local required_permissions=(
        "s3:CreateBucket"
        "elasticbeanstalk:CreateApplication"
        "iam:GetRole"
        "acm:ListCertificates"
    )

    local has_errors=false

    # Test S3 permissions
    if aws s3api list-buckets --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
        log_success "S3 permissions OK"
    else
        log_fail "S3 permissions insufficient"
        has_errors=true
    fi

    # Test Elastic Beanstalk permissions
    if aws elasticbeanstalk describe-applications --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
        log_success "Elastic Beanstalk permissions OK"
    else
        log_fail "Elastic Beanstalk permissions insufficient"
        has_errors=true
    fi

    # Test IAM permissions
    if aws iam list-roles --max-items 1 --profile "$AWS_PROFILE" &> /dev/null; then
        log_success "IAM permissions OK"
    else
        log_fail "IAM permissions insufficient"
        has_errors=true
    fi

    # Test ACM permissions
    if aws acm list-certificates --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
        log_success "ACM permissions OK"
    else
        log_fail "ACM permissions insufficient"
        has_errors=true
    fi

    if [ "$has_errors" = true ]; then
        return 1
    fi
    return 0
}

# Run all permission checks
test_aws_credentials || exit 1
test_iam_permissions || exit 1
