#!/bin/bash

# Main AWS Elastic Beanstalk Environment Setup Script
# Orchestrates the creation of EB environment with S3 buckets and SSL configuration

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/load-infrastructure-config.sh"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_section() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_prerequisites() {
    log_section "Checking Prerequisites"

    local missing_tools=()

    # Check for required tools
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi

    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed (recommended but not required)"
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        exit 1
    fi

    # Check AWS credentials
    log_info "Verifying AWS credentials..."
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        echo ""
        echo "Please configure AWS credentials:"
        echo "  aws configure --profile $AWS_PROFILE"
        exit 1
    fi

    local account_id=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Arn --output text)
    
    log_info "AWS Account: $account_id"
    log_info "User/Role: $user_arn"
    log_info "Region: $AWS_REGION"
    log_info "Profile: $AWS_PROFILE"
}

load_configuration() {
    local cli_config="${1:-}"
    local cli_env="${2:-}"

    log_section "Loading Configuration"

    if ! infrastructure_config_load "$SCRIPT_DIR" "$cli_config" "$cli_env"; then
        exit 1
    fi

    log_info "Loading configuration from: $INFRA_CONFIG_PATH"

    # Validate required configuration
    local required_vars=(
        "AWS_REGION"
        "AWS_PROFILE"
        "APP_NAME"
        "ENV_NAME"
        "EB_PLATFORM"
        "DOMAIN_NAME"
        "STATIC_ASSETS_BUCKET"
        "UPLOADS_BUCKET"
    )

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Required configuration variable not set: $var"
            exit 1
        fi
    done

    log_info "Configuration loaded successfully"
    echo "  Application: $APP_NAME"
    echo "  Environment: $ENV_NAME"
    echo "  Platform: $EB_PLATFORM"
    echo "  Domain: $DOMAIN_NAME"
}

setup_s3_buckets() {
    log_section "Setting Up S3 Buckets"
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/setup-s3-buckets.sh"
    main
}

setup_ssl_certificate() {
    log_section "Validating SSL Certificate"
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/setup-ssl-certificate.sh"
    main
}

setup_iam_roles() {
    log_section "Setting Up IAM Roles"
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/setup-iam-roles.sh"
    main
}

create_eb_environment() {
    log_section "Creating Elastic Beanstalk Environment"
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/create-eb-environment.sh"
    main
}

setup_rds_database() {
    log_section "Setting Up RDS Database"
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/setup-rds-database.sh"
    main
}

configure_ssl() {
    log_section "Configuring SSL on Load Balancer"
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/configure-ssl.sh"
    main
}

configure_custom_domain() {
    log_section "Configuring Custom Domain"
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/configure-custom-domain.sh"
    main
}

generate_instructions() {
    log_section "Setup Complete!"
    
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/generate-deployment-instructions.sh"
    main
}

cleanup_temp_files() {
    # Clean up environment-specific temp directory
    if [ -n "${INFRA_TMP_DIR:-}" ] && [ -d "$INFRA_TMP_DIR" ]; then
        rm -rf "$INFRA_TMP_DIR"
    fi
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

AWS Elastic Beanstalk Environment Setup Script

Environment selection (same order everywhere): INFRA_CONFIG, then --config, then
--env or INFRA_ENV (config.NAME.env), then default config.env.

OPTIONS:
    -h, --help              Show this help message
    -c, --config FILE       Use explicit configuration file path
    -e, --env NAME          Use config.NAME.env in the project root
    --skip-ssl              Skip SSL certificate validation and configuration
    --dry-run               Validate configuration without making changes
    -y, --yes               Non-interactive: no confirmation prompts; apply EB
                            config updates; wait for ACM validation when pending
                            (also enabled when environment variable CI=true)

EXAMPLES:
    # Standard setup
    ./setup-eb-environment.sh

    # Use custom config file
    ./setup-eb-environment.sh --config my-config.env

    # Use per-environment file (config.staging.env)
    ./setup-eb-environment.sh --env staging

    # Validate configuration only
    ./setup-eb-environment.sh --dry-run

    # Unattended / CI (no prompts, no AWS CLI pager on JSON output)
    ./setup-eb-environment.sh --yes

PREREQUISITES:
    - AWS CLI installed and configured
    - Valid AWS credentials
    - ACM certificate for your domain (or request one during setup)

For more information, see README.md

EOF
}

main() {
    local skip_ssl=false
    local dry_run=false
    local assume_yes=false
    local cli_config=""
    local cli_env=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--config)
                cli_config="$2"
                shift 2
                ;;
            -e|--env)
                cli_env="$2"
                shift 2
                ;;
            --skip-ssl)
                skip_ssl=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -y|--yes)
                assume_yes=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Avoid AWS CLI v2 paging JSON into less (blocks unattended runs)
    export AWS_PAGER=""

    if [ "$assume_yes" = true ] || [ "${CI:-}" = "true" ]; then
        export NON_INTERACTIVE=true
    fi

    # Display banner
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║     AWS Elastic Beanstalk Environment Setup Automation        ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    load_configuration "$cli_config" "$cli_env"

    # Create environment-specific temp directory to avoid conflicts
    # when setting up multiple environments concurrently
    export INFRA_TMP_DIR="/tmp/${APP_NAME}-${ENV_NAME}-infra"
    mkdir -p "$INFRA_TMP_DIR"

    check_prerequisites

    if [ "$dry_run" = true ]; then
        log_info "Dry-run mode: Configuration validation successful"
        exit 0
    fi

    # Confirm before proceeding
    echo ""
    log_warn "This script will create AWS resources that may incur costs."
    if [ "${NON_INTERACTIVE:-}" = "true" ]; then
        log_info "Non-interactive mode: continuing without confirmation (--yes, -y, or CI=true)"
    else
        read -p "Do you want to continue? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Setup cancelled by user"
            exit 0
        fi
    fi

    # Execute setup steps
    local start_time=$(date +%s)

    setup_s3_buckets

    # Validate SSL Certificate (if custom domain) - can be done before environment creation
    if [ "$skip_ssl" = false ] && [ -n "$CUSTOM_DOMAIN" ]; then
        # Custom domain requires ACM certificate - validate it exists
        setup_ssl_certificate
    fi

    setup_iam_roles
    create_eb_environment
    
    # Setup RDS database - MUST happen after environment creation
    setup_rds_database

    # Configure SSL on Load Balancer - MUST happen after environment creation
    if [ "$skip_ssl" = false ]; then
        if [ -z "$CUSTOM_DOMAIN" ]; then
            log_info "Using AWS automatic SSL for default Elastic Beanstalk domain"
        fi
        # Configure HTTPS listener (with or without custom certificates)
        configure_ssl
    else
        log_warn "Skipping SSL configuration entirely (--skip-ssl flag used)"
    fi

    # Configure custom domain if enabled
    configure_custom_domain

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Generate deployment instructions
    generate_instructions

    log_info "Total setup time: ${duration}s"

    # Cleanup
    cleanup_temp_files

    log_info "Setup script completed successfully!"
}

# Run main function
main "$@"

