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

If you don't have an ACM certificate yet:

```bash
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "*.example.com" \
  --validation-method DNS \
  --region us-east-1

# Follow the DNS validation instructions
# Wait for certificate to be issued (usually 5-30 minutes)
```

### 5. Run Setup

Make the script executable and run it:

```bash
chmod +x setup-eb-environment.sh
./setup-eb-environment.sh
```

The script will:
1. Create S3 buckets with appropriate configurations
2. Validate your SSL certificate
3. Set up IAM roles and policies
4. Create the Elastic Beanstalk environment
5. Configure HTTPS on the load balancer
6. Display deployment instructions

## Configuration Options

### EB Platform Options

Common platform strings (check [AWS documentation](https://docs.aws.amazon.com/elasticbeanstalk/latest/platforms/platforms-supported.html) for latest):

- `"Python 3.11 running on 64bit Amazon Linux 2023"`
- `"Python 3.9 running on 64bit Amazon Linux 2"`
- `"Node.js 18 running on 64bit Amazon Linux 2023"`
- `"Node.js 16 running on 64bit Amazon Linux 2"`
- `"Docker running on 64bit Amazon Linux 2"`
- `"Go 1.20 running on 64bit Amazon Linux 2023"`

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
- Certificate not in ISSUED status
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
- Review [AWS Elastic Beanstalk documentation](https://docs.aws.amazon.com/elasticbeanstalk/)
- Open an issue in the repository

## Acknowledgments

Built to simplify AWS Elastic Beanstalk deployments with S3 and SSL integration.

