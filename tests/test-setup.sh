#!/bin/bash

# Validation and Testing Script
# Validates configuration and checks AWS prerequisites before running setup

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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

check_existing_resources() {
    echo ""
    log_info "Checking for existing resources..."
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"
    
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

run_all_tests() {
    local failed_tests=0
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  AWS Elastic Beanstalk Setup - Validation Tests${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    test_aws_cli || ((failed_tests++))
    test_eb_cli
    test_jq
    test_aws_credentials || ((failed_tests++))
    test_iam_permissions || ((failed_tests++))
    validate_config_file || ((failed_tests++))
    validate_bucket_names || ((failed_tests++))
    check_existing_resources
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    if [ $failed_tests -eq 0 ]; then
        echo -e "${GREEN}  All validation tests passed!${NC}"
        echo -e "${GREEN}  You can proceed with: ./setup-eb-environment.sh${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        return 0
    else
        echo -e "${RED}  $failed_tests test(s) failed${NC}"
        echo -e "${RED}  Please fix the errors before running setup${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        return 1
    fi
}

main() {
    run_all_tests
}

# Run main function
main "$@"

