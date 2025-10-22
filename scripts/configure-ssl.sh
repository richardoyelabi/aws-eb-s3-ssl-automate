#!/bin/bash

# Load Balancer SSL Configuration Module
# Configures HTTPS listener with ACM certificate and optional HTTP redirect

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

configure_https_listener() {
    local app_name=$1
    local env_name=$2
    local cert_arn=$3

    log_info "Configuring HTTPS listener for environment: $env_name"

    # Check current configuration
    local current_config=$(aws elasticbeanstalk describe-configuration-settings \
        --application-name "$app_name" \
        --environment-name "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'ConfigurationSettings[0].OptionSettings' \
        --output json)
    
    # Extract current HTTPS settings
    local current_protocol=$(echo "$current_config" | grep -A2 '"Namespace": "aws:elbv2:listener:443"' | grep '"OptionName": "Protocol"' -A1 | grep '"Value"' | cut -d'"' -f4 || echo "")
    local current_cert=$(echo "$current_config" | grep -A2 '"Namespace": "aws:elbv2:listener:443"' | grep '"OptionName": "SSLCertificateArns"' -A1 | grep '"Value"' | cut -d'"' -f4 || echo "")
    local current_ssl_policy=$(echo "$current_config" | grep -A2 '"Namespace": "aws:elbv2:listener:443"' | grep '"OptionName": "SSLPolicy"' -A1 | grep '"Value"' | cut -d'"' -f4 || echo "")
    
    # Check if configuration needs update
    local needs_update=false
    if [ "$current_protocol" != "HTTPS" ] || [ "$current_cert" != "$cert_arn" ] || [ "$current_ssl_policy" != "$SSL_POLICY" ]; then
        needs_update=true
    fi
    
    if [ "$needs_update" = false ]; then
        log_info "HTTPS listener already configured correctly, skipping update"
        return 0
    fi
    
    log_info "HTTPS configuration needs update"
    if [ -n "$current_protocol" ]; then
        log_info "Current: Protocol=$current_protocol, Cert=$current_cert, SSLPolicy=$current_ssl_policy"
    fi
    log_info "Desired: Protocol=HTTPS, Cert=$cert_arn, SSLPolicy=$SSL_POLICY"

    # Create option settings for HTTPS
    cat > /tmp/https-options.json <<EOF
[
  {
    "Namespace": "aws:elbv2:listener:443",
    "OptionName": "Protocol",
    "Value": "HTTPS"
  },
  {
    "Namespace": "aws:elbv2:listener:443",
    "OptionName": "SSLCertificateArns",
    "Value": "$cert_arn"
  },
  {
    "Namespace": "aws:elbv2:listener:443",
    "OptionName": "SSLPolicy",
    "Value": "$SSL_POLICY"
  }
]
EOF

    log_info "Updating environment with HTTPS configuration..."
    aws elasticbeanstalk update-environment \
        --application-name "$app_name" \
        --environment-name "$env_name" \
        --option-settings file:///tmp/https-options.json \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"

    rm -f /tmp/https-options.json
    log_info "HTTPS listener configured successfully"
}

configure_http_redirect() {
    local app_name=$1
    local env_name=$2

    if [ "$ENABLE_HTTPS_REDIRECT" != "true" ]; then
        log_info "HTTP to HTTPS redirect is disabled"
        return 0
    fi

    log_info "Configuring HTTP to HTTPS redirect..."

    # Get the load balancer ARN
    log_info "Finding load balancer for environment..."
    local lb_name=$(aws elasticbeanstalk describe-environment-resources \
        --environment-name "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "EnvironmentResources.LoadBalancers[0].Name" \
        --output text)

    if [ -z "$lb_name" ] || [ "$lb_name" = "None" ]; then
        log_warn "Could not find load balancer. Skipping HTTP redirect configuration."
        return 0
    fi

    log_info "Load balancer: $lb_name"

    # Get full load balancer ARN
    local lb_arn=$(aws elbv2 describe-load-balancers \
        --names "$lb_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "LoadBalancers[0].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")

    if [ -z "$lb_arn" ]; then
        log_warn "Could not get load balancer ARN. Skipping redirect configuration."
        return 0
    fi

    # Get HTTP listener ARN
    local listener_arn=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$lb_arn" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "Listeners[?Port==\`80\`].ListenerArn | [0]" \
        --output text 2>/dev/null || echo "")

    if [ -z "$listener_arn" ] || [ "$listener_arn" = "None" ]; then
        log_warn "HTTP listener not found. May need to wait for environment to fully initialize."
        return 0
    fi

    log_info "Configuring redirect rule on HTTP listener..."
    
    # Modify HTTP listener to redirect to HTTPS
    aws elbv2 modify-listener \
        --listener-arn "$listener_arn" \
        --default-actions \
            "Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"

    log_info "HTTP to HTTPS redirect configured successfully"
}

verify_ssl_configuration() {
    local env_url=$1

    log_info "Verifying SSL configuration..."
    
    # Wait a moment for changes to propagate
    sleep 5

    # Try to check if HTTPS is responding
    if command -v curl &> /dev/null; then
        log_info "Testing HTTPS endpoint..."
        if curl -sSf -k "https://$env_url" -o /dev/null 2>&1; then
            log_info "HTTPS endpoint is responding"
        else
            log_warn "HTTPS endpoint may not be fully configured yet. This is normal immediately after creation."
        fi
    else
        log_warn "curl not available, skipping HTTPS verification"
    fi
}

main() {
    log_info "Starting SSL configuration..."

    # Read certificate ARN
    local cert_arn
    if [ -f /tmp/acm-cert-arn.txt ]; then
        cert_arn=$(cat /tmp/acm-cert-arn.txt)
    else
        cert_arn="$ACM_CERTIFICATE_ARN"
    fi

    if [ -z "$cert_arn" ]; then
        log_error "No certificate ARN found. SSL configuration cannot proceed."
        exit 1
    fi

    # Configure HTTPS listener
    configure_https_listener "$APP_NAME" "$ENV_NAME" "$cert_arn"

    # Wait for update to complete
    log_info "Waiting for environment update to complete..."
    sleep 30

    # Configure HTTP redirect
    configure_http_redirect "$APP_NAME" "$ENV_NAME"

    # Read environment URL
    local env_url
    if [ -f /tmp/eb-env-url.txt ]; then
        env_url=$(cat /tmp/eb-env-url.txt)
    fi

    # Verify configuration
    if [ -n "$env_url" ]; then
        verify_ssl_configuration "$env_url"
    fi

    log_info "SSL configuration completed successfully"
    echo ""
    echo "HTTPS endpoint will be available at: https://$env_url"
    echo "Note: You may need to configure your domain DNS to point to this endpoint"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

