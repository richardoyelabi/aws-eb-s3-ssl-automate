# Pre-deployment Validation Guide

This document explains the validation system for the AWS EB S3 SSL Automation project.

## Overview

The validation system ensures your environment is ready for deployment before running the main setup script. It performs comprehensive checks on prerequisites, permissions, configuration, and existing resources.

## Quick Start

```bash
# Run all validation checks
./validate/run-validation.sh

# Or run individual validation components
./validate/prerequisites.sh
./validate/permissions.sh
./validate/config.sh
./validate/environment.sh
```

## Validation Components

### 1. Prerequisites Validation (`validate/prerequisites.sh`)

**Purpose**: Verify required tools and basic AWS CLI installation.

**Checks Performed**:
- ✅ AWS CLI installation and version
- ✅ EB CLI installation (optional but recommended)
- ✅ jq installation (optional but recommended)

**Example Output**:
```
[INFO] Testing AWS CLI installation...
[✓] AWS CLI is installed: aws-cli/2.32.6 Python/3.13.9 Linux/6.14.0-35-generic exe/x86_64.ubuntu.24

[INFO] Testing EB CLI installation (optional)...
[✓] EB CLI is installed: EB CLI 3.25.1 (Python 3.12.9 | packaged by Anaconda, Inc.)

[INFO] Testing jq installation (optional)...
[✓] jq is installed: jq-1.7
```

### 2. Permissions Validation (`validate/permissions.sh`)

**Purpose**: Verify AWS credentials and IAM permissions required for deployment.

**Checks Performed**:
- ✅ AWS credentials validity
- ✅ S3 permissions (CreateBucket, ListBuckets)
- ✅ Elastic Beanstalk permissions (CreateApplication, DescribeApplications)
- ✅ IAM permissions (GetRole, ListRoles)
- ✅ ACM permissions (ListCertificates)

**Example Output**:
```
[INFO] Testing AWS credentials...
[✓] AWS credentials are valid
  Account ID: 123456789012
  User/Role: arn:aws:iam::123456789012:user/username
  Region: us-east-1
  Profile: default

[INFO] Testing IAM permissions...
[✓] S3 permissions OK
[✓] Elastic Beanstalk permissions OK
[✓] IAM permissions OK
[✓] ACM permissions OK
```

### 3. Configuration Validation (`validate/config.sh`)

**Purpose**: Validate configuration file and variable values.

**Checks Performed**:
- ✅ config.env file exists
- ✅ All required variables are set
- ✅ S3 bucket names are valid (3-63 chars, lowercase, hyphens, numbers only)

**Required Variables**:
- `AWS_REGION` - AWS region for deployment
- `AWS_PROFILE` - AWS CLI profile to use
- `APP_NAME` - Elastic Beanstalk application name
- `ENV_NAME` - Elastic Beanstalk environment name
- `EB_PLATFORM` - Elastic Beanstalk platform ARN
- `DOMAIN_NAME` - Domain name for SSL certificate
- `STATIC_ASSETS_BUCKET` - S3 bucket for static assets
- `UPLOADS_BUCKET` - S3 bucket for file uploads
- `INSTANCE_TYPE` - EC2 instance type

**Example Output**:
```
[INFO] Validating configuration file...
[✓] Variable set: AWS_REGION = us-east-1
[✓] Variable set: AWS_PROFILE = default
[✓] Variable set: APP_NAME = my-app
[✓] Variable set: ENV_NAME = production
[✓] Variable set: EB_PLATFORM = 64bit Amazon Linux 2 v4.3.3 running Docker
[✓] Variable set: DOMAIN_NAME = example.com
[✓] Variable set: STATIC_ASSETS_BUCKET = my-app-static-us-east-1
[✓] Variable set: UPLOADS_BUCKET = my-app-uploads-us-east-1
[✓] Variable set: INSTANCE_TYPE = t3.micro
[✓] Configuration file is valid

[INFO] Validating S3 bucket names...
[✓] Bucket name valid: my-app-static-us-east-1
[✓] Bucket name valid: my-app-uploads-us-east-1
```

### 4. Environment Validation (`validate/environment.sh`)

**Purpose**: Check for existing AWS resources that might conflict or be reused.

**Checks Performed**:
- ℹ️ Elastic Beanstalk application exists (warning - will reuse)
- ℹ️ Elastic Beanstalk environment exists (warning - will update)
- ℹ️ S3 buckets exist (warning - will reuse)

**Note**: These are informational checks. Existing resources are handled gracefully through idempotency.

**Example Output**:
```
[INFO] Checking for existing resources...
[WARN] Application already exists: my-app
[WARN] Environment already exists: production
[WARN] Bucket already exists: my-app-static-us-east-1
[WARN] Bucket already exists: my-app-uploads-us-east-1
```

## Exit Codes

- **0**: All validations passed - safe to proceed with deployment
- **1**: One or more validations failed - fix issues before deployment

## Integration with CI/CD

The validation scripts are designed to work in automated environments:

```bash
# In CI/CD pipeline
if ./validate/run-validation.sh; then
    echo "✅ Validation passed, proceeding with deployment"
    ./setup-eb-environment.sh
else
    echo "❌ Validation failed, stopping deployment"
    exit 1
fi
```

## Troubleshooting

### AWS CLI Not Found
```
[ERROR] AWS CLI is not installed
```
**Solution**: Install AWS CLI v2
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Invalid AWS Credentials
```
[ERROR] AWS credentials are not valid or not configured
```
**Solution**: Configure AWS credentials
```bash
aws configure --profile your-profile
```

### Missing Configuration Variables
```
[ERROR] Required variable not set: APP_NAME
```
**Solution**: Update config.env file
```bash
cp config.env.example config.env
nano config.env  # Add missing variables
```

### Insufficient IAM Permissions
```
[ERROR] S3 permissions insufficient
```
**Solution**: Ensure your IAM user/role has the required permissions. See IAM Requirements section in README.md.

## Best Practices

1. **Run validation before every deployment** to catch issues early
2. **Fix validation failures** before proceeding - don't skip them
3. **Use in CI/CD** to prevent failed deployments
4. **Review warnings** about existing resources to understand what will be reused vs created

## Validation vs Testing

Remember the distinction:
- **Validation** (this document): "Can we deploy?" - checks environment readiness
- **Testing** (see TESTING.md): "Does the code work?" - verifies functionality

Both are important but serve different purposes. Run validation before deployment, run tests during development.
