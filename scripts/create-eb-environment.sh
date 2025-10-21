#!/bin/bash

# Elastic Beanstalk Environment Creation Module
# Creates EB application and environment with proper configuration

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

create_application() {
    local app_name=$1

    if aws elasticbeanstalk describe-applications \
        --application-names "$app_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null | grep -q "$app_name"; then
        log_warn "Application $app_name already exists"
        return 0
    fi

    log_info "Creating Elastic Beanstalk application: $app_name"
    
    aws elasticbeanstalk create-application \
        --application-name "$app_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"

    log_info "Application created successfully"
}

get_solution_stack_name() {
    local platform=$1

    log_info "Finding solution stack for platform: $platform"

    # Try to find exact match or similar
    local stack_name=$(aws elasticbeanstalk list-available-solution-stacks \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "SolutionStacks[?contains(@, '$platform')] | [0]" \
        --output text)

    if [ -z "$stack_name" ] || [ "$stack_name" = "None" ]; then
        log_error "Could not find solution stack matching: $platform"
        log_info "Available platforms:"
        aws elasticbeanstalk list-available-solution-stacks \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "SolutionStacks[*]" \
            --output table | head -20
        exit 1
    fi

    echo "$stack_name"
}

create_environment_options() {
    local cert_arn=$1
    local instance_profile=$2

    cat > /tmp/eb-options.json <<EOF
[
  {
    "Namespace": "aws:autoscaling:launchconfiguration",
    "OptionName": "IamInstanceProfile",
    "Value": "$instance_profile"
  },
  {
    "Namespace": "aws:autoscaling:launchconfiguration",
    "OptionName": "InstanceType",
    "Value": "$INSTANCE_TYPE"
  },
  {
    "Namespace": "aws:autoscaling:asg",
    "OptionName": "MinSize",
    "Value": "$MIN_INSTANCES"
  },
  {
    "Namespace": "aws:autoscaling:asg",
    "OptionName": "MaxSize",
    "Value": "$MAX_INSTANCES"
  },
  {
    "Namespace": "aws:elasticbeanstalk:environment",
    "OptionName": "EnvironmentType",
    "Value": "LoadBalanced"
  },
  {
    "Namespace": "aws:elasticbeanstalk:environment",
    "OptionName": "LoadBalancerType",
    "Value": "$LB_TYPE"
  },
  {
    "Namespace": "aws:elasticbeanstalk:environment:process:default",
    "OptionName": "HealthCheckPath",
    "Value": "$HEALTH_CHECK_PATH"
  },
  {
    "Namespace": "aws:elasticbeanstalk:application:environment",
    "OptionName": "STATIC_ASSETS_BUCKET",
    "Value": "$STATIC_ASSETS_BUCKET"
  },
  {
    "Namespace": "aws:elasticbeanstalk:application:environment",
    "OptionName": "UPLOADS_BUCKET",
    "Value": "$UPLOADS_BUCKET"
  },
  {
    "Namespace": "aws:elasticbeanstalk:application:environment",
    "OptionName": "AWS_REGION",
    "Value": "$AWS_REGION"
  }
]
EOF
}

create_environment() {
    local app_name=$1
    local env_name=$2
    local platform=$3
    local cert_arn=$4
    local instance_profile=$5

    if aws elasticbeanstalk describe-environments \
        --application-name "$app_name" \
        --environment-names "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" 2>/dev/null | grep -q "$env_name"; then
        log_warn "Environment $env_name already exists"
        return 0
    fi

    log_info "Creating Elastic Beanstalk environment: $env_name"

    local solution_stack=$(get_solution_stack_name "$platform")
    log_info "Using solution stack: $solution_stack"

    create_environment_options "$cert_arn" "$instance_profile"

    aws elasticbeanstalk create-environment \
        --application-name "$app_name" \
        --environment-name "$env_name" \
        --solution-stack-name "$solution_stack" \
        --option-settings file:///tmp/eb-options.json \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"

    log_info "Environment creation initiated. This may take several minutes..."
    
    # Wait for environment to be ready
    log_info "Waiting for environment to become ready..."
    aws elasticbeanstalk wait environment-exists \
        --application-name "$app_name" \
        --environment-names "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"

    log_info "Waiting for environment health to stabilize..."
    local max_wait=600  # 10 minutes
    local elapsed=0
    local sleep_interval=30

    while [ $elapsed -lt $max_wait ]; do
        local status=$(aws elasticbeanstalk describe-environments \
            --application-name "$app_name" \
            --environment-names "$env_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "Environments[0].Status" \
            --output text)

        if [ "$status" = "Ready" ]; then
            log_info "Environment is ready!"
            break
        elif [ "$status" = "Terminated" ] || [ "$status" = "Terminating" ]; then
            log_error "Environment creation failed with status: $status"
            exit 1
        fi

        log_info "Current status: $status (waiting...)"
        sleep $sleep_interval
        elapsed=$((elapsed + sleep_interval))
    done

    rm -f /tmp/eb-options.json
}

get_environment_url() {
    local app_name=$1
    local env_name=$2

    local url=$(aws elasticbeanstalk describe-environments \
        --application-name "$app_name" \
        --environment-names "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "Environments[0].CNAME" \
        --output text)

    echo "$url"
}

main() {
    log_info "Starting Elastic Beanstalk environment creation..."

    # Read certificate ARN
    local cert_arn
    if [ -f /tmp/acm-cert-arn.txt ]; then
        cert_arn=$(cat /tmp/acm-cert-arn.txt)
    else
        cert_arn="$ACM_CERTIFICATE_ARN"
    fi

    # Read instance profile
    local instance_profile
    if [ -f /tmp/eb-instance-profile.txt ]; then
        instance_profile=$(cat /tmp/eb-instance-profile.txt)
    else
        instance_profile="aws-elasticbeanstalk-ec2-role"
    fi

    # Create application
    create_application "$APP_NAME"

    # Create environment
    create_environment "$APP_NAME" "$ENV_NAME" "$EB_PLATFORM" "$cert_arn" "$instance_profile"

    # Get environment URL
    local env_url=$(get_environment_url "$APP_NAME" "$ENV_NAME")
    
    export EB_ENVIRONMENT_URL="$env_url"
    echo "$env_url" > /tmp/eb-env-url.txt

    log_info "Elastic Beanstalk environment creation completed successfully"
    echo ""
    echo "Application: $APP_NAME"
    echo "Environment: $ENV_NAME"
    echo "URL: http://$env_url"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" -eq "${0}" ]; then
    main "$@"
fi

