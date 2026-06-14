#!/bin/bash

# ACM Certificate Request Utility
# Idempotently ensures an ACM certificate exists for a domain and prints the
# DNS validation records that must be added to the domain's DNS provider.
#
#   - If a certificate already exists for the domain, its DNS validation
#     records and status are displayed (no new certificate is requested).
#   - If none exists, a new certificate is requested (apex + wildcard SAN,
#     DNS validation) and its validation records are displayed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Reuse shared config resolution and the certificate lookup/display helpers
# (find_certificate_by_domain, get_certificate_status,
# display_dns_validation_records, and the log_* helpers).
source "$SCRIPT_DIR/load-infrastructure-config.sh"
source "$SCRIPT_DIR/setup-ssl-certificate.sh"

request_certificate() {
    local domain=$1
    local region=$2

    log_info "Requesting ACM certificate for $domain (and *.$domain)..."

    aws acm request-certificate \
        --domain-name "$domain" \
        --subject-alternative-names "*.$domain" \
        --validation-method DNS \
        --profile "$AWS_PROFILE" \
        --region "$region" \
        --query "CertificateArn" \
        --output text
}

# Poll until ACM has populated the DNS validation records for a freshly
# requested certificate (they are not always available immediately).
wait_for_validation_records() {
    local cert_arn=$1
    local region=$2
    local max_attempts=${3:-12}
    local wait_interval=5

    if [ "${TEST_MODE:-}" = "true" ]; then
        return 0
    fi

    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local record_name=$(aws acm describe-certificate \
            --certificate-arn "$cert_arn" \
            --profile "$AWS_PROFILE" \
            --region "$region" \
            --query "Certificate.DomainValidationOptions[0].ResourceRecord.Name" \
            --output text)

        if [ -n "$record_name" ] && [ "$record_name" != "None" ]; then
            return 0
        fi

        attempt=$((attempt + 1))
        sleep $wait_interval
    done

    log_warn "DNS validation records were not available yet; re-run this script in a moment to see them"
    return 0
}

show_usage() {
    cat <<EOF
Usage: $0 [DOMAIN] [OPTIONS]

Ensure an ACM certificate exists for a domain and print the DNS validation
records to add at your DNS provider.

  - If a certificate already exists for the domain, its validation records
    and status are shown (no new certificate is requested).
  - If none exists, a new certificate is requested and its validation
    records are shown.

Arguments:
  DOMAIN              Domain to use (defaults to DOMAIN_NAME from config)

Options:
  --config FILE       Use a specific configuration file
  --env NAME          Use config.NAME.env from the repo root
  -h, --help          Show this help message

Examples:

  # Use DOMAIN_NAME from config.env
  $0

  # Request/show for an explicit domain
  $0 example.com

  # Use a named environment's config
  $0 --env staging

After adding the displayed CNAME record at your DNS provider, AWS validates
the certificate (usually within 5-30 minutes). If your domain is hosted in
Route 53, you can add the record with ./scripts/setup-route53-dns.sh. Once
the certificate is ISSUED, run ./setup-eb-environment.sh.
EOF
}

main() {
    local domain=""
    local cli_config=""
    local cli_env=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --config)
                cli_config="$2"
                shift 2
                ;;
            --env)
                cli_env="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                return 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                return 1
                ;;
            *)
                domain="$1"
                shift
                ;;
        esac
    done

    # Load configuration. Use strict loading when a file was explicitly named;
    # otherwise load config.env if present but continue without it (so an
    # explicit DOMAIN argument or a pre-set environment still works).
    if [ -n "$cli_config" ] || [ -n "$cli_env" ]; then
        if ! infrastructure_config_load "$REPO_ROOT" "$cli_config" "$cli_env"; then
            return 1
        fi
    else
        infrastructure_config_load_optional "$REPO_ROOT"
    fi

    AWS_PROFILE="${AWS_PROFILE:-default}"
    AWS_REGION="${AWS_REGION:-us-east-1}"

    if [ -z "$domain" ]; then
        domain="${DOMAIN_NAME:-}"
    fi

    if [ -z "$domain" ]; then
        log_error "No domain provided. Pass one as an argument or set DOMAIN_NAME in your config."
        show_usage
        return 1
    fi

    local cert_arn=$(find_certificate_by_domain "$domain" "$AWS_REGION")

    if [ -n "$cert_arn" ] && [ "$cert_arn" != "None" ]; then
        log_info "Found existing certificate: $cert_arn"
        display_dns_validation_records "$cert_arn" "$AWS_REGION"
        local status=$(get_certificate_status "$cert_arn" "$AWS_REGION")
        log_info "Certificate status: $status"
        if [ "$status" = "ISSUED" ]; then
            log_info "Certificate is already issued — no DNS action needed."
        fi
    else
        log_info "No certificate found for $domain — requesting a new one..."
        cert_arn=$(request_certificate "$domain" "$AWS_REGION")
        log_info "Certificate requested: $cert_arn"
        wait_for_validation_records "$cert_arn" "$AWS_REGION"
        display_dns_validation_records "$cert_arn" "$AWS_REGION"
    fi

    echo ""
    log_info "Add the CNAME record above at your DNS provider."
    log_info "If your domain is in Route 53, you can use ./scripts/setup-route53-dns.sh"
    log_info "Once the certificate is ISSUED, run ./setup-eb-environment.sh"

    return 0
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
