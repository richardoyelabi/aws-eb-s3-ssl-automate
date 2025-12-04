#!/bin/bash

# IAM Role Setup Module
# Creates IAM roles and policies for Elastic Beanstalk instances to access S3 buckets

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
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

create_trust_policy() {
    cat > /tmp/eb-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

create_s3_access_policy() {
    local static_bucket=$1
    local uploads_bucket=$2

    cat > /tmp/s3-access-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StaticAssetsReadAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${static_bucket}",
        "arn:aws:s3:::${static_bucket}/*"
      ]
    },
    {
      "Sid": "UploadsFullAccess",
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::${uploads_bucket}",
        "arn:aws:s3:::${uploads_bucket}/*"
      ]
    }
  ]
}
EOF
}

create_iam_role() {
    local role_name=$1

    if aws iam get-role --role-name "$role_name" --profile "$AWS_PROFILE" 2>/dev/null; then
        log_warn "IAM role $role_name already exists"
        return 0
    fi

    log_info "Creating IAM role: $role_name"
    
    create_trust_policy

    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document file:///tmp/eb-trust-policy.json \
        --profile "$AWS_PROFILE"

    log_info "IAM role created successfully"
    rm -f /tmp/eb-trust-policy.json
}

attach_managed_policies() {
    local role_name=$1

    log_info "Attaching AWS managed policies to $role_name"

    # Attach standard EB managed policies
    local policies=(
        "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
        "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
        "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
    )

    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy" \
            --profile "$AWS_PROFILE" 2>/dev/null || log_warn "Policy $policy may already be attached"
    done
}

normalize_json() {
    local json_file=$1
    if command -v jq &> /dev/null; then
        jq -S -c . "$json_file" 2>/dev/null || cat "$json_file"
    else
        cat "$json_file" | tr -d ' \n\t'
    fi
}

create_and_attach_s3_policy() {
    local role_name=$1
    local policy_name="${role_name}-s3-access"
    
    log_info "Creating S3 access policy: $policy_name"

    create_s3_access_policy "$STATIC_ASSETS_BUCKET" "$UPLOADS_BUCKET"

    # Check if policy already exists
    local account_id=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
    local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"

    if aws iam get-policy --policy-arn "$policy_arn" --profile "$AWS_PROFILE" 2>/dev/null; then
        log_info "Policy $policy_name already exists, checking if update needed"
        
        # Get current default version
        local current_version=$(aws iam get-policy \
            --policy-arn "$policy_arn" \
            --profile "$AWS_PROFILE" \
            --query 'Policy.DefaultVersionId' \
            --output text)
        
        # Get existing policy document
        aws iam get-policy-version \
            --policy-arn "$policy_arn" \
            --version-id "$current_version" \
            --profile "$AWS_PROFILE" \
            --query 'PolicyVersion.Document' \
            --output json > /tmp/existing-s3-policy.json
        
        # Normalize both JSON documents for comparison
        local new_policy_normalized=$(normalize_json /tmp/s3-access-policy.json)
        local existing_policy_normalized=$(normalize_json /tmp/existing-s3-policy.json)
        
        if [ "$new_policy_normalized" != "$existing_policy_normalized" ]; then
            log_warn "Policy content has changed, creating new version"
            
            # List all non-default versions for cleanup
            local all_versions=$(aws iam list-policy-versions \
                --policy-arn "$policy_arn" \
                --profile "$AWS_PROFILE" \
                --query 'Versions[?IsDefaultVersion==`false`].VersionId' \
                --output text)
            
            # Delete oldest non-default versions if we have 4 or more versions
            local version_count=$(aws iam list-policy-versions \
                --policy-arn "$policy_arn" \
                --profile "$AWS_PROFILE" \
                --query 'length(Versions)' \
                --output text)
            
            if [ "$version_count" -ge 4 ]; then
                log_info "Cleaning up old policy versions"
                local oldest_version=$(aws iam list-policy-versions \
                    --policy-arn "$policy_arn" \
                    --profile "$AWS_PROFILE" \
                    --query 'Versions[?IsDefaultVersion==`false`] | sort_by(@, &CreateDate) | [0].VersionId' \
                    --output text)
                
                if [ -n "$oldest_version" ] && [ "$oldest_version" != "None" ]; then
                    aws iam delete-policy-version \
                        --policy-arn "$policy_arn" \
                        --version-id "$oldest_version" \
                        --profile "$AWS_PROFILE" 2>/dev/null || true
                fi
            fi
            
            # Create new version
            aws iam create-policy-version \
                --policy-arn "$policy_arn" \
                --policy-document file:///tmp/s3-access-policy.json \
                --set-as-default \
                --profile "$AWS_PROFILE"
        else
            log_info "Policy content unchanged, skipping update"
        fi
        
        rm -f /tmp/existing-s3-policy.json
    else
        # Create new policy
        log_info "Creating new policy"
        aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document file:///tmp/s3-access-policy.json \
            --profile "$AWS_PROFILE"
    fi

    # Attach policy to role
    log_info "Attaching S3 policy to role"
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "$policy_arn" \
        --profile "$AWS_PROFILE" 2>/dev/null || log_warn "Policy may already be attached"

    rm -f /tmp/s3-access-policy.json
    log_info "S3 access policy created and attached successfully"
}

create_instance_profile() {
    local role_name=$1
    local profile_name="${role_name}-profile"

    log_info "Creating instance profile: $profile_name"

    if aws iam get-instance-profile --instance-profile-name "$profile_name" --profile "$AWS_PROFILE" 2>/dev/null; then
        log_warn "Instance profile $profile_name already exists"
        
        # Check if role is attached to the profile
        local attached_role=$(aws iam get-instance-profile \
            --instance-profile-name "$profile_name" \
            --profile "$AWS_PROFILE" \
            --query "InstanceProfile.Roles[?RoleName=='$role_name'].RoleName | [0]" \
            --output text 2>/dev/null)
        
        if [ -z "$attached_role" ] || [ "$attached_role" = "None" ]; then
            log_warn "Role $role_name not attached to profile, attaching now"
            aws iam add-role-to-instance-profile \
                --instance-profile-name "$profile_name" \
                --role-name "$role_name" \
                --profile "$AWS_PROFILE" 2>/dev/null || log_warn "Role may already be attached or attachment failed"
            
            # Wait for IAM propagation (skip in test mode)
            if [ "$TEST_MODE" != "true" ]; then
                log_info "Waiting for IAM changes to propagate..."
                sleep 10
            fi
        else
            log_info "Role $role_name is already attached to profile"
        fi
        
        export EB_INSTANCE_PROFILE="$profile_name"
        echo "$profile_name" > /tmp/eb-instance-profile.txt
        return 0
    fi

    aws iam create-instance-profile \
        --instance-profile-name "$profile_name" \
        --profile "$AWS_PROFILE"

    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "$role_name" \
        --profile "$AWS_PROFILE"

    # Wait a bit for IAM to propagate (skip in test mode)
    if [ "$TEST_MODE" != "true" ]; then
        log_info "Waiting for IAM changes to propagate..."
        sleep 10
    fi

    export EB_INSTANCE_PROFILE="$profile_name"
    echo "$profile_name" > /tmp/eb-instance-profile.txt

    log_info "Instance profile created successfully"
}

main() {
    log_info "Starting IAM role setup..."

    if [ "$USE_DEFAULT_IAM_ROLE" = "true" ]; then
        log_info "Using default Elastic Beanstalk IAM role"
        log_info "Adding S3 bucket policies to default role: aws-elasticbeanstalk-ec2-role"
        
        # Check if default role exists
        if ! aws iam get-role --role-name "aws-elasticbeanstalk-ec2-role" --profile "$AWS_PROFILE" 2>/dev/null; then
            log_warn "Default EB role doesn't exist. You may need to create it via EB console first"
            log_warn "Or set USE_DEFAULT_IAM_ROLE=false in config.env"
            exit 1
        fi

        create_and_attach_s3_policy "aws-elasticbeanstalk-ec2-role"
        
        export EB_INSTANCE_PROFILE="aws-elasticbeanstalk-ec2-role"
        echo "aws-elasticbeanstalk-ec2-role" > /tmp/eb-instance-profile.txt
    else
        log_info "Creating custom IAM role: $CUSTOM_IAM_ROLE_NAME"
        
        create_iam_role "$CUSTOM_IAM_ROLE_NAME"
        attach_managed_policies "$CUSTOM_IAM_ROLE_NAME"
        create_and_attach_s3_policy "$CUSTOM_IAM_ROLE_NAME"
        create_instance_profile "$CUSTOM_IAM_ROLE_NAME"
    fi

    log_info "IAM role setup completed successfully"
    echo ""
    echo "Instance Profile: $EB_INSTANCE_PROFILE"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

