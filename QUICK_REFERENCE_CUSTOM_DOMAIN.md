# Custom Domain Quick Reference

## 🚀 Quick Start

### Route 53 (Automatic)
```bash
# 1. Edit config.env
CUSTOM_DOMAIN="api.example.com"
AUTO_CONFIGURE_DNS="true"

# 2. Run setup
./setup-eb-environment.sh

# 3. Done! Access at https://api.example.com
```

### Manual DNS
```bash
# 1. Edit config.env
CUSTOM_DOMAIN="api.example.com"
AUTO_CONFIGURE_DNS="false"

# 2. Run setup (note the instructions)
./setup-eb-environment.sh

# 3. Add DNS record at your provider
# 4. Wait 5-30 minutes for propagation
# 5. Access at https://api.example.com
```

## 📋 Configuration Variables

```bash
# In config.env
CUSTOM_DOMAIN=""              # Your domain or subdomain (empty to skip)
AUTO_CONFIGURE_DNS="false"    # "true" for Route 53 automation
```

## 🔧 Route 53 DNS Script Commands

```bash
# List zones
./scripts/setup-route53-dns.sh list-zones

# Find zone
./scripts/setup-route53-dns.sh find-zone example.com

# Create CNAME (subdomain)
./scripts/setup-route53-dns.sh create-cname ZONE_ID api.example.com target.com

# Create ALIAS (root domain)
./scripts/setup-route53-dns.sh create-alias ZONE_ID example.com target.com LB_ZONE_ID

# Delete record
./scripts/setup-route53-dns.sh delete-record ZONE_ID api.example.com CNAME

# Help
./scripts/setup-route53-dns.sh help
```

## ✅ Testing

```bash
# Run tests
./tests/test-custom-domain.sh

# Check DNS
dig api.example.com +short

# Test HTTPS
curl -I https://api.example.com
```

## 📝 DNS Record Types

### Subdomain (api.example.com)
- **Type**: CNAME
- **Name**: api
- **Target**: your-env.region.elasticbeanstalk.com

### Root Domain (example.com)
- **Type**: ALIAS (Route 53) or A (with IP)
- **Name**: @ or blank
- **Target**: your-env.region.elasticbeanstalk.com

## 🔐 SSL Certificate

Must include your custom domain:

```bash
# Wildcard (recommended)
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "*.example.com" \
  --validation-method DNS

# Specific domains
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "api.example.com" "www.example.com" \
  --validation-method DNS
```

## 🐛 Troubleshooting

### Domain not resolving?
- Wait 5-30 minutes (up to 48 hours)
- Check DNS records at provider
- Flush DNS cache: `sudo systemd-resolve --flush-caches`

### HTTPS not working?
- Check certificate includes domain
- Wait for DNS propagation
- Deploy application: `eb deploy`
- Check environment health: `eb health`

### Root domain issues?
- Use subdomain (www.example.com)
- Migrate to Route 53 or Cloudflare
- Both support ALIAS/CNAME flattening

## 📚 Documentation

- Main guide: [CUSTOM_DOMAIN_SETUP.md](CUSTOM_DOMAIN_SETUP.md)
- Full README: [README.md](README.md)
- Changelog: [CHANGELOG_CUSTOM_DOMAIN.md](CHANGELOG_CUSTOM_DOMAIN.md)

## 🎯 Examples

### Single Subdomain
```bash
CUSTOM_DOMAIN="api.example.com"
AUTO_CONFIGURE_DNS="true"
./setup-eb-environment.sh
```

### Multiple Domains
```bash
# Get environment URL
ENV_URL=$(aws elasticbeanstalk describe-environments \
  --application-name my-app \
  --environment-names my-env \
  --query "Environments[0].CNAME" --output text)

# Add domains
./scripts/setup-route53-dns.sh create-cname ZONE_ID api.example.com $ENV_URL
./scripts/setup-route53-dns.sh create-cname ZONE_ID www.example.com $ENV_URL
```

### Root Domain
```bash
CUSTOM_DOMAIN="example.com"
AUTO_CONFIGURE_DNS="true"
./setup-eb-environment.sh
```

## ⚡ Common Tasks

### Check DNS propagation
```bash
dig api.example.com +short
```

### Verify HTTPS
```bash
curl -I https://api.example.com
```

### List DNS records
```bash
./scripts/setup-route53-dns.sh list-records ZONE_ID
```

### Update existing environment
```bash
# Add CUSTOM_DOMAIN to config.env
./setup-eb-environment.sh  # Safe - idempotent
```

## 🎨 Best Practices

1. ✅ Use subdomains (easier, universal support)
2. ✅ Use wildcard SSL certificates
3. ✅ Use Route 53 for DNS (best integration)
4. ✅ Test before going live
5. ✅ Enable HTTPS redirect
6. ✅ Monitor DNS and SSL expiration

## 🔗 Quick Links

- AWS Route 53: https://console.aws.amazon.com/route53/
- AWS ACM: https://console.aws.amazon.com/acm/
- DNS Checker: https://www.whatsmydns.net/



