#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    export ORIGINAL_SCRIPT_DIR="$SCRIPT_DIR"
    export SCRIPT_DIR="$TEST_TMPDIR"

    mkdir -p "$TEST_TMPDIR/validate"
    # Strip auto-load and auto-run footer so tests control when config is loaded
    sed '/^# shellcheck disable=SC1091$/,/^fi$/d' "$ORIGINAL_SCRIPT_DIR/validate/config.sh" \
        | sed '/^# Run all config validation checks/,$d' > "$TEST_TMPDIR/validate/config.sh"
}

load_fixture_config() {
    unset INFRA_CONFIG INFRA_ENV INFRA_CONFIG_PATH
    # shellcheck disable=SC1091
    source "$ORIGINAL_SCRIPT_DIR/scripts/load-infrastructure-config.sh"
    infrastructure_config_load "$TEST_TMPDIR"
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
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_config_file
    [ "$status" -eq 0 ]
    assert_output --partial "Configuration file is valid"
}

@test "infrastructure_config_load fails when default config file missing" {
    rm -f "$TEST_TMPDIR/config.env"
    unset INFRA_CONFIG INFRA_ENV INFRA_CONFIG_PATH
    # shellcheck disable=SC1091
    source "$ORIGINAL_SCRIPT_DIR/scripts/load-infrastructure-config.sh"
    run infrastructure_config_load "$TEST_TMPDIR"
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
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_config_file
    [ "$status" -ne 0 ]
    assert_output --partial "Required variable not set"
}

@test "validate_bucket_names succeeds with valid bucket names" {
    create_bucket_test_config "valid-bucket-name" "another-valid-bucket"
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_bucket_names
    [ "$status" -eq 0 ]
    assert_output --partial "Bucket name valid"
}

@test "validate_bucket_names fails with too short name" {
    create_bucket_test_config "ab" "test-uploads"
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name length"
}

@test "validate_bucket_names fails with too long name" {
    local long_name=$(printf 'a%.0s' {1..64})
    create_bucket_test_config "$long_name" "test-uploads"
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name length"
}

@test "validate_bucket_names fails with invalid characters" {
    create_bucket_test_config "Invalid_Bucket_Name" "test-uploads"
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name format"
}

@test "validate_bucket_names fails with leading hyphen" {
    create_bucket_test_config "-invalid-bucket" "test-uploads"
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name format"
}

@test "validate_bucket_names fails with trailing hyphen" {
    create_bucket_test_config "invalid-bucket-" "test-uploads"
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_bucket_names
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid bucket name format"
}

@test "validate_bucket_names accepts minimum valid length" {
    create_bucket_test_config "abc" "test-uploads"
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_bucket_names
    [ "$status" -eq 0 ]
}

@test "validate_bucket_names accepts maximum valid length" {
    local max_name=$(printf 'a%.0s' {1..63})
    create_bucket_test_config "$max_name" "test-uploads"
    load_fixture_config
    source "$TEST_TMPDIR/validate/config.sh"

    run validate_bucket_names
    [ "$status" -eq 0 ]
}
