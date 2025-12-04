#!/bin/bash

# ACM Certificate Setup Module
# Validates or helps create SSL certificate in AWS Certificate Manager

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

find_certificate_by_domain() {
    local domain=$1
    local region=$2

    log_info "Searching for ACM certificate for domain: $domain"

    local cert_arn=$(aws acm list-certificates \
        --profile "$AWS_PROFILE" \
        --region "$region" \
        --query "CertificateSummaryList[?DomainName=='$domain'].CertificateArn | [0]" \
        --output text)

    if [ "$cert_arn" = "None" ] || [ -z "$cert_arn" ]; then
        # Try wildcard domain
        local wildcard_domain="*.$domain"
        cert_arn=$(aws acm list-certificates \
            --profile "$AWS_PROFILE" \
            --region "$region" \
            --query "CertificateSummaryList[?DomainName=='$wildcard_domain'].CertificateArn | [0]" \
            --output text)
    fi

    echo "$cert_arn"
}

get_certificate_status() {
    local cert_arn=$1
    local region=$2

    aws acm describe-certificate \
        --certificate-arn "$cert_arn" \
        --profile "$AWS_PROFILE" \
        --region "$region" \
        --query "Certificate.Status" \
        --output text
}

display_dns_validation_records() {
    local cert_arn=$1
    local region=$2

    log_info "Fetching DNS validation records..."
    
    local validation_records=$(aws acm describe-certificate \
        --certificate-arn "$cert_arn" \
        --profile "$AWS_PROFILE" \
        --region "$region" \
        --query "Certificate.DomainValidationOptions" \
        --output json)

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  DNS Validation Records Required"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Add the following DNS records to your domain's DNS provider:"
    echo ""
    
    if command -v jq &> /dev/null; then
        echo "$validation_records" | jq -r '.[] | 
            "\nDomain: \(.DomainName)\n" +
            "Record Type: \(.ResourceRecord.Type)\n" +
            "Record Name: \(.ResourceRecord.Name)\n" +
            "Record Value: \(.ResourceRecord.Value)\n" +
            "Status: \(.ValidationStatus)\n" +
            "---"'
    else
        echo "$validation_records"
        echo ""
        log_warn "Install 'jq' for better formatted output"
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

wait_for_certificate_validation() {
    local cert_arn=$1
    local region=$2
    local max_attempts=${3:-60}  # Default 60 attempts = 30 minutes
    local wait_interval=30  # 30 seconds between checks
    
    # Skip wait loop in test mode
    if [ "$TEST_MODE" = "true" ]; then
        log_info "Skipping certificate validation wait in test mode"
        return 0
    fi
    
    log_info "Polling for certificate validation..."
    log_info "This may take 5-30 minutes. Checking every $wait_interval seconds..."
    echo ""
    
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local status=$(get_certificate_status "$cert_arn" "$region")
        
        if [ "$status" = "ISSUED" ]; then
            echo ""
            log_info "Certificate has been successfully validated and issued!"
            return 0
        elif [ "$status" = "FAILED" ]; then
            echo ""
            log_error "Certificate validation failed"
            return 1
        fi
        
        # Show progress
        attempt=$((attempt + 1))
        local elapsed=$((attempt * wait_interval))
        echo -ne "\r[$(date +'%H:%M:%S')] Status: $status | Elapsed: ${elapsed}s | Attempt: $attempt/$max_attempts"
        
        sleep $wait_interval
    done
    
    echo ""
    log_warn "Timeout waiting for certificate validation after $((max_attempts * wait_interval)) seconds"
    return 1
}

validate_certificate() {
    local cert_arn=$1
    local region=$2

    log_info "Validating certificate: $cert_arn"

    local cert_status=$(get_certificate_status "$cert_arn" "$region")

    if [ "$cert_status" = "ISSUED" ]; then
        log_info "Certificate is valid and issued"
        return 0
    elif [ "$cert_status" = "PENDING_VALIDATION" ]; then
        log_warn "Certificate is pending validation (Status: $cert_status)"
        
        # Display DNS validation records
        display_dns_validation_records "$cert_arn" "$region"
        
        # Skip interactive prompt in test mode
        if [ "$TEST_MODE" = "true" ]; then
            log_info "Skipping interactive prompt in test mode"
            return 1
        fi
        
        echo ""
        echo "What would you like to do?"
        echo "  1) Wait for validation (poll every 30 seconds)"
        echo "  2) Exit and continue later (after adding DNS records)"
        echo "  3) Skip SSL configuration for now"
        echo ""
        read -p "Enter your choice (1-3): " choice
        
        case $choice in
            1)
                echo ""
                log_info "Waiting for certificate validation..."
                if wait_for_certificate_validation "$cert_arn" "$region" 60; then
                    return 0
                else
                    log_error "Certificate validation failed or timed out"
                    return 1
                fi
                ;;
            2)
                echo ""
                log_info "Please add the DNS records shown above to your DNS provider"
                log_info "After adding the records, wait a few minutes and re-run this script"
                exit 0
                ;;
            3)
                echo ""
                log_warn "Skipping SSL configuration"
                log_warn "You can configure SSL later using the AWS console or by re-running this script"
                exit 0
                ;;
            *)
                log_error "Invalid choice"
                return 1
                ;;
        esac
    else
        log_error "Certificate status is: $cert_status (expected: ISSUED)"
        log_error "Please check the certificate in AWS Certificate Manager console"
        return 1
    fi
}

request_certificate_instructions() {
    local domain=$1
    local region=$2

    cat <<EOF

${YELLOW}No valid ACM certificate found for domain: $domain${NC}

To request a new certificate, run:

  aws acm request-certificate \\
    --domain-name $domain \\
    --subject-alternative-names "*.$domain" \\
    --validation-method DNS \\
    --profile $AWS_PROFILE \\
    --region $region

After requesting the certificate:
1. You will receive DNS validation records
2. Add these records to your DNS provider
3. Wait for AWS to validate (usually takes 5-30 minutes)
4. Re-run this script once the certificate is ISSUED

Alternatively, if you have an existing certificate:
1. Import it using: aws acm import-certificate
2. Set ACM_CERTIFICATE_ARN in config.env
3. Re-run this script

EOF
}

main() {
    log_info "Starting SSL certificate validation..."

    local cert_arn="$ACM_CERTIFICATE_ARN"

    # If no ARN provided, search by domain
    if [ -z "$cert_arn" ] || [ "$cert_arn" = "None" ]; then
        cert_arn=$(find_certificate_by_domain "$DOMAIN_NAME" "$AWS_REGION")
    fi

    if [ -z "$cert_arn" ] || [ "$cert_arn" = "None" ]; then
        log_error "No certificate found for domain: $DOMAIN_NAME"
        request_certificate_instructions "$DOMAIN_NAME" "$AWS_REGION"
        exit 1
    fi

    log_info "Found certificate: $cert_arn"

    if validate_certificate "$cert_arn" "$AWS_REGION"; then
        # Export for use in other scripts
        export VALIDATED_ACM_CERT_ARN="$cert_arn"
        echo "$cert_arn" > /tmp/acm-cert-arn.txt
        
        log_info "SSL certificate validation completed successfully"
        echo ""
        echo "Certificate ARN: $cert_arn"
        return 0
    else
        log_error "Certificate validation failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

