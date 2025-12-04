#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    # Create a temporary SCRIPT_DIR for tests
    export ORIGINAL_SCRIPT_DIR="$SCRIPT_DIR"
    export SCRIPT_DIR="$TEST_TMPDIR"
    
    # Copy validation scripts to temp dir (without sourcing yet)
    mkdir -p "$TEST_TMPDIR/validate"
    
    # Create a modified version that doesn't auto-run
    sed '/^# Run all config validation checks/,$d' "$ORIGINAL_SCRIPT_DIR/validate/config.sh" > "$TEST_TMPDIR/validate/config.sh"
}

teardown() {
    export SCRIPT_DIR="$ORIGINAL_SCRIPT_DIR"
    teardown_test_env
}

# Helper to create a config.env with specific bucket names
create_bucket_test_config() {
    local static_bucket="$1"
    local uploads_bucket="$2"
    cat > "$TEST_TMPDIR/config.env" <<EOF
AWS_REGION=us-east-1
AWS_PROFILE=default
APP_NAME=test-app
ENV_NAME=test-env
EB_PLATFORM="Python 3.11"
DOMAIN_NAME=example.com
STATIC_ASSETS_BUCKET=$static_bucket
UPLOADS_BUCKET=$uploads_bucket
INSTANCE_TYPE=t3.micro
EOF
}

@test "validate_config_file succeeds with valid config" {
    create_bucket_test_config "test-static-assets" "test-uploads"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_config_file
    [ "$status" -eq 0 ]
    assert_output --partial "Configuration file is valid"
}

@test "validate_config_file fails when config file missing" {
    rm -f "$TEST_TMPDIR/config.env"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_config_file
    [ "$status" -ne 0 ]
    assert_output --partial "Configuration file not found"
}

@test "validate_config_file fails when required variable missing" {
    # Create config without AWS_REGION (empty value)
    cat > "$TEST_TMPDIR/config.env" <<EOF
AWS_REGION=
AWS_PROFILE=default
APP_NAME=test-app
ENV_NAME=test-env
EB_PLATFORM="Python 3.11"
DOMAIN_NAME=example.com
STATIC_ASSETS_BUCKET=test-static
UPLOADS_BUCKET=test-uploads
INSTANCE_TYPE=t3.micro
EOF
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_config_file
    [ "$status" -ne 0 ]
    assert_output --partial "Required variable not set"
}

@test "validate_bucket_names succeeds with valid bucket names" {
    create_bucket_test_config "valid-bucket-name" "another-valid-bucket"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_bucket_names
    [ "$status" -eq 0 ]
    assert_output --partial "Bucket name valid"
}

@test "validate_bucket_names fails with too short name" {
    create_bucket_test_config "ab" "test-uploads"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name length"
}

@test "validate_bucket_names fails with too long name" {
    local long_name=$(printf 'a%.0s' {1..64})
    create_bucket_test_config "$long_name" "test-uploads"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name length"
}

@test "validate_bucket_names fails with invalid characters" {
    create_bucket_test_config "Invalid_Bucket_Name" "test-uploads"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name format"
}

@test "validate_bucket_names fails with leading hyphen" {
    create_bucket_test_config "-invalid-bucket" "test-uploads"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name format"
}

@test "validate_bucket_names fails with trailing hyphen" {
    create_bucket_test_config "invalid-bucket-" "test-uploads"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name format"
}

@test "validate_bucket_names accepts minimum valid length" {
    create_bucket_test_config "abc" "test-uploads"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_bucket_names
    [ "$status" -eq 0 ]
}

@test "validate_bucket_names accepts maximum valid length" {
    local max_name=$(printf 'a%.0s' {1..63})
    create_bucket_test_config "$max_name" "test-uploads"
    source "$TEST_TMPDIR/validate/config.sh"
    
    run validate_bucket_names
    [ "$status" -eq 0 ]
}
