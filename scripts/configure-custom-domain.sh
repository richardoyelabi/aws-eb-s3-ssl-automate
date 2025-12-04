#!/bin/bash

# Custom Domain Configuration Module
# Configures custom domain or subdomain for Elastic Beanstalk environment

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

validate_domain_format() {
    local domain=$1
    
    # Basic domain validation regex
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi
    
    return 0
}

get_load_balancer_dns() {
    local env_name=$1
    
    log_info "Retrieving load balancer DNS name..."
    
    local lb_name=$(aws elasticbeanstalk describe-environment-resources \
        --environment-name "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "EnvironmentResources.LoadBalancers[0].Name" \
        --output text)
    
    if [ -z "$lb_name" ] || [ "$lb_name" = "None" ]; then
        log_error "Could not find load balancer for environment: $env_name"
        return 1
    fi
    
    local lb_dns=$(aws elbv2 describe-load-balancers \
        --names "$lb_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "LoadBalancers[0].DNSName" \
        --output text)
    
    if [ -z "$lb_dns" ] || [ "$lb_dns" = "None" ]; then
        log_error "Could not retrieve load balancer DNS name"
        return 1
    fi
    
    echo "$lb_dns"
}

get_load_balancer_hosted_zone() {
    local env_name=$1
    
    local lb_name=$(aws elasticbeanstalk describe-environment-resources \
        --environment-name "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "EnvironmentResources.LoadBalancers[0].Name" \
        --output text)
    
    local lb_zone=$(aws elbv2 describe-load-balancers \
        --names "$lb_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "LoadBalancers[0].CanonicalHostedZoneId" \
        --output text)
    
    echo "$lb_zone"
}

detect_dns_provider() {
    local domain=$1

    # Try to detect DNS provider by checking nameservers
    if command -v dig &> /dev/null; then
        local nameservers=$(dig NS "$domain" +short 2>/dev/null | head -4)

        if echo "$nameservers" | grep -q "ns[0-9]*\.godaddy\.com"; then
            echo "GoDaddy"
        elif echo "$nameservers" | grep -q "ns[0-9]*\.namecheap\.com"; then
            echo "Namecheap"
        elif echo "$nameservers" | grep -q "ns[0-9]*\.cloudflare\.com"; then
            echo "Cloudflare"
        elif echo "$nameservers" | grep -q "ns[0-9]*\.awsdns"; then
            echo "Route 53"
        elif echo "$nameservers" | grep -q "ns[0-9]*\.bluehost\.com"; then
            echo "Bluehost"
        elif echo "$nameservers" | grep -q "ns[0-9]*\.hostgator\.com"; then
            echo "HostGator"
        else
            echo "Unknown"
        fi
    else
        echo "Unknown"
    fi
}

display_manual_dns_instructions() {
    local domain=$1
    local lb_dns=$2

    # Determine if this is a root domain or subdomain
    local root_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
    local is_root_domain=false
    if [ "$domain" = "$root_domain" ]; then
        is_root_domain=true
    fi

    # Try to detect DNS provider
    local detected_provider=$(detect_dns_provider "$domain")

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Manual DNS Configuration Required${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Your domain (${domain}) is not hosted with Route 53, so you'll need to configure"
    echo "DNS records manually with your current DNS provider."

    if [ "$detected_provider" != "Unknown" ]; then
        echo -e "${GREEN}✓ Detected DNS Provider: $detected_provider${NC}"
        echo ""
    fi

    # Special guidance for root domains
    if [ "$is_root_domain" = true ]; then
        echo -e "${YELLOW}💡 Tip for Root Domains:${NC}"
        echo "Root domains (like ${domain}) work best with Route 53 because it supports ALIAS records."
        echo "If you encounter issues with your current provider, consider migrating DNS to Route 53."
        echo ""
        echo -e "${CYAN}To migrate to Route 53:${NC}"
        echo "1. Create hosted zone: aws route53 create-hosted-zone --name ${domain}"
        echo "2. Update nameservers at your domain registrar"
        echo "3. Set AUTO_CONFIGURE_DNS=\"true\" in config.env"
        echo "4. Re-run this script"
        echo ""
    fi

    echo -e "${CYAN}DNS Record Configuration:${NC}"
    echo ""

    if [ "$is_root_domain" = true ]; then
        echo -e "${YELLOW}For Root Domain (${domain}):${NC}"
        echo "  Record Type: ALIAS (preferred) or A record"
        echo "  Name:        @ (or leave blank, or ${domain})"
        echo "  Target:      $lb_dns"
        echo "  TTL:         300 (or default)"
        echo ""
        echo -e "${CYAN}Alternative Methods for Root Domains:${NC}"
        echo ""
        echo -e "${YELLOW}Option A: Use ALIAS record (if your provider supports it)${NC}"
        echo "  - Route 53, Cloudflare, and some others support ALIAS"
        echo "  - ALIAS records work correctly with load balancers that change IPs"
        echo "  - This is the recommended approach"
        echo ""
        echo -e "${YELLOW}Option B: Use A record with IP lookup (NOT recommended)${NC}"
        echo "  - Look up the IP address of: $lb_dns"
        echo "  - Create A record pointing to that IP"
        echo "  - ⚠️ Load balancer IPs can change, breaking your domain!"
        echo "  - Only use if your provider doesn't support ALIAS"
        echo ""
        echo -e "${YELLOW}Option C: Use CNAME flattening (Cloudflare)${NC}"
        echo "  - If using Cloudflare, enable \"CNAME flattening\""
        echo "  - Create CNAME record pointing to $lb_dns"
        echo "  - Cloudflare will handle the root domain properly"
    else
        echo -e "${YELLOW}For Subdomain (${domain}):${NC}"
        echo "  Record Type: CNAME"
        echo "  Name:        $(echo "$domain" | cut -d'.' -f1)"
        echo "  Target:      $lb_dns"
        echo "  TTL:         300 (or default)"
        echo ""
        echo -e "${GREEN}✓ CNAME records are supported by all DNS providers${NC}"
        echo -e "${GREEN}✓ Safe to use with load balancers${NC}"
    fi

    echo ""
    echo -e "${CYAN}Steps to Configure:${NC}"
    echo ""
    echo -e "1. ${CYAN}Log into your DNS provider's control panel${NC}"
    echo "   - GoDaddy, Namecheap, Cloudflare, Bluehost, etc."
    echo ""
    echo -e "2. ${CYAN}Find the DNS management section${NC}"
    echo "   - Usually called \"DNS\", \"DNS Zone\", or \"Name Servers\""
    echo ""
    echo -e "3. ${CYAN}Add the DNS record shown above${NC}"
    echo "   - Copy the exact values provided"
    echo "   - Save the changes"
    echo ""
    echo -e "4. ${CYAN}Wait for DNS propagation${NC}"
    echo "   - Usually takes 5-30 minutes"
    echo "   - Can take up to 48 hours in rare cases"
    echo "   - DNS changes propagate globally"
    echo ""
    echo -e "${CYAN}Verification Commands:${NC}"
    echo ""
    echo "  # Check if DNS record was added correctly"
    if [ "$is_root_domain" = true ]; then
        echo "  dig $domain A +short      # For root domains"
    else
        echo "  dig $domain CNAME +short  # For subdomains"
    fi
    echo ""
    echo "  # Test if domain resolves to your load balancer"
    echo "  nslookup $domain"
    echo ""
    echo "  # Test HTTPS access (after DNS propagates)"
    echo "  curl -I https://$domain"
    echo ""
    echo -e "${CYAN}Provider-Specific Instructions:${NC}"
    echo ""

    if [ "$detected_provider" = "GoDaddy" ]; then
        echo -e "${YELLOW}GoDaddy (Detected):${NC}"
        echo "  1. Go to \"My Products\" → Domain Settings → DNS"
        echo "  2. Add the record in the \"Records\" section"
    elif [ "$detected_provider" = "Namecheap" ]; then
        echo -e "${YELLOW}Namecheap (Detected):${NC}"
        echo "  1. Go to Domain List → Manage → Advanced DNS"
        echo "  2. Add the record in the \"Host Records\" section"
    elif [ "$detected_provider" = "Cloudflare" ]; then
        echo -e "${YELLOW}Cloudflare (Detected):${NC}"
        echo "  1. Go to DNS → Records"
        if [ "$is_root_domain" = true ]; then
            echo "  2. For root domains: Enable \"CNAME Flattening\" in SSL/TLS settings"
        fi
        echo "  3. Add the record as specified above"
    else
        echo -e "${YELLOW}General Instructions:${NC}"
        echo "  - Look for \"DNS Management\", \"DNS Zone\", or \"Name Server\" settings"
        echo "  - Most providers have similar interfaces"
        echo ""
        echo -e "${YELLOW}Popular Providers:${NC}"
        echo "  GoDaddy: \"My Products\" → Domain Settings → DNS → Records"
        echo "  Namecheap: Domain List → Manage → Advanced DNS → Host Records"
        echo "  Cloudflare: DNS → Records (enable CNAME flattening for root domains)"
        echo "  Bluehost: Domains → DNS Zone Editor"
    fi

    echo ""
    echo -e "${CYAN}Common Issues:${NC}"
    echo ""
    echo -e "${RED}❌ DNS not propagating?${NC}"
    echo "   - Wait longer (up to 48 hours)"
    echo "   - Check if record was saved correctly"
    echo "   - Clear DNS cache: sudo systemd-resolve --flush-caches"
    echo ""
    echo -e "${RED}❌ HTTPS not working?${NC}"
    echo "   - DNS must propagate first"
    echo "   - SSL certificate must include this domain"
    echo "   - Check: aws acm describe-certificate --certificate-arn YOUR_CERT_ARN"
    if [ "$is_root_domain" = false ]; then
        echo "   - If using subdomain, ensure wildcard (*.${root_domain}) is in certificate"
    fi
    echo ""
    echo -e "${RED}❌ Root domain not working?${NC}"
    echo "   - Try using www.${domain} instead"
    echo "   - Migrate DNS to Route 53 (supports ALIAS)"
    echo "   - Use Cloudflare (supports CNAME flattening)"
    echo ""
    echo -e "${CYAN}Need Help?${NC}"
    echo ""
    echo "If you encounter issues:"
    echo "1. Check the troubleshooting section in README.md"
    echo "2. Verify your SSL certificate includes this domain"
    echo "3. Test with a subdomain first (easier to debug)"
    echo "4. Contact your DNS provider's support"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

check_existing_dns_record() {
    local hosted_zone_id=$1
    local domain=$2
    local record_type=$3
    local expected_target=$4
    
    # Get existing record
    local existing_record=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --profile "$AWS_PROFILE" \
        --query "ResourceRecordSets[?Name=='${domain}.' && Type=='$record_type']" \
        --output json 2>/dev/null)
    
    if [ -z "$existing_record" ] || [ "$existing_record" = "[]" ]; then
        echo "NOT_FOUND"
        return
    fi
    
    # For CNAME records, check if target matches
    if [ "$record_type" = "CNAME" ]; then
        local current_target=$(echo "$existing_record" | grep -o '"Value": "[^"]*"' | cut -d'"' -f4 | head -1)
        if [ "$current_target" = "$expected_target" ]; then
            echo "MATCHES"
        else
            echo "DIFFERENT:$current_target"
        fi
    # For ALIAS records, check if DNS name matches
    elif [ "$record_type" = "A" ]; then
        local current_target=$(echo "$existing_record" | grep -o '"DNSName": "[^"]*"' | cut -d'"' -f4 | head -1)
        # Normalize DNS names (remove trailing dot if present)
        current_target=$(echo "$current_target" | sed 's/\.$//')
        expected_target=$(echo "$expected_target" | sed 's/\.$//')
        if [ "$current_target" = "$expected_target" ]; then
            echo "MATCHES"
        else
            echo "DIFFERENT:$current_target"
        fi
    fi
}

configure_domain_with_route53() {
    local domain=$1
    local lb_dns=$2
    local lb_zone_id=$3
    
    log_info "Checking if domain is hosted in Route 53..."
    
    # Find hosted zone for the domain
    local hosted_zone_id=$(aws route53 list-hosted-zones \
        --profile "$AWS_PROFILE" \
        --query "HostedZones[?Name=='${domain}.' || Name=='$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}').' ].Id" \
        --output text 2>/dev/null | head -1)
    
    if [ -z "$hosted_zone_id" ] || [ "$hosted_zone_id" = "None" ]; then
        log_warn "No Route 53 hosted zone found for domain: $domain"
        log_info "Skipping automatic DNS configuration"
        return 1
    fi
    
    # Clean up the hosted zone ID (remove /hostedzone/ prefix)
    hosted_zone_id=$(echo "$hosted_zone_id" | sed 's/\/hostedzone\///')
    
    log_info "Found hosted zone: $hosted_zone_id"
    
    # Determine if this is a root domain or subdomain
    local root_domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
    local is_root_domain=false
    local record_type=""
    
    if [ "$domain" = "$root_domain" ]; then
        is_root_domain=true
        record_type="A"
    else
        record_type="CNAME"
    fi
    
    # Check if DNS record already exists and matches
    log_info "Checking existing DNS configuration..."
    local record_status=$(check_existing_dns_record "$hosted_zone_id" "$domain" "$record_type" "$lb_dns")
    
    if [[ $record_status == "MATCHES" ]]; then
        log_info "DNS record for $domain already exists and is correctly configured"
        log_info "Target: $lb_dns"
        log_info "Skipping DNS record creation"
        return 0
    elif [[ $record_status == DIFFERENT:* ]]; then
        local current_target="${record_status#DIFFERENT:}"
        log_warn "DNS record exists but points to different target"
        log_info "Current: $current_target"
        log_info "Desired: $lb_dns"
        log_info "Updating DNS record..."
    else
        log_info "Creating new DNS record for: $domain"
    fi
    
    # Create change batch JSON
    if [ "$is_root_domain" = true ]; then
        # Use ALIAS record for root domain
        cat > /tmp/route53-change-batch.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$domain",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$lb_zone_id",
          "DNSName": "$lb_dns",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF
        log_info "Creating ALIAS record for root domain"
    else
        # Use CNAME record for subdomain
        cat > /tmp/route53-change-batch.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$domain",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "$lb_dns"
          }
        ]
      }
    }
  ]
}
EOF
        log_info "Creating CNAME record for subdomain"
    fi
    
    # Apply the change
    local change_info=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --change-batch file:///tmp/route53-change-batch.json \
        --profile "$AWS_PROFILE" \
        --output json)
    
    local change_id=$(echo "$change_info" | grep -o '"Id": "[^"]*"' | cut -d'"' -f4)
    
    rm -f /tmp/route53-change-batch.json
    
    if [[ $record_status == DIFFERENT:* ]]; then
        log_info "DNS record updated successfully!"
    else
        log_info "DNS record created successfully!"
    fi
    log_info "Change ID: $change_id"
    log_info "DNS propagation may take a few minutes..."
    
    return 0
}   

verify_domain_configuration() {
    local domain=$1
    local lb_dns=$2
    
    log_info "Verifying domain configuration..."
    
    # Check if dig is available
    if ! command -v dig &> /dev/null; then
        log_warn "dig command not available, skipping DNS verification"
        return 0
    fi
    
    # Try to resolve the domain
    log_info "Checking DNS resolution for: $domain"
    
    local resolved=$(dig +short "$domain" | tail -1)
    
    if [ -z "$resolved" ]; then
        log_warn "Domain not yet resolving. DNS may still be propagating."
        log_info "This is normal for newly created DNS records."
        return 0
    fi
    
    log_info "Domain resolves to: $resolved"
    
    # Check if it points to the right load balancer (for CNAME records)
    if [[ $resolved == *"elb.amazonaws.com"* ]] || [[ $resolved == $lb_dns ]]; then
        log_info "Domain is correctly pointing to the load balancer!"
    else
        log_warn "Domain resolves, but may not be pointing to the correct load balancer"
        log_info "Expected: $lb_dns"
        log_info "Got: $resolved"
    fi
}

test_https_endpoint() {
    local domain=$1
    
    log_info "Testing HTTPS endpoint..."
    
    if ! command -v curl &> /dev/null; then
        log_warn "curl not available, skipping HTTPS test"
        return 0
    fi
    
    log_info "Attempting to connect to: https://$domain"
    
    # Try to connect (with timeout)
    if curl -sSf -k --max-time 10 "https://$domain" -o /dev/null 2>&1; then
        log_info "HTTPS endpoint is responding!"
    else
        log_warn "HTTPS endpoint not responding yet. This is normal if:"
        log_warn "  1. DNS hasn't propagated yet (wait 5-30 minutes)"
        log_warn "  2. Application hasn't been deployed yet"
        log_warn "  3. SSL certificate doesn't include this domain"
    fi
}

main() {
    log_info "Starting custom domain configuration..."
    
    # Check if custom domain is configured
    if [ -z "$CUSTOM_DOMAIN" ] || [ "$CUSTOM_DOMAIN" = "false" ]; then
        log_info "Custom domain not configured (CUSTOM_DOMAIN is empty or false)"
        log_info "Skipping custom domain setup"
        return 0
    fi
    
    # Validate domain format
    if ! validate_domain_format "$CUSTOM_DOMAIN"; then
        log_error "Invalid domain format. Please check CUSTOM_DOMAIN in config.env"
        exit 1
    fi
    
    log_info "Configuring custom domain: $CUSTOM_DOMAIN"
    
    # Get load balancer DNS
    local lb_dns=$(get_load_balancer_dns "$ENV_NAME")
    if [ $? -ne 0 ]; then
        log_error "Failed to retrieve load balancer DNS"
        exit 1
    fi
    
    log_info "Load balancer DNS: $lb_dns"
    
    # Try automatic Route 53 configuration if enabled
    if [ "$AUTO_CONFIGURE_DNS" = "true" ]; then
        log_info "Automatic DNS configuration enabled"
        
        local lb_zone_id=$(get_load_balancer_hosted_zone "$ENV_NAME")
        
        if configure_domain_with_route53 "$CUSTOM_DOMAIN" "$lb_dns" "$lb_zone_id"; then
            log_info "Route 53 DNS record created successfully!"
            
            # Wait a moment for DNS to propagate (skip in test mode)
            if [ "$TEST_MODE" != "true" ]; then
                log_info "Waiting 10 seconds for DNS propagation..."
                sleep 10
            fi
            
            # Verify configuration
            verify_domain_configuration "$CUSTOM_DOMAIN" "$lb_dns"
            
            # Test HTTPS endpoint
            test_https_endpoint "$CUSTOM_DOMAIN"
            
            log_info "Custom domain configuration completed!"
            echo ""
            echo "Your application will be available at: https://$CUSTOM_DOMAIN"
            echo "Note: DNS propagation may take a few minutes to complete globally."
        else
            log_warn "Route 53 hosted zone not found for domain: $CUSTOM_DOMAIN"
            log_info "Falling back to manual DNS configuration instructions..."
            echo ""
            display_manual_dns_instructions "$CUSTOM_DOMAIN" "$lb_dns"
        fi
    else
        log_info "Automatic DNS configuration disabled"
        display_manual_dns_instructions "$CUSTOM_DOMAIN" "$lb_dns"
    fi
    
    # Export for use in other scripts
    export CUSTOM_DOMAIN_CONFIGURED="true"
    echo "$CUSTOM_DOMAIN" > /tmp/custom-domain.txt
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

