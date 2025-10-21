# AWS Elastic Beanstalk S3 SSL Automation

A shell script automation tool that sets up a complete AWS Elastic Beanstalk environment with S3 buckets for static assets and file uploads, plus SSL certificate configuration via AWS Certificate Manager.

## Features

- **Automated EB Environment Creation**: Creates and configures Elastic Beanstalk application and environment
- **Dual S3 Buckets**: Sets up separate buckets for static assets (read-only) and file uploads (full access)
- **SSL/HTTPS Configuration**: Integrates with AWS Certificate Manager for HTTPS support
- **IAM Role Management**: Creates or configures IAM roles with appropriate S3 permissions
- **Load Balancer Setup**: Configures Application Load Balancer with HTTPS listener and optional HTTP redirect
- **Environment Variables**: Automatically configures environment variables for S3 bucket access
- **Deployment Instructions**: Generates customized deployment instructions for your application

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

- **ACM Certificate**: SSL certificate for your domain (will be validated during setup)

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

# S3 Buckets (must be globally unique)
STATIC_ASSETS_BUCKET="my-app-static-us-east-1"
UPLOADS_BUCKET="my-app-uploads-us-east-1"

# Instance Configuration
INSTANCE_TYPE="t3.micro"
MIN_INSTANCES="1"
MAX_INSTANCES="4"
```

### 3. Validate Configuration

Run the validation script to check prerequisites and configuration:

```bash
chmod +x tests/test-setup.sh
./tests/test-setup.sh
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
6. Display deployment instructions

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
├── scripts/
│   ├── setup-s3-buckets.sh         # S3 bucket creation and configuration
│   ├── setup-ssl-certificate.sh    # ACM certificate validation
│   ├── setup-iam-roles.sh          # IAM role and policy setup
│   ├── create-eb-environment.sh    # EB environment creation
│   ├── configure-ssl.sh            # Load balancer SSL configuration
│   └── generate-deployment-instructions.sh  # Deployment guide generator
├── tests/
│   └── test-setup.sh               # Validation and testing script
└── templates/
    └── eb-options.json             # EB option settings template
```

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

- `STATIC_ASSETS_BUCKET`: Name of the static assets S3 bucket
- `UPLOADS_BUCKET`: Name of the uploads S3 bucket
- `AWS_REGION`: AWS region where resources are located

### Example Application Code

**Python (using boto3):**

```python
import os
import boto3

# Initialize S3 client
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

**Node.js (using AWS SDK):**

```javascript
const AWS = require("aws-sdk");

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
  console.log(data.Location);
});

// Get object
const getParams = {
  Bucket: process.env.STATIC_ASSETS_BUCKET,
  Key: "static/image.jpg"
};

s3.getObject(getParams, (err, data) => {
  console.log(data.Body);
});
```

## Managing Your Environment

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

