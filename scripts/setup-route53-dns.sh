#!/bin/bash

# Route 53 DNS Management Module
# Manages Route 53 hosted zones and DNS records

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
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

list_hosted_zones() {
    log_info "Listing Route 53 hosted zones..."
    
    aws route53 list-hosted-zones \
        --profile "$AWS_PROFILE" \
        --query "HostedZones[*].[Name,Id,ResourceRecordSetCount]" \
        --output table
}

find_hosted_zone() {
    local domain=$1
    
    # Try exact match first
    local hosted_zone_id=$(aws route53 list-hosted-zones \
        --profile "$AWS_PROFILE" \
        --query "HostedZones[?Name=='${domain}.'].Id | [0]" \
        --output text 2>/dev/null)
    
    if [ -z "$hosted_zone_id" ] || [ "$hosted_zone_id" = "None" ]; then
        # Try finding parent domain
        local parent_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
        hosted_zone_id=$(aws route53 list-hosted-zones \
            --profile "$AWS_PROFILE" \
            --query "HostedZones[?Name=='${parent_domain}.'].Id | [0]" \
            --output text 2>/dev/null)
    fi
    
    if [ -z "$hosted_zone_id" ] || [ "$hosted_zone_id" = "None" ]; then
        return 1
    fi
    
    # Clean up the hosted zone ID (remove /hostedzone/ prefix)
    hosted_zone_id=$(echo "$hosted_zone_id" | sed 's/\/hostedzone\///')
    echo "$hosted_zone_id"
}

create_hosted_zone() {
    local domain=$1
    
    log_info "Creating Route 53 hosted zone for: $domain"
    
    # Generate unique caller reference
    local caller_ref="eb-ssl-automate-$(date +%s)"
    
    local zone_info=$(aws route53 create-hosted-zone \
        --name "$domain" \
        --caller-reference "$caller_ref" \
        --profile "$AWS_PROFILE" \
        --output json)
    
    local zone_id=$(echo "$zone_info" | grep -o '"Id": "[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\/hostedzone\///')
    local nameservers=$(echo "$zone_info" | grep -o '"NameServers": \[[^]]*\]' | sed 's/"NameServers": \[//;s/\]//')
    
    log_info "Hosted zone created successfully!"
    log_info "Zone ID: $zone_id"
    echo ""
    echo "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo "${CYAN}  Update Your Domain Registrar's Nameservers${NC}"
    echo "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "To complete the DNS setup, update your domain registrar's nameservers to:"
    echo ""
    echo "$nameservers" | sed 's/,/\n/g' | sed 's/"//g' | sed 's/^ */  - /'
    echo ""
    echo "This is done at your domain registrar (GoDaddy, Namecheap, etc.)"
    echo "Nameserver updates can take 24-48 hours to propagate globally."
    echo ""
    echo "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    
    echo "$zone_id"
}

list_dns_records() {
    local hosted_zone_id=$1
    
    log_info "Listing DNS records for hosted zone: $hosted_zone_id"
    
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --profile "$AWS_PROFILE" \
        --query "ResourceRecordSets[*].[Name,Type,TTL,ResourceRecords[0].Value]" \
        --output table
}

check_existing_record() {
    local hosted_zone_id=$1
    local domain=$2
    local record_type=$3
    
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --profile "$AWS_PROFILE" \
        --query "ResourceRecordSets[?Name=='${domain}.' && Type=='$record_type']" \
        --output json 2>/dev/null
}

create_alias_record() {
    local hosted_zone_id=$1
    local domain=$2
    local target_dns=$3
    local target_zone_id=$4
    
    # Check if record already exists
    local existing=$(check_existing_record "$hosted_zone_id" "$domain" "A")
    
    if [ -n "$existing" ] && [ "$existing" != "[]" ]; then
        local current_target=$(echo "$existing" | grep -o '"DNSName": "[^"]*"' | cut -d'"' -f4 | head -1 | sed 's/\.$//')
        local expected_target=$(echo "$target_dns" | sed 's/\.$//')
        
        if [ "$current_target" = "$expected_target" ]; then
            log_info "ALIAS record for $domain already exists and points to $target_dns"
            log_info "Skipping record creation"
            return 0
        else
            log_warn "ALIAS record exists but points to different target: $current_target"
            log_info "Updating to: $target_dns"
        fi
    fi
    
    log_info "Creating/Updating ALIAS record: $domain -> $target_dns"
    
    cat > /tmp/route53-alias-record.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$domain",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$target_zone_id",
          "DNSName": "$target_dns",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF
    
    local change_info=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --change-batch file:///tmp/route53-alias-record.json \
        --profile "$AWS_PROFILE" \
        --output json)
    
    local change_id=$(echo "$change_info" | grep -o '"Id": "[^"]*"' | cut -d'"' -f4)
    
    rm -f /tmp/route53-alias-record.json
    
    log_info "ALIAS record created successfully!"
    log_info "Change ID: $change_id"
}

create_cname_record() {
    local hosted_zone_id=$1
    local domain=$2
    local target_dns=$3
    local ttl=${4:-300}
    
    # Check if record already exists
    local existing=$(check_existing_record "$hosted_zone_id" "$domain" "CNAME")
    
    if [ -n "$existing" ] && [ "$existing" != "[]" ]; then
        local current_target=$(echo "$existing" | grep -o '"Value": "[^"]*"' | cut -d'"' -f4 | head -1)
        
        if [ "$current_target" = "$target_dns" ]; then
            log_info "CNAME record for $domain already exists and points to $target_dns"
            log_info "Skipping record creation"
            return 0
        else
            log_warn "CNAME record exists but points to different target: $current_target"
            log_info "Updating to: $target_dns"
        fi
    fi
    
    log_info "Creating/Updating CNAME record: $domain -> $target_dns"
    
    cat > /tmp/route53-cname-record.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$domain",
        "Type": "CNAME",
        "TTL": $ttl,
        "ResourceRecords": [
          {
            "Value": "$target_dns"
          }
        ]
      }
    }
  ]
}
EOF
    
    local change_info=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --change-batch file:///tmp/route53-cname-record.json \
        --profile "$AWS_PROFILE" \
        --output json)
    
    local change_id=$(echo "$change_info" | grep -o '"Id": "[^"]*"' | cut -d'"' -f4)
    
    rm -f /tmp/route53-cname-record.json
    
    log_info "CNAME record created successfully!"
    log_info "Change ID: $change_id"
}

delete_dns_record() {
    local hosted_zone_id=$1
    local domain=$2
    local record_type=$3
    
    log_info "Deleting $record_type record for: $domain"
    
    # Get current record
    local record_json=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --profile "$AWS_PROFILE" \
        --query "ResourceRecordSets[?Name=='${domain}.' && Type=='$record_type']" \
        --output json | head -1)
    
    if [ -z "$record_json" ] || [ "$record_json" = "[]" ]; then
        log_warn "No $record_type record found for: $domain"
        return 1
    fi
    
    # Create delete change batch
    cat > /tmp/route53-delete-record.json <<EOF
{
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": $record_json
    }
  ]
}
EOF
    
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --change-batch file:///tmp/route53-delete-record.json \
        --profile "$AWS_PROFILE"
    
    rm -f /tmp/route53-delete-record.json
    
    log_info "DNS record deleted successfully"
}

wait_for_dns_propagation() {
    local domain=$1
    local max_wait=${2:-300}
    local sleep_interval=10
    
    # Skip wait loop in test mode
    if [ "$TEST_MODE" = "true" ]; then
        log_info "Skipping DNS propagation wait in test mode"
        return 0
    fi
    
    log_info "Waiting for DNS propagation for: $domain"
    log_info "This may take a few minutes..."
    
    if ! command -v dig &> /dev/null; then
        log_warn "dig command not available, skipping DNS verification"
        return 0
    fi
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local resolved=$(dig +short "$domain" | tail -1)
        
        if [ -n "$resolved" ]; then
            log_info "Domain is now resolving to: $resolved"
            return 0
        fi
        
        echo -ne "\r[$(date +'%H:%M:%S')] Waiting for DNS propagation... Elapsed: ${elapsed}s / ${max_wait}s"
        
        sleep $sleep_interval
        elapsed=$((elapsed + sleep_interval))
    done
    
    echo ""
    log_warn "DNS not propagated within timeout"
    log_info "DNS propagation can take longer in some cases. Check again in a few minutes."
    return 1
}

show_usage() {
    cat <<EOF
Usage: $0 [COMMAND] [OPTIONS]

Route 53 DNS Management Commands:

  list-zones               List all hosted zones
  find-zone DOMAIN         Find hosted zone for a domain
  create-zone DOMAIN       Create a new hosted zone
  list-records ZONE_ID     List DNS records in a zone
  create-alias ZONE_ID DOMAIN TARGET_DNS TARGET_ZONE_ID
                          Create ALIAS record (for root domains)
  create-cname ZONE_ID DOMAIN TARGET_DNS [TTL]
                          Create CNAME record (for subdomains)
  delete-record ZONE_ID DOMAIN TYPE
                          Delete a DNS record
  wait DOMAIN [MAX_WAIT]  Wait for DNS propagation

Examples:

  # List all hosted zones
  $0 list-zones

  # Find hosted zone for domain
  $0 find-zone example.com

  # Create hosted zone
  $0 create-zone example.com

  # List DNS records
  $0 list-records Z1234567890ABC

  # Create ALIAS record (root domain)
  $0 create-alias Z1234567890ABC example.com my-lb-123.us-east-1.elb.amazonaws.com Z35SXDOTRQ7X7K

  # Create CNAME record (subdomain)
  $0 create-cname Z1234567890ABC api.example.com my-lb-123.us-east-1.elb.amazonaws.com

  # Wait for DNS propagation
  $0 wait example.com 300

EOF
}

main() {
    local command=${1:-help}
    shift || true
    
    case $command in
        list-zones)
            list_hosted_zones
            ;;
        find-zone)
            if [ $# -lt 1 ]; then
                log_error "Usage: $0 find-zone DOMAIN"
                exit 1
            fi
            find_hosted_zone "$1"
            ;;
        create-zone)
            if [ $# -lt 1 ]; then
                log_error "Usage: $0 create-zone DOMAIN"
                exit 1
            fi
            create_hosted_zone "$1"
            ;;
        list-records)
            if [ $# -lt 1 ]; then
                log_error "Usage: $0 list-records ZONE_ID"
                exit 1
            fi
            list_dns_records "$1"
            ;;
        create-alias)
            if [ $# -lt 4 ]; then
                log_error "Usage: $0 create-alias ZONE_ID DOMAIN TARGET_DNS TARGET_ZONE_ID"
                exit 1
            fi
            create_alias_record "$1" "$2" "$3" "$4"
            ;;
        create-cname)
            if [ $# -lt 3 ]; then
                log_error "Usage: $0 create-cname ZONE_ID DOMAIN TARGET_DNS [TTL]"
                exit 1
            fi
            create_cname_record "$1" "$2" "$3" "${4:-300}"
            ;;
        delete-record)
            if [ $# -lt 3 ]; then
                log_error "Usage: $0 delete-record ZONE_ID DOMAIN TYPE"
                exit 1
            fi
            delete_dns_record "$1" "$2" "$3"
            ;;
        wait)
            if [ $# -lt 1 ]; then
                log_error "Usage: $0 wait DOMAIN [MAX_WAIT]"
                exit 1
            fi
            wait_for_dns_propagation "$1" "${2:-300}"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

