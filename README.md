# AWS Elastic Beanstalk S3 SSL Automation

A somewhat opinionated, comprehensive shell script automation tool that provisions a fully-configured AWS Elastic Beanstalk environment. The script automates the creation and configuration of an Elastic Beanstalk application, sets up separate S3 buckets for static assets (read-only) and file uploads (full access), and integrates with AWS Certificate Manager to handle SSL certificate procurement and HTTPS setup. It also manages RDS database provisioning, IAM roles and policies, environment variables, load balancer configuration, and optional custom domain and Route 53 DNS record automation, making deployment on AWS streamlined and repeatable with minimal manual intervention.

## Features

- **Automated EB Environment Creation**: Creates and configures Elastic Beanstalk application and environment
- **RDS Database Integration**: PostgreSQL RDS instance with Multi-AZ deployment and automated backups
- **Database Autoscaling**: Storage autoscaling and read replica autoscaling for handling variable workloads
- **Dual S3 Buckets**: Sets up separate buckets for static assets (read-only) and file uploads (full access)
- **SSL/HTTPS Configuration**: Integrates with AWS Certificate Manager for HTTPS support
- **Custom Domain Configuration**: Supports custom domains and subdomains with optional Route 53 automation
- **Route 53 DNS Management**: Automatically creates DNS records for custom domains (if hosted in Route 53)
- **IAM Role Management**: Creates or configures IAM roles with appropriate S3 and Secrets Manager permissions
- **Load Balancer Setup**: Configures Application Load Balancer with HTTPS listener and optional HTTP redirect
- **Environment Variables**: Automatically configures environment variables for S3 bucket and database access
- **Deployment Instructions**: Generates customized deployment instructions for your application

## Validation vs Testing

This project distinguishes between **validation** and **testing**:

### Validation (Pre-deployment)
Run before deployment to ensure your environment is ready:
```bash
./validate/run-validation.sh
```
- ✅ Checks prerequisites (AWS CLI, credentials, permissions)
- ✅ Validates configuration files and variables
- ✅ Verifies environment readiness
- **Purpose**: "Can we deploy?"

### Testing (Code Quality)
Run during development to verify functionality:
```bash
./tests/run-tests.sh unit
```
- ✅ Tests code logic and behavior
- ✅ Validates business rules
- ✅ Checks integration between components
- **Purpose**: "Does the code work correctly?"

## Documentation

- **[VALIDATION.md](VALIDATION.md)** - Pre-deployment validation guide
- **[TESTING.md](TESTING.md)** - Testing framework and writing tests
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines and development workflow
- **[CUSTOM_DOMAIN_SETUP.md](CUSTOM_DOMAIN_SETUP.md)** - Custom domain configuration
- **[IDEMPOTENCY_VERIFICATION.md](IDEMPOTENCY_VERIFICATION.md)** - Idempotency verification examples

## Prerequisites

### Required Tools

- **AWS CLI**: Version 2.x or higher
  ```bash
  # Install on Linux
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  
  # Install on macOS
  brew install awscli
  ```

- **EB CLI** (recommended for deployment):
  ```bash
  pip install awsebcli
  ```

- **jq** (recommended, for JSON parsing):
  ```bash
  # Linux
  sudo apt-get install jq
  
  # macOS
  brew install jq
  ```

### AWS Requirements

- **AWS Account** with appropriate permissions
- **IAM Permissions** for:
  - Elastic Beanstalk (full access)
  - S3 (create and manage buckets)
  - IAM (create and manage roles/policies)
  - ACM (list and describe certificates)
  - EC2 (for EB instances)
  - Elastic Load Balancing (for ALB configuration)
  - RDS (create and manage database instances)
  - Secrets Manager (store database credentials)
  - VPC (manage security groups and subnets)

- **ACM Certificate**: SSL certificate for your domain (will be validated during setup)

### Git Submodules

This project uses git submodules for the testing framework. After cloning:

```bash
git submodule update --init --recursive
```

**Note**: Required for running tests. See [TESTING.md](TESTING.md) for details.

### AWS Credentials Configuration

Configure your AWS credentials before running the script:

```bash
aws configure --profile default
```

Or for a custom profile:

```bash
aws configure --profile myprofile
```

## Quick Start

### 1. Clone or Download

```bash
git clone <repository-url>
cd aws-eb-s3-ssl-automate

# Initialize git submodules (required for testing framework)
git submodule update --init --recursive
```

### 2. Configure

Copy the example configuration and edit it with your settings:

```bash
cp config.env.example config.env
nano config.env  # or use your preferred editor
```

**Important configuration options:**

```bash
# AWS Configuration
AWS_REGION="us-east-1"
AWS_PROFILE="default"

# Application Configuration
APP_NAME="my-application"
ENV_NAME="my-app-prod"
EB_PLATFORM="Python 3.11 running on 64bit Amazon Linux 2023"

# Domain and SSL
DOMAIN_NAME="example.com"

# Custom Domain (optional)
CUSTOM_DOMAIN="api.example.com"  # Your custom domain or subdomain
AUTO_CONFIGURE_DNS="true"        # Automatically configure Route 53 DNS

# S3 Buckets (must be globally unique)
STATIC_ASSETS_BUCKET="my-app-static-us-east-1"
UPLOADS_BUCKET="my-app-uploads-us-east-1"

# Instance Configuration
INSTANCE_TYPE="t3.micro"
MIN_INSTANCES="1"
MAX_INSTANCES="4"
```

### 3. Validate Prerequisites

Run the validation script to check prerequisites, permissions, and configuration before deployment:

```bash
./validate/run-validation.sh
```

**What this checks:**
- ✅ AWS CLI installation and version
- ✅ AWS credentials and permissions
- ✅ Required IAM permissions for EB, S3, ACM
- ✅ Configuration file variables
- ✅ S3 bucket name validity
- ✅ Existing AWS resources

**Note:** This validation ensures your environment is ready for deployment. It is separate from code testing.

### 4. Optional: Run Code Tests

For developers: Run unit and integration tests to verify code functionality:

```bash
# Run unit tests (no AWS required)
./tests/run-tests.sh unit

# Run integration tests
./tests/run-tests.sh integration
```

### 4. Request SSL Certificate (if needed)

If you don't have an ACM certificate yet, you can request one:

```bash
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "*.example.com" \
  --validation-method DNS \
  --region us-east-1
```

**Note:** You don't need to wait for the certificate to be issued before running the setup script. The script will automatically detect if your certificate is pending validation, display the required DNS records, and give you options to:
- Wait for validation (with automatic polling)
- Exit and continue later after adding DNS records
- Skip SSL configuration temporarily

### 5. Run Setup

Make the script executable and run it:

```bash
chmod +x setup-eb-environment.sh
./setup-eb-environment.sh
```

The script will:
1. Create S3 buckets with appropriate configurations
2. Find and validate your SSL certificate (or guide you through DNS validation)
3. Set up IAM roles and policies
4. Create the Elastic Beanstalk environment
5. Configure HTTPS on the load balancer
6. Configure custom domain (if specified)
7. Display deployment instructions

**SSL Certificate Validation:**
- If your certificate is already issued, the script continues automatically
- If pending validation, the script displays the DNS records you need to add
- You can choose to wait for validation, or exit and return later
- The script polls AWS every 30 seconds until validation completes

## Configuration Options

### EB Platform Options

Available platform strings (check [AWS documentation](https://docs.aws.amazon.com/elasticbeanstalk/latest/platforms/platforms-supported.html) for latest):

#### Amazon Linux 2 Platforms
- `"64bit Amazon Linux 2 v4.9.7 running Tomcat 9 Corretto 11"`
- `"64bit Amazon Linux 2 v4.9.7 running Tomcat 9 Corretto 8"`
- `"64bit Amazon Linux 2 v4.3.3 running Docker"`
- `"64bit Amazon Linux 2 v3.10.7 running PHP 8.1"`
- `"64bit Amazon Linux 2 v3.9.7 running Corretto 17"`
- `"64bit Amazon Linux 2 v3.9.7 running Corretto 11"`
- `"64bit Amazon Linux 2 v3.9.7 running Corretto 8"`
- `"64bit Amazon Linux 2 v3.5.7 running ECS"`
- `"64bit Amazon Linux 2 v2.11.7 running .NET Core"`

#### Amazon Linux 2023 Platforms
- `"Python 3.11 running on 64bit Amazon Linux 2023"`

#### Windows Server Platforms
- `"64bit Windows Server 2025 v2.20.0 running IIS 10.0"`
- `"64bit Windows Server Core 2025 v2.20.0 running IIS 10.0"`
- `"64bit Windows Server 2022 v2.20.0 running IIS 10.0"`
- `"64bit Windows Server Core 2022 v2.20.0 running IIS 10.0"`
- `"64bit Windows Server 2019 v2.20.0 running IIS 10.0"`
- `"64bit Windows Server Core 2019 v2.20.0 running IIS 10.0"`
- `"64bit Windows Server 2016 v2.20.0 running IIS 10.0"`
- `"64bit Windows Server Core 2016 v2.20.0 running IIS 10.0"`

### Instance Types

Recommended instance types by use case:

- **Development/Testing**: `t3.micro`, `t3.small`
- **Small Production**: `t3.medium`, `t3a.medium`
- **Medium Production**: `t3.large`, `m5.large`
- **High Performance**: `c5.xlarge`, `m5.xlarge`

### SSL Policies

Available SSL policies (most secure to most compatible):

- `ELBSecurityPolicy-TLS13-1-2-2021-06` (recommended, TLS 1.2 and 1.3)
- `ELBSecurityPolicy-TLS-1-2-2017-01` (legacy support)
- `ELBSecurityPolicy-2016-08` (maximum compatibility)

## Usage

### Basic Usage

```bash
./setup-eb-environment.sh
```

**Expected Execution Time:** 5-15 minutes, depending on:
- AWS resource creation time (environment creation typically takes 5-10 minutes)
- SSL certificate validation status
- Network latency

The script provides real-time progress updates and will wait up to 15 minutes for environment creation to complete. If the environment is still launching after the timeout, the script will display a warning but the environment will continue to launch in the background.

### Advanced Options

```bash
# Use custom configuration file
./setup-eb-environment.sh --config my-custom-config.env

# Skip SSL configuration
./setup-eb-environment.sh --skip-ssl

# Dry-run (validate only)
./setup-eb-environment.sh --dry-run

# Show help
./setup-eb-environment.sh --help
```

## Idempotency

The scripts are designed to be **idempotent**, meaning you can safely run them multiple times without causing errors or creating duplicate resources. This is useful for:

- Re-running after configuration changes
- Recovering from partial failures
- Updating existing environments with new settings

### What Happens on Subsequent Runs

#### ✅ Safe Re-run Behavior

When you run the scripts on an existing setup:

**S3 Buckets:**
- Existing buckets are detected and skipped
- Configuration (CORS, versioning, public access) is only updated if it differs from desired state
- No unnecessary API calls are made if configuration is already correct

**IAM Roles and Policies:**
- Existing roles and policies are detected and reused
- Policy documents are compared before creating new versions
- Old policy versions are automatically cleaned up to stay within AWS's 5-version limit
- Role attachments to instance profiles are verified and fixed if missing

**Elastic Beanstalk Environment:**
- Existing applications and environments are detected
- Configuration is compared with desired state from `config.env`
- If changes are detected, you'll be prompted before updating (to avoid unexpected downtime)
- Only necessary updates are applied

**HTTPS Configuration:**
- Current HTTPS listener settings are checked before updating
- Updates are skipped if certificate ARN and SSL policy are already correct
- No environment restarts triggered for unchanged configuration

**SSL Certificate:**
- Existing certificates are found and validated
- No new certificates are created if one already exists for your domain

**Custom Domain (Route 53):**
- Existing DNS records are detected before creating new ones
- If record exists and points to correct target, creation is skipped
- If record exists but points to different target, it's updated
- No duplicate records are created

#### ⚠️ Configuration Updates with User Confirmation

If you change settings in `config.env` and re-run the scripts, the following will prompt for confirmation:

**Elastic Beanstalk Environment Updates:**
When instance type, scaling settings, or environment variables change:
```
[WARN] Environment configuration has changed. The following will be updated:
  - Instance Type
  - Min Instances
  - STATIC_ASSETS_BUCKET env var

[WARN] Updating the environment may cause brief downtime or service interruption.
Do you want to update the environment? (yes/no):
```

### Example: Re-running After Config Changes

```bash
# Initial run - creates everything
./setup-eb-environment.sh

# Later, you change INSTANCE_TYPE in config.env from t3.micro to t3.small
nano config.env

# Re-run - will detect the change and prompt
./setup-eb-environment.sh
# Output:
# [INFO] Application my-app already exists
# [WARN] Environment my-app-prod already exists
# [INFO] Checking if environment configuration needs update...
# [WARN] Environment configuration has changed. The following will be updated:
#   - Instance Type
# [WARN] Updating the environment may cause brief downtime or service interruption.
# Do you want to update the environment? (yes/no): yes
# [INFO] Updating environment configuration...
```

### No Duplicate Resources

The scripts will **never** create duplicate resources:
- S3 bucket names are unique, so attempts to recreate will be safely skipped
- IAM roles are checked by name before creation
- EB applications and environments are checked before creation
- Certificate lookups find existing certificates by domain name
- Route 53 DNS records are checked before creation; existing matching records are skipped

### Benefits

1. **Safe to Re-run**: Fix failures or incomplete runs without manual cleanup
2. **Configuration Management**: Update settings by editing `config.env` and re-running
3. **No Manual Cleanup Needed**: Scripts handle existing resources gracefully
4. **Efficient**: Skips unnecessary API calls and updates
5. **Policy Version Management**: Automatically cleans up old IAM policy versions

## Project Structure

```
.
├── setup-eb-environment.sh          # Main orchestration script
├── config.env.example               # Configuration template
├── config.env                       # Your configuration (gitignored)
├── README.md                        # This file
├── VALIDATION.md                    # Pre-deployment validation guide
├── TESTING.md                       # Testing framework guide
├── CONTRIBUTING.md                  # Contribution guidelines
├── CUSTOM_DOMAIN_SETUP.md           # Custom domain configuration guide
├── QUICK_REFERENCE_CUSTOM_DOMAIN.md # Custom domain quick reference
├── IDEMPOTENCY_VERIFICATION.md      # Idempotency verification examples
├── scripts/
│   ├── setup-s3-buckets.sh         # S3 bucket creation and configuration
│   ├── setup-ssl-certificate.sh    # ACM certificate validation
│   ├── setup-iam-roles.sh          # IAM role and policy setup
│   ├── create-eb-environment.sh    # EB environment creation
│   ├── configure-ssl.sh            # Load balancer SSL configuration
│   ├── configure-custom-domain.sh  # Custom domain configuration
│   ├── setup-route53-dns.sh        # Route 53 DNS management utility
│   └── generate-deployment-instructions.sh  # Deployment guide generator
├── validate/                        # Pre-deployment validation
│   ├── run-validation.sh           # Main validation orchestrator
│   ├── prerequisites.sh            # AWS CLI, tools, credentials
│   ├── permissions.sh              # IAM permissions validation
│   ├── config.sh                   # Configuration file validation
│   └── environment.sh              # Existing resources check
├── tests/                          # Code testing
│   ├── bats/                       # bats-core testing framework (submodule)
│   ├── test_helper.bash            # Shared test utilities
│   ├── aws-mock.bash               # AWS API mocking
│   ├── run-tests.sh                # Test runner
│   ├── unit/                       # Unit tests
│   ├── integration/                # Integration tests
│   ├── e2e/                        # End-to-end tests
│   ├── test-setup.sh               # Legacy validation (deprecated)
│   └── test-custom-domain.sh       # Legacy custom domain tests
└── templates/
    └── eb-options.json             # EB option settings template
```

## Custom Domain Configuration

### Overview

The automation supports configuring custom domains or subdomains for your Elastic Beanstalk environment with two options:
1. **Automatic Route 53 Configuration**: Automatically creates DNS records if your domain is hosted in Route 53
2. **Manual DNS Configuration**: Provides instructions for manual DNS setup with any provider

### Quick Setup

#### Option 1: Automatic Configuration (Route 53)

If your domain is hosted in Route 53:

```bash
# In config.env
CUSTOM_DOMAIN="api.example.com"
AUTO_CONFIGURE_DNS="true"

# Run setup
./setup-eb-environment.sh
```

The script will automatically:
- Detect your Route 53 hosted zone
- Check if DNS record already exists and is correct
- Skip if record already points to the correct target (idempotent)
- Create or update DNS records (CNAME for subdomains, ALIAS for root domains)
- Verify DNS configuration
- Test HTTPS endpoint

**Note**: The script is fully idempotent - running it multiple times with the same configuration will not create duplicate DNS records or cause errors.

#### Option 2: Manual Configuration (Any DNS Provider)

For domains hosted with GoDaddy, Namecheap, Cloudflare, etc.:

```bash
# In config.env
CUSTOM_DOMAIN="api.example.com"
AUTO_CONFIGURE_DNS="false"  # or leave empty

# Run setup
./setup-eb-environment.sh
```

The script will display DNS configuration instructions like:

```
For Subdomain (api.example.com, www.example.com):
  Record Type: CNAME
  Name:        api
  Target:      my-env-123.us-east-1.elasticbeanstalk.com
  TTL:         300

For Root Domain (example.com):
  Record Type: ALIAS (if supported) or A record
  Name:        @ (or leave blank)
  Target:      my-env-123.us-east-1.elasticbeanstalk.com
  TTL:         300
```

### Supported Domain Types

#### Subdomains
- **Examples**: `api.example.com`, `www.example.com`, `app.example.com`
- **DNS Record**: CNAME
- **Works with**: All DNS providers
- **Propagation**: Usually 5-30 minutes

#### Root Domains
- **Examples**: `example.com`, `yourdomain.com`
- **DNS Record**: ALIAS (Route 53) or A record (with IP lookup)
- **Works with**: 
  - Route 53 (recommended, supports ALIAS)
  - Cloudflare (supports CNAME flattening)
  - Some other providers (check if they support ALIAS)
- **Propagation**: Usually 5-30 minutes, can take up to 48 hours

**Note**: Some DNS providers don't support ALIAS records for root domains. In such cases:
- Use a subdomain instead (e.g., `www.example.com`)
- Migrate DNS to Route 53
- Use your provider's alternative (Cloudflare has "CNAME flattening")

### Route 53 DNS Management Script

A standalone utility for managing Route 53 DNS records:

```bash
# List all hosted zones
./scripts/setup-route53-dns.sh list-zones

# Find hosted zone for a domain
./scripts/setup-route53-dns.sh find-zone example.com

# Create hosted zone
./scripts/setup-route53-dns.sh create-zone example.com

# List DNS records in a zone
./scripts/setup-route53-dns.sh list-records Z1234567890ABC

# Create CNAME record (for subdomains)
./scripts/setup-route53-dns.sh create-cname Z1234567890ABC api.example.com my-lb.elb.amazonaws.com

# Create ALIAS record (for root domains)
./scripts/setup-route53-dns.sh create-alias Z1234567890ABC example.com my-lb.elb.amazonaws.com Z35SXDOTRQ7X7K

# Delete DNS record
./scripts/setup-route53-dns.sh delete-record Z1234567890ABC api.example.com CNAME

# Wait for DNS propagation
./scripts/setup-route53-dns.sh wait api.example.com 300

# Show help
./scripts/setup-route53-dns.sh help
```

### Adding Multiple Domains

You can point multiple domains to the same environment:

#### Using Route 53 Script:

```bash
# Get your environment's load balancer DNS
ENV_URL=$(aws elasticbeanstalk describe-environments \
  --application-name my-app \
  --environment-names my-env \
  --query "Environments[0].CNAME" \
  --output text)

# Get your hosted zone ID
ZONE_ID=$(./scripts/setup-route53-dns.sh find-zone example.com)

# Add multiple subdomains
./scripts/setup-route53-dns.sh create-cname $ZONE_ID api.example.com $ENV_URL
./scripts/setup-route53-dns.sh create-cname $ZONE_ID www.example.com $ENV_URL
./scripts/setup-route53-dns.sh create-cname $ZONE_ID app.example.com $ENV_URL
```

#### Manually:

Just add multiple CNAME records in your DNS provider, all pointing to your environment's URL.

### SSL Certificate Considerations

**Important**: Your SSL certificate must include all domains you want to use:

```bash
# Request certificate with multiple domains
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "*.example.com" "api.example.com" "www.example.com" \
  --validation-method DNS \
  --region us-east-1
```

- Use a wildcard certificate (`*.example.com`) to cover all subdomains
- Or explicitly list all domains/subdomains in the certificate
- Without proper SSL coverage, HTTPS won't work for that domain

### Verifying Domain Configuration

#### Check DNS Resolution:

```bash
# Using dig
dig api.example.com +short

# Using nslookup
nslookup api.example.com

# Using host
host api.example.com
```

#### Test HTTPS Endpoint:

```bash
# Test with curl
curl -I https://api.example.com

# Test with browser
# Simply visit https://api.example.com
```

### Troubleshooting Custom Domains

#### Domain not resolving:
- **Wait for DNS propagation** (5-30 minutes typically, up to 48 hours)
- **Check DNS records** are correct in your provider
- **Verify nameservers** if using Route 53 (update at domain registrar)
- **Try flushing DNS cache**: `sudo systemd-resolve --flush-caches` (Linux)

#### HTTPS not working:
- **Certificate doesn't include domain**: Request new certificate with this domain
- **DNS not propagated yet**: Wait longer
- **Application not deployed**: Deploy your application first
- **Environment not healthy**: Check environment health in AWS console

#### Root domain not working:
- **Provider doesn't support ALIAS**: Use subdomain or migrate to Route 53
- **Need to use A record**: Some providers require you to resolve the LB IP (not recommended, IPs can change)
- **Alternative solutions**: Use Cloudflare (supports CNAME flattening)

### Example: Complete Custom Domain Setup

```bash
# 1. Configure in config.env
cat >> config.env <<EOF
CUSTOM_DOMAIN="api.mycompany.com"
AUTO_CONFIGURE_DNS="true"
EOF

# 2. Ensure SSL certificate includes the domain
aws acm request-certificate \
  --domain-name "*.mycompany.com" \
  --validation-method DNS \
  --region us-east-1

# 3. Run setup
./setup-eb-environment.sh

# 4. Verify DNS
dig api.mycompany.com +short

# 5. Test HTTPS
curl -I https://api.mycompany.com

# 6. Deploy your application
cd /path/to/your/app
eb deploy
```

## Database Configuration

The automation creates a PostgreSQL RDS instance with the following features:

- **Multi-AZ deployment** for high availability
- **Automated backups** with 7-day retention (configurable 0-35 days)
- **Encryption at rest** using AWS KMS
- **Private access only** (not publicly accessible)
- **Security group** allowing access only from EB instances
- **Secrets Manager** for secure password storage
- **Storage autoscaling** to automatically grow storage as needed
- **Read replica autoscaling** for handling variable read traffic

### Database Settings

Configure your database in `config.env`:

```bash
# Database Configuration
DB_ENGINE="postgres"                              # Database engine
DB_ENGINE_VERSION="16.3"                         # Engine version
DB_INSTANCE_CLASS="db.t3.micro"                  # Instance size
DB_ALLOCATED_STORAGE="20"                        # Storage in GB
DB_STORAGE_TYPE="gp3"                            # Storage type
DB_NAME="${APP_NAME//-/_}_${ENV_NAME}"           # Database name
DB_USERNAME="dbadmin"                            # Master username
DB_MASTER_PASSWORD=""                            # Leave empty for auto-generation
DB_MULTI_AZ="true"                               # Enable Multi-AZ
DB_BACKUP_RETENTION_DAYS="7"                     # Backup retention
DB_BACKUP_WINDOW="03:00-04:00"                   # Backup window (UTC)
DB_MAINTENANCE_WINDOW="mon:04:00-mon:05:00"      # Maintenance window
DB_STORAGE_ENCRYPTED="true"                      # Enable encryption
DB_PUBLICLY_ACCESSIBLE="false"                   # Public access (keep false)
DB_SKIP_FINAL_SNAPSHOT="false"                   # Skip final snapshot on delete

# Database Autoscaling Configuration
DB_STORAGE_AUTOSCALING_ENABLED="true"            # Enable storage autoscaling
DB_MAX_ALLOCATED_STORAGE="100"                   # Maximum storage limit in GB
DB_READ_REPLICA_ENABLED="false"                  # Enable read replicas
DB_READ_REPLICA_COUNT="1"                        # Initial number of replicas
DB_READ_REPLICA_MIN_CAPACITY="1"                 # Minimum replicas
DB_READ_REPLICA_MAX_CAPACITY="3"                 # Maximum replicas
DB_READ_REPLICA_TARGET_CPU="70"                  # Target CPU % for scaling
DB_READ_REPLICA_SCALE_IN_COOLDOWN="300"          # Scale-in cooldown (seconds)
DB_READ_REPLICA_SCALE_OUT_COOLDOWN="60"          # Scale-out cooldown (seconds)
```

### Database Connection

Database connection details are automatically configured as environment variables in your Elastic Beanstalk environment:

- `DATABASE_URL`: Full PostgreSQL connection string
- `DB_HOST`: Database endpoint
- `DB_PORT`: Database port (5432)
- `DB_NAME`: Database name
- `DB_USERNAME`: Master username
- `DB_PASSWORD`: Master password (auto-generated if not provided)

### Password Management

If `DB_MASTER_PASSWORD` is left empty, a secure password will be automatically generated and stored in AWS Secrets Manager at:

```
<APP_NAME>/<ENV_NAME>/db-password
```

This password is automatically retrieved and configured in your EB environment during setup.

### Autoscaling

The database supports two types of autoscaling:

**Storage Autoscaling:**
- Automatically increases storage when running low on disk space
- Grows up to `DB_MAX_ALLOCATED_STORAGE` limit
- No downtime during scaling
- Prevents storage-full errors

**Read Replica Autoscaling:**
- Automatically scales read replicas based on CPU utilization
- Adjusts between `DB_READ_REPLICA_MIN_CAPACITY` and `DB_READ_REPLICA_MAX_CAPACITY`
- Ideal for handling variable read traffic
- Cost-effective scaling for read-heavy workloads

To enable read replicas, set `DB_READ_REPLICA_ENABLED="true"` in `config.env`.

### Security Considerations

- The database is created in the same VPC as your EB environment
- Only EB instances can access the database (via security group rules)
- All connections are encrypted in transit
- Storage is encrypted at rest
- Passwords are never stored in plain text in configuration files

For detailed database management, scaling strategies, and monitoring, see [DATABASE_SETUP.md](DATABASE_SETUP.md).

## Deployment

After the environment is created, deploy your application:

### Using EB CLI

```bash
# Navigate to your application directory
cd /path/to/your/application

# Initialize EB CLI
eb init --profile default --region us-east-1

# Select the application and environment created by the script

# Deploy your application
eb deploy my-app-prod
```

### Environment Variables

Your application will have access to these environment variables:

**S3 Configuration:**
- `STATIC_ASSETS_BUCKET`: Name of the static assets S3 bucket
- `UPLOADS_BUCKET`: Name of the uploads S3 bucket
- `AWS_REGION`: AWS region where resources are located
- `AWS_DEFAULT_REGION`: Standard AWS SDK environment variable for region
- `S3_REGION`: Explicit S3 region (alias for AWS_REGION)

**Database Configuration:**
- `DATABASE_URL`: PostgreSQL connection string (e.g., `postgresql://user:pass@host:port/dbname`)
- `DB_HOST`: Database endpoint hostname
- `DB_PORT`: Database port (default: 5432)
- `DB_NAME`: Database name
- `DB_USERNAME`: Database username
- `DB_PASSWORD`: Database password

#### S3 Credentials and Authentication

**Important:** S3 access credentials (access key ID and secret access key) are **NOT** stored as environment variables. This infrastructure uses IAM instance roles, which is the AWS security best practice.

**How It Works:**
1. Your EC2 instances are assigned an IAM instance role with S3 permissions
2. The AWS SDK automatically detects it's running on EC2
3. Temporary credentials are retrieved from the EC2 instance metadata service
4. Credentials are automatically rotated before expiration

**What This Means:**
- No access keys to manage or rotate manually
- No risk of credential exposure in environment variables or code
- AWS SDK automatically handles authentication
- Your application code simply uses the AWS SDK without explicit credentials

### Example Application Code

**Python (using boto3):**

```python
import os
import boto3

# Initialize S3 client
# No credentials needed - AWS SDK automatically uses IAM instance role
s3 = boto3.client("s3", region_name=os.environ["AWS_REGION"])

# Upload a file
s3.upload_file(
    "local_file.jpg",
    os.environ["UPLOADS_BUCKET"],
    "uploads/file.jpg"
)

# Generate presigned URL for static asset
url = s3.generate_presigned_url(
    "get_object",
    Params={
        "Bucket": os.environ["STATIC_ASSETS_BUCKET"],
        "Key": "static/image.jpg"
    },
    ExpiresIn=3600
)
```

**Node.js (using AWS SDK v2):**

```javascript
const AWS = require("aws-sdk");

// Initialize S3 client
// No credentials needed - AWS SDK automatically uses IAM instance role
const s3 = new AWS.S3({
  region: process.env.AWS_REGION
});

// Upload a file
const uploadParams = {
  Bucket: process.env.UPLOADS_BUCKET,
  Key: "uploads/file.jpg",
  Body: fileBuffer
};

s3.upload(uploadParams, (err, data) => {
  if (err) throw err;
  console.log(data.Location);
});

// Get object
const getParams = {
  Bucket: process.env.STATIC_ASSETS_BUCKET,
  Key: "static/image.jpg"
};

s3.getObject(getParams, (err, data) => {
  if (err) throw err;
  console.log(data.Body);
});
```

**Node.js (using AWS SDK v3):**

```javascript
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";

// Initialize S3 client
// No credentials needed - AWS SDK automatically uses IAM instance role
const s3Client = new S3Client({ region: process.env.AWS_REGION });

// Upload a file
const uploadCommand = new PutObjectCommand({
  Bucket: process.env.UPLOADS_BUCKET,
  Key: "uploads/file.jpg",
  Body: fileBuffer
});

const uploadResult = await s3Client.send(uploadCommand);
console.log(uploadResult);

// Get object
const getCommand = new GetObjectCommand({
  Bucket: process.env.STATIC_ASSETS_BUCKET,
  Key: "static/image.jpg"
});

const getResult = await s3Client.send(getCommand);
console.log(getResult.Body);
```

## Managing Your Environment

### Quick Status Check

Use the included status checker script to quickly verify your environment health:

```bash
./scripts/check-environment-status.sh
```

This will show:
- Current environment status (Ready, Launching, etc.)
- Health status (Green, Yellow, Red)
- Recent events and logs
- Environment URL

This is especially useful after the setup script times out to verify if the environment completed successfully.

### Common EB CLI Commands

```bash
# View environment status
eb status my-app-prod

# View environment health
eb health my-app-prod

# View logs
eb logs my-app-prod

# SSH into instance
eb ssh my-app-prod

# Set environment variables
eb setenv KEY=VALUE

# Print environment variables
eb printenv

# Open environment in browser
eb open my-app-prod

# Terminate environment
eb terminate my-app-prod
```

### Managing S3 Buckets

```bash
# List files in static assets bucket
aws s3 ls s3://my-app-static-us-east-1/

# Upload file to static assets
aws s3 cp local-file.jpg s3://my-app-static-us-east-1/images/

# Sync directory
aws s3 sync ./static/ s3://my-app-static-us-east-1/static/

# Download file from uploads bucket
aws s3 cp s3://my-app-uploads-us-east-1/file.jpg ./
```

### Updating SSL Certificate

If you need to update the SSL certificate:

```bash
# Request new certificate
aws acm request-certificate \
  --domain-name example.com \
  --validation-method DNS \
  --region us-east-1

# After validation, update environment
aws elasticbeanstalk update-environment \
  --environment-name my-app-prod \
  --option-settings Namespace=aws:elbv2:listener:443,OptionName=SSLCertificateArns,Value=NEW_CERT_ARN
```

## Troubleshooting

### Environment Creation Fails

**Check logs:**
```bash
aws elasticbeanstalk describe-events \
  --environment-name my-app-prod \
  --max-items 20
```

**Common issues:**
- Insufficient IAM permissions
- Invalid platform selection
- Resource limits reached
- Instance type not available in region

### Script Timeout During Environment Creation

If the script times out while waiting for the environment to become ready:

**Check environment status:**
```bash
aws elasticbeanstalk describe-environments \
  --application-name ride-jaunt-server \
  --environment-names development \
  --query "Environments[0].[Status,Health,HealthStatus]" \
  --output table
```

**What to do:**

1. **Environment is "Ready" with "Green" or "Yellow" health:** 
   - The environment launched successfully! The script timed out but the environment is working.
   - Continue to the next steps (SSL configuration if needed)

2. **Environment is still "Launching":**
   - Wait a few more minutes and check again
   - Environment creation typically takes 5-10 minutes
   - Check recent events for progress:
   ```bash
   aws elasticbeanstalk describe-events \
     --application-name ride-jaunt-server \
     --environment-name development \
     --max-items 20
   ```

3. **Environment status is "Terminated" or shows errors:**
   - Check the events log for error messages
   - Common issues: IAM role problems, VPC/subnet issues, instance launch failures
   - Delete the failed environment and retry

### SSL Certificate Validation Issues

**If certificate is pending validation:**

The script will automatically display the DNS records you need to add. If you've already run the script, you can check the validation records manually:

```bash
aws acm describe-certificate \
  --certificate-arn YOUR_CERT_ARN \
  --region us-east-1 \
  --query "Certificate.DomainValidationOptions"
```

Add the CNAME records to your DNS provider and wait 5-30 minutes for validation.

**Common issues:**
- DNS records not added correctly (check Name and Value exactly match AWS requirements)
- DNS propagation delay (can take up to 30 minutes)
- Using the wrong DNS zone or subdomain

### HTTPS Not Working

**Verify certificate:**
```bash
aws acm describe-certificate \
  --certificate-arn YOUR_CERT_ARN \
  --region us-east-1
```

**Check listener configuration:**
```bash
aws elbv2 describe-listeners \
  --load-balancer-arn YOUR_LB_ARN
```

**Common issues:**
- Certificate not in ISSUED status (must be validated first)
- DNS not pointing to load balancer
- Security group blocking port 443
- Need to wait for DNS propagation (up to 48 hours)

### S3 Access Issues

**Verify IAM role:**
```bash
aws iam get-role --role-name aws-elasticbeanstalk-ec2-role
```

**Check attached policies:**
```bash
aws iam list-attached-role-policies \
  --role-name aws-elasticbeanstalk-ec2-role
```

**Common issues:**
- IAM role missing S3 permissions
- Bucket policy conflicts
- Public access blocks preventing access

### Application Deployment Fails

**Check environment health:**
```bash
eb health my-app-prod --refresh
```

**View detailed logs:**
```bash
eb logs my-app-prod
```

**Common issues:**
- Missing application dependencies
- Incorrect platform selection
- Application port not matching EB expectations
- Health check path returning errors

## Cost Considerations

Running this setup will incur AWS costs for:

- **EC2 Instances**: Based on instance type and number of instances
- **Load Balancer**: Application Load Balancer hourly charges + data transfer
- **S3 Storage**: Storage costs + request costs
- **Data Transfer**: Outbound data transfer charges
- **CloudWatch**: Log storage and monitoring (minimal)

**Estimated monthly costs (us-east-1, minimal usage):**
- 1 × t3.micro instance (24/7): ~$7-8
- Application Load Balancer: ~$16
- S3 storage (10 GB): ~$0.25
- **Total**: ~$23-25/month

*Use AWS Cost Calculator for accurate estimates based on your usage.*

## Security Best Practices

1. **IAM Roles**: Use least-privilege principle for IAM policies
2. **S3 Buckets**: Keep uploads bucket private, use signed URLs when needed
3. **HTTPS Only**: Enable HTTP to HTTPS redirect
4. **Security Groups**: Restrict access to necessary ports only
5. **Secrets Management**: Use AWS Secrets Manager or Parameter Store for sensitive data
6. **Regular Updates**: Keep platform versions updated
7. **Monitoring**: Enable CloudWatch alarms for unusual activity

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is provided as-is for educational and automation purposes.

## Support

For issues and questions:
- Check the [Troubleshooting](#troubleshooting) section
- Review [AWS Elastic Beanstalk documentation](https://docs.aws.amazon.com/elastic-beanstalk/)
- Open an issue in the repository

## Acknowledgments

Built to simplify AWS Elastic Beanstalk deployments with S3 and SSL integration.

