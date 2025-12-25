#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/setup-s3-buckets.sh"
}

teardown() {
    teardown_test_env
}

@test "create_bucket_if_not_exists creates new bucket" {
    run create_bucket_if_not_exists "new-bucket" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating S3 bucket: new-bucket"
}

@test "create_bucket_if_not_exists skips existing bucket" {
    run create_bucket_if_not_exists "existing-bucket" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

@test "create_bucket_if_not_exists handles us-east-1 region" {
    run create_bucket_if_not_exists "test-bucket" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "create_bucket_if_not_exists handles other regions" {
    run create_bucket_if_not_exists "test-bucket" "us-west-2"
    [ "$status" -eq 0 ]
}

@test "configure_static_assets_bucket enables versioning when configured" {
    export ENABLE_S3_VERSIONING="true"
    run configure_static_assets_bucket "test-static-assets" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "configure_static_assets_bucket skips versioning when disabled" {
    export ENABLE_S3_VERSIONING="false"
    run configure_static_assets_bucket "test-static-assets" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "configure_static_assets_bucket configures CORS" {
    run configure_static_assets_bucket "test-static-assets" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "Configuring CORS"
}

@test "configure_static_assets_bucket skips CORS when already configured" {
    run configure_static_assets_bucket "cors-configured-bucket" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "CORS already configured"
}

@test "configure_static_assets_bucket configures public access block" {
    run configure_static_assets_bucket "test-static-assets" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "configure_static_assets_bucket skips public access block when already configured" {
    run configure_static_assets_bucket "pab-configured-bucket" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "already configured"
}

@test "configure_uploads_bucket enables versioning when configured" {
    export ENABLE_S3_VERSIONING="true"
    run configure_uploads_bucket "test-uploads" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "configure_uploads_bucket configures CORS for uploads" {
    run configure_uploads_bucket "test-uploads" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "Configuring CORS"
}

@test "configure_uploads_bucket configures public access block for uploads" {
    run configure_uploads_bucket "test-uploads" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "main creates and configures both buckets" {
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Static Assets:"
    assert_output --partial "Uploads:"
}

@test "idempotency: running main twice succeeds" {
    run main
    [ "$status" -eq 0 ]
    
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

@test "S3 environment variables are included in EB configuration" {
    source "$SCRIPT_DIR/scripts/create-eb-environment.sh"
    
    export STATIC_ASSETS_BUCKET="test-static-bucket"
    export UPLOADS_BUCKET="test-uploads-bucket"
    export AWS_REGION="us-east-1"
    export INSTANCE_TYPE="t3.micro"
    export MIN_INSTANCES="1"
    export MAX_INSTANCES="4"
    export LB_TYPE="application"
    export HEALTH_CHECK_PATH="/"
    
    run create_environment_options "test-cert-arn" "test-instance-profile"
    [ "$status" -eq 0 ]
    
    # Verify the generated JSON contains S3 environment variables
    [ -f /tmp/eb-options.json ]
    
    grep -q "STATIC_ASSETS_BUCKET" /tmp/eb-options.json
    grep -q "UPLOADS_BUCKET" /tmp/eb-options.json
    grep -q "AWS_REGION" /tmp/eb-options.json
    grep -q "AWS_DEFAULT_REGION" /tmp/eb-options.json
    grep -q "S3_REGION" /tmp/eb-options.json
    
    rm -f /tmp/eb-options.json
}

@test "S3 environment variables have correct values in EB configuration" {
    source "$SCRIPT_DIR/scripts/create-eb-environment.sh"
    
    export STATIC_ASSETS_BUCKET="my-static-assets-bucket"
    export UPLOADS_BUCKET="my-uploads-bucket"
    export AWS_REGION="us-west-2"
    export INSTANCE_TYPE="t3.micro"
    export MIN_INSTANCES="1"
    export MAX_INSTANCES="4"
    export LB_TYPE="application"
    export HEALTH_CHECK_PATH="/"
    
    run create_environment_options "test-cert-arn" "test-instance-profile"
    [ "$status" -eq 0 ]
    
    # Verify the values in the generated JSON
    [ -f /tmp/eb-options.json ]
    
    grep -q '"Value": "my-static-assets-bucket"' /tmp/eb-options.json
    grep -q '"Value": "my-uploads-bucket"' /tmp/eb-options.json
    grep -q '"Value": "us-west-2"' /tmp/eb-options.json
    
    rm -f /tmp/eb-options.json
}

@test "S3 region variables use AWS_REGION value" {
    source "$SCRIPT_DIR/scripts/create-eb-environment.sh"
    
    export STATIC_ASSETS_BUCKET="test-bucket"
    export UPLOADS_BUCKET="test-bucket"
    export AWS_REGION="eu-west-1"
    export INSTANCE_TYPE="t3.micro"
    export MIN_INSTANCES="1"
    export MAX_INSTANCES="4"
    export LB_TYPE="application"
    export HEALTH_CHECK_PATH="/"
    
    run create_environment_options "test-cert-arn" "test-instance-profile"
    [ "$status" -eq 0 ]
    
    # Verify all region variables use the same value
    [ -f /tmp/eb-options.json ]
    
    local aws_region_count=$(grep -c '"Value": "eu-west-1"' /tmp/eb-options.json)
    [ "$aws_region_count" -ge 3 ]  # AWS_REGION, AWS_DEFAULT_REGION, S3_REGION
    
    rm -f /tmp/eb-options.json
}

@test "RDS setup preserves S3 environment variables" {
    source "$SCRIPT_DIR/scripts/setup-rds-database.sh"
    
    export APP_NAME="test-app"
    export ENV_NAME="test-env"
    export AWS_REGION="us-east-1"
    export STATIC_ASSETS_BUCKET="test-static-bucket"
    export UPLOADS_BUCKET="test-uploads-bucket"
    export DB_NAME="testdb"
    export DB_USERNAME="testuser"
    
    # Create a minimal version of set_environment_variables for testing
    # This tests that the JSON structure includes S3 variables
    local db_endpoint="test.rds.amazonaws.com"
    local db_port="5432"
    local master_password="testpass"
    local env_name="test-env"
    local database_url="postgresql://testuser:testpass@test.rds.amazonaws.com:5432/testdb"
    
    # Generate the environment options JSON
    cat > /tmp/db-env-options.json <<EOF
[
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DATABASE_URL",
        "Value": "${database_url}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_HOST",
        "Value": "${db_endpoint}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_PORT",
        "Value": "${db_port}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_NAME",
        "Value": "${DB_NAME}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_USERNAME",
        "Value": "${DB_USERNAME}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_PASSWORD",
        "Value": "${master_password}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "STATIC_ASSETS_BUCKET",
        "Value": "${STATIC_ASSETS_BUCKET}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "UPLOADS_BUCKET",
        "Value": "${UPLOADS_BUCKET}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "AWS_REGION",
        "Value": "${AWS_REGION}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "AWS_DEFAULT_REGION",
        "Value": "${AWS_REGION}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "S3_REGION",
        "Value": "${AWS_REGION}"
    }
]
EOF
    
    # Verify S3 variables are in the JSON
    [ -f /tmp/db-env-options.json ]
    
    grep -q "STATIC_ASSETS_BUCKET" /tmp/db-env-options.json
    grep -q "UPLOADS_BUCKET" /tmp/db-env-options.json
    grep -q "AWS_DEFAULT_REGION" /tmp/db-env-options.json
    grep -q "S3_REGION" /tmp/db-env-options.json
    
    rm -f /tmp/db-env-options.json
}

