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
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
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
        --query "SolutionStacks[?contains(@, \`$platform\`)] | [0]" \
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

compare_configuration() {
    local current_config=$1
    local namespace=$2
    local option_name=$3
    local desired_value=$4
    
    local current_value=$(echo "$current_config" | grep -B2 "\"OptionName\": \"$option_name\"" | grep "\"Namespace\": \"$namespace\"" -A2 | grep "\"Value\"" | cut -d'"' -f4 || echo "")
    
    if [ "$current_value" != "$desired_value" ]; then
        echo "different"
    else
        echo "same"
    fi
}

update_environment_configuration() {
    local app_name=$1
    local env_name=$2
    local cert_arn=$3
    local instance_profile=$4
    
    log_info "Checking if environment configuration needs update..."
    
    # Get current configuration
    local current_config=$(aws elasticbeanstalk describe-configuration-settings \
        --application-name "$app_name" \
        --environment-name "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'ConfigurationSettings[0].OptionSettings' \
        --output json)
    
    # Check key configuration values
    local needs_update=false
    local changes=()
    
    # Check instance type
    if [ "$(compare_configuration "$current_config" "aws:autoscaling:launchconfiguration" "InstanceType" "$INSTANCE_TYPE")" = "different" ]; then
        needs_update=true
        changes+=("Instance Type")
    fi
    
    # Check min instances
    if [ "$(compare_configuration "$current_config" "aws:autoscaling:asg" "MinSize" "$MIN_INSTANCES")" = "different" ]; then
        needs_update=true
        changes+=("Min Instances")
    fi
    
    # Check max instances
    if [ "$(compare_configuration "$current_config" "aws:autoscaling:asg" "MaxSize" "$MAX_INSTANCES")" = "different" ]; then
        needs_update=true
        changes+=("Max Instances")
    fi
    
    # Check environment variables
    if [ "$(compare_configuration "$current_config" "aws:elasticbeanstalk:application:environment" "STATIC_ASSETS_BUCKET" "$STATIC_ASSETS_BUCKET")" = "different" ]; then
        needs_update=true
        changes+=("STATIC_ASSETS_BUCKET env var")
    fi
    
    if [ "$(compare_configuration "$current_config" "aws:elasticbeanstalk:application:environment" "UPLOADS_BUCKET" "$UPLOADS_BUCKET")" = "different" ]; then
        needs_update=true
        changes+=("UPLOADS_BUCKET env var")
    fi
    
    if [ "$needs_update" = false ]; then
        log_info "Environment configuration is up to date"
        return 0
    fi
    
    # Prompt user for confirmation
    log_warn "Environment configuration has changed. The following will be updated:"
    for change in "${changes[@]}"; do
        echo "  - $change"
    done
    echo ""
    log_warn "Updating the environment may cause brief downtime or service interruption."
    
    # Skip prompt in test mode
    if [ "$TEST_MODE" = "true" ]; then
        log_info "Skipping environment update"
        return 0
    fi
    
    read -p "Do you want to update the environment? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Skipping environment update"
        return 0
    fi
    
    log_info "Updating environment configuration..."
    create_environment_options "$cert_arn" "$instance_profile"
    
    aws elasticbeanstalk update-environment \
        --application-name "$app_name" \
        --environment-name "$env_name" \
        --option-settings file:///tmp/eb-options.json \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    
    # Wait for environment update (skip in test mode)
    if [ "$TEST_MODE" != "true" ]; then
        log_info "Waiting for environment update to complete..."
        sleep 30
    fi
    
    rm -f /tmp/eb-options.json
    log_info "Environment configuration updated successfully"
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
        
        # Check if configuration needs update
        update_environment_configuration "$app_name" "$env_name" "$cert_arn" "$instance_profile"
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

    log_info "Environment creation initiated. This may take 5-10 minutes..."
    
    # Skip wait loop in test mode
    if [ "$TEST_MODE" = "true" ]; then
        log_info "Skipping wait loop in test mode"
        rm -f /tmp/eb-options.json
        return 0
    fi
    
    # Wait for environment to be ready with extended timeout
    log_info "Waiting for environment to become ready..."
    local max_wait=900  # 15 minutes
    local elapsed=0
    local sleep_interval=20
    local last_status=""

    while [ $elapsed -lt $max_wait ]; do
        # Get both status and health for better visibility
        local env_info=$(aws elasticbeanstalk describe-environments \
            --application-name "$app_name" \
            --environment-names "$env_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "Environments[0].[Status,Health]" \
            --output text 2>/dev/null)
        
        local status=$(echo "$env_info" | awk '{print $1}')
        local health=$(echo "$env_info" | awk '{print $2}')

        # Check for terminal states
        if [ "$status" = "Ready" ]; then
            log_info "Environment is ready with health: $health"
            
            # Additional health check for production readiness
            if [ "$health" = "Green" ] || [ "$health" = "Yellow" ]; then
                log_info "Environment health is acceptable: $health"
                break
            else
                log_warn "Environment is Ready but health is: $health"
                log_info "Waiting for health to stabilize..."
            fi
        elif [ "$status" = "Terminated" ] || [ "$status" = "Terminating" ]; then
            log_error "Environment creation failed with status: $status"
            log_error "Check AWS Console for detailed error messages"
            exit 1
        fi

        # Show progress only when status changes to reduce noise
        if [ "$status" != "$last_status" ]; then
            log_info "Status: $status | Health: $health | Elapsed: ${elapsed}s / ${max_wait}s"
            last_status="$status"
        elif [ $((elapsed % 60)) -eq 0 ]; then
            # Show periodic update every minute
            log_info "Still waiting... Status: $status | Health: $health | Elapsed: ${elapsed}s / ${max_wait}s"
        fi

        sleep $sleep_interval
        elapsed=$((elapsed + sleep_interval))
    done

    # Check if we timed out
    if [ $elapsed -ge $max_wait ]; then
        log_warn "Wait timeout reached (${max_wait}s). Environment may still be launching."
        log_warn "Check environment status with: aws elasticbeanstalk describe-environments --application-name $app_name --environment-names $env_name"
        log_warn "The environment may complete successfully - verify in AWS Console"
    fi

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
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

