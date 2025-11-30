# Custom Domain Configuration Guide

This document provides a comprehensive guide for configuring custom domains and subdomains with your Elastic Beanstalk environment.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Configuration Options](#configuration-options)
3. [Automatic Route 53 Configuration](#automatic-route53-configuration)
4. [Manual DNS Configuration](#manual-dns-configuration)
5. [Managing Multiple Domains](#managing-multiple-domains)
6. [SSL Certificate Requirements](#ssl-certificate-requirements)
7. [Troubleshooting](#troubleshooting)
8. [Advanced Usage](#advanced-usage)

## Quick Start

### For Route 53 Hosted Domains

If your domain is already hosted in Route 53, the setup is fully automated:

1. **Update configuration**:
   ```bash
   # Edit config.env
   CUSTOM_DOMAIN="api.example.com"
   AUTO_CONFIGURE_DNS="true"
   ```

2. **Run setup**:
   ```bash
   ./setup-eb-environment.sh
   ```

3. **Wait for DNS propagation** (typically 5-30 minutes)

4. **Access your application**:
   ```bash
   https://api.example.com
   ```

### For Other DNS Providers

If your domain is hosted elsewhere (GoDaddy, Namecheap, Cloudflare, etc.):

1. **Update configuration**:
   ```bash
   # Edit config.env
   CUSTOM_DOMAIN="api.example.com"
   AUTO_CONFIGURE_DNS="false"
   ```

2. **Run setup** and note the DNS instructions provided

3. **Add DNS record** at your provider:
   - **Type**: CNAME (for subdomains) or ALIAS/A (for root domains)
   - **Name**: subdomain or @ for root
   - **Target**: Your EB environment URL (e.g., `my-env.us-east-1.elasticbeanstalk.com`)
   - **TTL**: 300 (or default)

4. **Wait for DNS propagation** (typically 5-30 minutes, up to 48 hours)

## Configuration Options

### Config Variables

Add these to your `config.env`:

```bash
# Custom Domain Configuration
CUSTOM_DOMAIN=""              # Your domain or subdomain
AUTO_CONFIGURE_DNS="false"    # Set to "true" for automatic Route 53 setup

# Examples:
# CUSTOM_DOMAIN="api.example.com"      # Subdomain
# CUSTOM_DOMAIN="www.example.com"      # WWW subdomain
# CUSTOM_DOMAIN="example.com"          # Root domain
# CUSTOM_DOMAIN=""                     # Skip custom domain setup
```

### Domain Types

#### Subdomains (Recommended)
- **Examples**: `api.example.com`, `www.example.com`, `app.example.com`
- **DNS Record**: CNAME
- **Compatibility**: Works with all DNS providers
- **Setup**: Easiest to configure

#### Root Domains
- **Examples**: `example.com`, `yourdomain.com`
- **DNS Record**: ALIAS (Route 53) or A record (other providers)
- **Compatibility**: Requires ALIAS support or alternative
- **Setup**: May require Route 53 or Cloudflare

**Note**: Many DNS providers don't support ALIAS records for root domains. Options:
- Use a subdomain (e.g., `www.example.com`)
- Use Route 53 for DNS hosting
- Use Cloudflare (has CNAME flattening)

## Automatic Route 53 Configuration

When `AUTO_CONFIGURE_DNS="true"` and your domain is in Route 53:

### What Happens Automatically

1. **Hosted Zone Detection**: Script finds your Route 53 hosted zone
2. **Existing Record Check**: Checks if DNS record already exists
   - If exists and correct: Skips creation (idempotent)
   - If exists but different: Updates the record
   - If not exists: Creates new record
3. **Record Creation/Update**: Creates or updates appropriate DNS record:
   - ALIAS record for root domains
   - CNAME record for subdomains
4. **DNS Verification**: Checks if DNS resolves correctly
5. **HTTPS Testing**: Tests the HTTPS endpoint

**Idempotency**: This process is fully idempotent - running it multiple times with the same configuration will not create duplicate records. Existing correct configurations are detected and preserved.

### Example

```bash
# Configure
cat >> config.env <<EOF
CUSTOM_DOMAIN="api.myapp.com"
AUTO_CONFIGURE_DNS="true"
EOF

# Run
./setup-eb-environment.sh

# Output will show:
# [INFO] Custom domain configured: api.myapp.com
# [INFO] Route 53 DNS record created successfully!
# [INFO] Domain resolves to: my-env.us-east-1.elb.amazonaws.com
# [INFO] HTTPS endpoint is responding!
```

## Manual DNS Configuration

When `AUTO_CONFIGURE_DNS="false"` or domain is not in Route 53:

### For Subdomains

Most DNS providers (GoDaddy, Namecheap, Cloudflare, etc.):

```
Record Type: CNAME
Name:        api (or www, app, etc.)
Target:      your-env-name.region.elasticbeanstalk.com
TTL:         300 (or default)
```

**Example for `api.example.com`**:
- Name: `api`
- Target: `my-app-prod.us-east-1.elasticbeanstalk.com`

### For Root Domains

**Option 1: Route 53** (Recommended)
```
Record Type: ALIAS
Name:        @ (or leave blank)
Target:      your-env-name.region.elasticbeanstalk.com
```

**Option 2: Cloudflare**
```
Record Type: CNAME (with orange cloud icon for flattening)
Name:        @ (or leave blank)
Target:      your-env-name.region.elasticbeanstalk.com
```

**Option 3: Other Providers** (Not recommended)
```
Record Type: A
Name:        @ (or leave blank)
Target:      [Resolved IP address of load balancer]
```
⚠️ Note: Load balancer IPs can change!

## Managing Multiple Domains

You can point multiple domains/subdomains to the same environment.

### Using the Route 53 Script

```bash
# Get your environment URL
ENV_URL=$(aws elasticbeanstalk describe-environments \
  --application-name my-app \
  --environment-names my-env \
  --query "Environments[0].CNAME" \
  --output text)

# Get hosted zone ID
ZONE_ID=$(./scripts/setup-route53-dns.sh find-zone example.com)

# Add multiple domains
./scripts/setup-route53-dns.sh create-cname $ZONE_ID api.example.com $ENV_URL
./scripts/setup-route53-dns.sh create-cname $ZONE_ID www.example.com $ENV_URL
./scripts/setup-route53-dns.sh create-cname $ZONE_ID app.example.com $ENV_URL
```

### Manual Configuration

Simply add multiple CNAME records in your DNS provider, all pointing to your environment URL.

## SSL Certificate Requirements

**Critical**: Your ACM SSL certificate must include all domains you plan to use.

### Wildcard Certificates (Recommended)

Covers all subdomains:

```bash
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "*.example.com" \
  --validation-method DNS \
  --region us-east-1
```

This certificate covers:
- `example.com`
- `api.example.com`
- `www.example.com`
- `app.example.com`
- Any other subdomain

### Specific Domain Certificates

Explicitly list each domain:

```bash
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "api.example.com" "www.example.com" "app.example.com" \
  --validation-method DNS \
  --region us-east-1
```

### Checking Certificate Coverage

```bash
# List your domains in certificate
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:region:account:certificate/id \
  --query "Certificate.SubjectAlternativeNames"
```

## Troubleshooting

### Domain Not Resolving

**Symptoms**: `dig` or `nslookup` returns no results

**Solutions**:
1. **Wait longer**: DNS propagation can take 5-30 minutes (up to 48 hours)
2. **Check DNS records**: Verify configuration at your DNS provider
3. **Verify nameservers**: If using Route 53, ensure nameservers are updated at registrar
4. **Clear DNS cache**:
   ```bash
   # Linux
   sudo systemd-resolve --flush-caches
   
   # macOS
   sudo dscacheutil -flushcache
   
   # Windows
   ipconfig /flushdns
   ```

### HTTPS Not Working

**Symptoms**: Certificate errors or connection refused on HTTPS

**Solutions**:
1. **Certificate doesn't include domain**:
   ```bash
   # Check certificate
   aws acm describe-certificate --certificate-arn YOUR_ARN
   
   # Request new certificate with all domains
   aws acm request-certificate \
     --domain-name "*.example.com" \
     --validation-method DNS \
     --region us-east-1
   ```

2. **DNS not propagated**: Wait and try again

3. **Application not deployed**:
   ```bash
   eb deploy
   ```

4. **Environment unhealthy**:
   ```bash
   eb health --refresh
   ```

### Root Domain Not Working

**Symptoms**: Subdomain works but root domain doesn't

**Solutions**:
1. **Provider doesn't support ALIAS**: 
   - Migrate to Route 53, or
   - Use subdomain (`www.example.com`), or
   - Use Cloudflare

2. **Using A record with changing IPs**:
   - Not recommended for production
   - Migrate to Route 53 or Cloudflare

### Route 53 Automatic Configuration Failed

**Symptoms**: Script can't find hosted zone

**Solutions**:
1. **Create hosted zone**:
   ```bash
   ./scripts/setup-route53-dns.sh create-zone example.com
   ```

2. **Update nameservers** at domain registrar (shown after zone creation)

3. **Wait 24-48 hours** for nameserver propagation

4. **Use manual configuration** instead:
   ```bash
   AUTO_CONFIGURE_DNS="false"
   ```

## Advanced Usage

### Route 53 DNS Management Script

The standalone script provides full DNS management:

```bash
# View all commands
./scripts/setup-route53-dns.sh help

# List hosted zones
./scripts/setup-route53-dns.sh list-zones

# Find zone for domain
./scripts/setup-route53-dns.sh find-zone example.com

# Create new hosted zone
./scripts/setup-route53-dns.sh create-zone example.com

# List DNS records
./scripts/setup-route53-dns.sh list-records Z1234567890ABC

# Create CNAME record
./scripts/setup-route53-dns.sh create-cname Z1234567890ABC api.example.com target.example.com

# Create ALIAS record
./scripts/setup-route53-dns.sh create-alias Z1234567890ABC example.com lb.amazonaws.com Z35SXDOTRQ7X7K

# Delete record
./scripts/setup-route53-dns.sh delete-record Z1234567890ABC api.example.com CNAME

# Wait for DNS propagation
./scripts/setup-route53-dns.sh wait api.example.com 300
```

### Verifying Configuration

#### Check DNS Resolution

```bash
# Using dig (detailed)
dig api.example.com

# Just the result
dig api.example.com +short

# Check nameservers
dig example.com NS +short

# Check from specific nameserver
dig @8.8.8.8 api.example.com

# Using nslookup
nslookup api.example.com

# Using host
host api.example.com
```

#### Test HTTPS Endpoint

```bash
# Check headers
curl -I https://api.example.com

# Full request
curl https://api.example.com

# Check SSL certificate
curl -v https://api.example.com 2>&1 | grep -A 10 "SSL certificate"

# Using openssl
openssl s_client -connect api.example.com:443 -servername api.example.com
```

### Testing Custom Domain Setup

Run the comprehensive test suite:

```bash
# Run all tests
./tests/test-custom-domain.sh

# Quick tests only (skip AWS integration)
./tests/test-custom-domain.sh --quick

# Full tests including AWS
./tests/test-custom-domain.sh --full
```

### DNS Propagation Monitoring

```bash
# Check multiple DNS servers
for ns in 8.8.8.8 1.1.1.1 208.67.222.222; do
  echo "DNS Server: $ns"
  dig @$ns api.example.com +short
  echo ""
done

# Monitor propagation
watch -n 5 'dig api.example.com +short'
```

## Best Practices

1. **Use Subdomains**: Easier to configure, works with all providers
2. **Wildcard Certificates**: Cover all subdomains automatically
3. **Route 53 for DNS**: Best integration, supports ALIAS records
4. **Test Before Going Live**: Verify DNS and HTTPS before announcing
5. **Monitor DNS TTL**: Lower TTL (300s) allows faster changes
6. **Document Changes**: Keep record of all DNS configurations
7. **Use HTTPS Only**: Enable HTTP to HTTPS redirect
8. **Idempotent Operations**: Scripts can be safely re-run; existing correct configurations are preserved

## Idempotency

The custom domain configuration scripts follow the same idempotency principles as the rest of the project:

- **Check Before Create**: DNS records are checked before creation
- **Skip if Correct**: If a record exists and points to the correct target, no changes are made
- **Update if Different**: If a record exists but points to a different target, it's updated
- **No Duplicates**: Running the script multiple times will never create duplicate DNS records
- **Safe Re-runs**: You can safely re-run the setup script to update configurations

Example behavior:
```bash
# First run - creates DNS record
./setup-eb-environment.sh
# Output: [INFO] Creating new DNS record for: api.example.com

# Second run - skips because record is correct
./setup-eb-environment.sh
# Output: [INFO] DNS record for api.example.com already exists and is correctly configured
#         [INFO] Skipping DNS record creation

# After changing environment - updates record
# (Environment changed, load balancer DNS changed)
./setup-eb-environment.sh
# Output: [WARN] DNS record exists but points to different target: old-lb.amazonaws.com
#         [INFO] Updating to: new-lb.amazonaws.com
```

## Security Considerations

1. **Always use HTTPS**: Configure valid SSL certificates
2. **Enable HTTPS redirect**: Force all traffic through HTTPS
3. **Keep certificates updated**: Monitor expiration dates
4. **Use strong SSL policies**: Prefer TLS 1.2 and 1.3
5. **Verify domain ownership**: Ensure only authorized domains point to your environment
6. **Monitor DNS changes**: Watch for unauthorized modifications
7. **Use DNS validation**: For ACM certificates, prefer DNS over email validation

## Support

For issues and questions:
- Check this guide and the main [README.md](README.md)
- Review [AWS Route 53 documentation](https://docs.aws.amazon.com/route53/)
- Review [AWS ACM documentation](https://docs.aws.amazon.com/acm/)
- Run the test suite: `./tests/test-custom-domain.sh`
- Open an issue in the repository

## Additional Resources

- [AWS Route 53 Developer Guide](https://docs.aws.amazon.com/route53/latest/DeveloperGuide/)
- [AWS Certificate Manager User Guide](https://docs.aws.amazon.com/acm/latest/userguide/)
- [Elastic Beanstalk Custom Domains](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/customdomains.html)
- [DNS Propagation Checker](https://www.whatsmydns.net/)

