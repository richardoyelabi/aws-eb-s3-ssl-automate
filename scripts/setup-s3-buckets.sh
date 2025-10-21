#!/bin/bash

# S3 Bucket Setup Module
# Creates and configures S3 buckets for static assets and file uploads

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

create_bucket_if_not_exists() {
    local bucket_name=$1
    local region=$2

    if aws s3api head-bucket --bucket "$bucket_name" --profile "$AWS_PROFILE" 2>/dev/null; then
        log_warn "Bucket $bucket_name already exists"
        return 0
    fi

    log_info "Creating S3 bucket: $bucket_name"
    
    if [ "$region" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --profile "$AWS_PROFILE" \
            --region "$region"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --profile "$AWS_PROFILE" \
            --region "$region" \
            --create-bucket-configuration LocationConstraint="$region"
    fi

    log_info "Bucket $bucket_name created successfully"
}

configure_static_assets_bucket() {
    local bucket_name=$1
    local region=$2

    log_info "Configuring static assets bucket: $bucket_name"

    # Enable versioning if configured
    if [ "$ENABLE_S3_VERSIONING" = "true" ]; then
        log_info "Enabling versioning on $bucket_name"
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled \
            --profile "$AWS_PROFILE" \
            --region "$region"
    fi

    # Configure CORS for static assets
    log_info "Configuring CORS for $bucket_name"
    cat > /tmp/cors-config.json <<EOF
{
    "CORSRules": [
        {
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "HEAD"],
            "AllowedOrigins": ["*"],
            "ExposeHeaders": ["ETag"],
            "MaxAgeSeconds": 3000
        }
    ]
}
EOF

    aws s3api put-bucket-cors \
        --bucket "$bucket_name" \
        --cors-configuration file:///tmp/cors-config.json \
        --profile "$AWS_PROFILE" \
        --region "$region"

    # Block public access (we'll use IAM policies for EB access)
    log_info "Configuring public access block for $bucket_name"
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
        --profile "$AWS_PROFILE" \
        --region "$region"

    rm -f /tmp/cors-config.json
    log_info "Static assets bucket configured successfully"
}

configure_uploads_bucket() {
    local bucket_name=$1
    local region=$2

    log_info "Configuring uploads bucket: $bucket_name"

    # Enable versioning if configured
    if [ "$ENABLE_S3_VERSIONING" = "true" ]; then
        log_info "Enabling versioning on $bucket_name"
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled \
            --profile "$AWS_PROFILE" \
            --region "$region"
    fi

    # Configure CORS for uploads
    log_info "Configuring CORS for $bucket_name"
    cat > /tmp/cors-config-uploads.json <<EOF
{
    "CORSRules": [
        {
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "HEAD", "PUT", "POST", "DELETE"],
            "AllowedOrigins": ["*"],
            "ExposeHeaders": ["ETag", "x-amz-request-id"],
            "MaxAgeSeconds": 3000
        }
    ]
}
EOF

    aws s3api put-bucket-cors \
        --bucket "$bucket_name" \
        --cors-configuration file:///tmp/cors-config-uploads.json \
        --profile "$AWS_PROFILE" \
        --region "$region"

    # Block all public access for uploads bucket
    log_info "Configuring public access block for $bucket_name"
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --profile "$AWS_PROFILE" \
        --region "$region"

    rm -f /tmp/cors-config-uploads.json
    log_info "Uploads bucket configured successfully"
}

main() {
    log_info "Starting S3 bucket setup..."

    # Create and configure static assets bucket
    create_bucket_if_not_exists "$STATIC_ASSETS_BUCKET" "$AWS_REGION"
    configure_static_assets_bucket "$STATIC_ASSETS_BUCKET" "$AWS_REGION"

    # Create and configure uploads bucket
    create_bucket_if_not_exists "$UPLOADS_BUCKET" "$AWS_REGION"
    configure_uploads_bucket "$UPLOADS_BUCKET" "$AWS_REGION"

    log_info "S3 bucket setup completed successfully"
    echo ""
    echo "Created buckets:"
    echo "  - Static Assets: $STATIC_ASSETS_BUCKET"
    echo "  - Uploads: $UPLOADS_BUCKET"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" -eq "${0}" ]; then
    main "$@"
fi

