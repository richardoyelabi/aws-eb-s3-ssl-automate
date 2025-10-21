#!/bin/bash

# Deployment Instructions Generator
# Generates customized deployment instructions based on the environment configuration

set -e

# Color codes for output
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

generate_instructions() {
    local env_url=$1

    cat <<EOF

${GREEN}════════════════════════════════════════════════════════════════════════${NC}
${GREEN}  AWS Elastic Beanstalk Environment Setup Complete!${NC}
${GREEN}════════════════════════════════════════════════════════════════════════${NC}

${CYAN}Environment Details:${NC}
  Application Name:    $APP_NAME
  Environment Name:    $ENV_NAME
  Region:              $AWS_REGION
  Environment URL:     http://$env_url
  HTTPS URL:           https://$env_url

${CYAN}S3 Buckets Created:${NC}
  Static Assets:       $STATIC_ASSETS_BUCKET
  File Uploads:        $UPLOADS_BUCKET

${CYAN}Environment Variables (already configured):${NC}
  STATIC_ASSETS_BUCKET=$STATIC_ASSETS_BUCKET
  UPLOADS_BUCKET=$UPLOADS_BUCKET
  AWS_REGION=$AWS_REGION

${GREEN}────────────────────────────────────────────────────────────────────────${NC}
${GREEN}  Next Steps: Deploying Your Application${NC}
${GREEN}────────────────────────────────────────────────────────────────────────${NC}

${YELLOW}Step 1: Initialize EB CLI in your application directory${NC}

  cd /path/to/your/application
  eb init --profile $AWS_PROFILE --region $AWS_REGION

  When prompted:
  - Select application: $APP_NAME
  - Select environment: $ENV_NAME

${YELLOW}Step 2: Deploy your application${NC}

  eb deploy $ENV_NAME --profile $AWS_PROFILE

${YELLOW}Step 3: Access S3 buckets from your application${NC}

  The following environment variables are available in your application:
  
  - STATIC_ASSETS_BUCKET: Use for serving static files (CSS, JS, images)
  - UPLOADS_BUCKET: Use for user file uploads
  - AWS_REGION: AWS region where resources are located

  Example Python code using boto3:

    import os
    import boto3

    s3 = boto3.client("s3", region_name=os.environ["AWS_REGION"])
    
    # Upload a file
    s3.upload_file(
        "local_file.jpg",
        os.environ["UPLOADS_BUCKET"],
        "uploads/file.jpg"
    )
    
    # Get file URL
    url = s3.generate_presigned_url(
        "get_object",
        Params={
            "Bucket": os.environ["STATIC_ASSETS_BUCKET"],
            "Key": "static/image.jpg"
        },
        ExpiresIn=3600
    )

${YELLOW}Step 4: Configure your domain (optional)${NC}

  To use your custom domain ($DOMAIN_NAME) with this environment:

  1. Create a CNAME record in your DNS provider:
     
     CNAME: $DOMAIN_NAME -> $env_url

  2. Wait for DNS propagation (can take up to 48 hours)

  3. Access your application at: https://$DOMAIN_NAME

${YELLOW}Step 5: Monitor your environment${NC}

  # View environment status
  eb status $ENV_NAME --profile $AWS_PROFILE

  # View logs
  eb logs $ENV_NAME --profile $AWS_PROFILE

  # Open environment in browser
  eb open $ENV_NAME --profile $AWS_PROFILE

  # SSH into instance (if key pair configured)
  eb ssh $ENV_NAME --profile $AWS_PROFILE

${GREEN}────────────────────────────────────────────────────────────────────────${NC}
${GREEN}  Useful EB CLI Commands${NC}
${GREEN}────────────────────────────────────────────────────────────────────────${NC}

  eb deploy              Deploy your application
  eb status              Check environment status
  eb health              View environment health
  eb logs                Retrieve environment logs
  eb config              View/edit configuration
  eb setenv KEY=VALUE    Set environment variables
  eb printenv            Print environment variables
  eb terminate           Terminate the environment

${GREEN}────────────────────────────────────────────────────────────────────────${NC}
${GREEN}  Managing S3 Buckets${NC}
${GREEN}────────────────────────────────────────────────────────────────────────${NC}

  # List files in static assets bucket
  aws s3 ls s3://$STATIC_ASSETS_BUCKET/ --profile $AWS_PROFILE

  # Upload files to static assets bucket
  aws s3 cp local-file.jpg s3://$STATIC_ASSETS_BUCKET/images/ --profile $AWS_PROFILE

  # Sync directory to static assets bucket
  aws s3 sync ./static/ s3://$STATIC_ASSETS_BUCKET/static/ --profile $AWS_PROFILE

  # List uploads
  aws s3 ls s3://$UPLOADS_BUCKET/ --profile $AWS_PROFILE

${GREEN}────────────────────────────────────────────────────────────────────────${NC}
${GREEN}  Troubleshooting${NC}
${GREEN}────────────────────────────────────────────────────────────────────────${NC}

  If deployment fails:
  
  1. Check environment health:
     eb health $ENV_NAME --profile $AWS_PROFILE --refresh

  2. View recent logs:
     eb logs $ENV_NAME --profile $AWS_PROFILE

  3. Check environment events:
     aws elasticbeanstalk describe-events \\
       --environment-name $ENV_NAME \\
       --profile $AWS_PROFILE \\
       --region $AWS_REGION \\
       --max-items 20

  If HTTPS is not working:
  
  1. Verify certificate status:
     aws acm describe-certificate \\
       --certificate-arn \$(cat /tmp/acm-cert-arn.txt 2>/dev/null || echo "YOUR_CERT_ARN") \\
       --profile $AWS_PROFILE \\
       --region $AWS_REGION

  2. Wait a few minutes for SSL configuration to propagate

${GREEN}════════════════════════════════════════════════════════════════════════${NC}

EOF
}

main() {
    # Read environment URL
    local env_url
    if [ -f /tmp/eb-env-url.txt ]; then
        env_url=$(cat /tmp/eb-env-url.txt)
    else
        env_url="<environment-url>"
    fi

    generate_instructions "$env_url"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

