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
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

validate_certificate() {
    local cert_arn=$1
    local region=$2

    log_info "Validating certificate: $cert_arn"

    local cert_status=$(aws acm describe-certificate \
        --certificate-arn "$cert_arn" \
        --profile "$AWS_PROFILE" \
        --region "$region" \
        --query "Certificate.Status" \
        --output text)

    if [ "$cert_status" = "ISSUED" ]; then
        log_info "Certificate is valid and issued"
        return 0
    else
        log_error "Certificate status is: $cert_status (expected: ISSUED)"
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
if [ "${BASH_SOURCE[0]}" -eq "${0}" ]; then
    main "$@"
fi

