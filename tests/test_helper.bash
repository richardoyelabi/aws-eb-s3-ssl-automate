#!/usr/bin/env bash

# Shared test utilities for bats-core tests

load '../bats-support/load'
load '../bats-assert/load'

# Project-specific test setup
setup_test_env() {
    export TEST_MODE=true
    export SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_DIRNAME}")/.." && pwd)"

    # Set default test configuration
    export AWS_REGION="${AWS_REGION:-us-east-1}"
    export AWS_PROFILE="${AWS_PROFILE:-default}"
    export APP_NAME="${APP_NAME:-test-app}"
    export ENV_NAME="${ENV_NAME:-test-env}"
    export STATIC_ASSETS_BUCKET="${STATIC_ASSETS_BUCKET:-test-static-assets}"
    export UPLOADS_BUCKET="${UPLOADS_BUCKET:-test-uploads}"
    export INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
    export MIN_INSTANCES="${MIN_INSTANCES:-1}"
    export MAX_INSTANCES="${MAX_INSTANCES:-2}"
    export LB_TYPE="${LB_TYPE:-application}"
    export SSL_POLICY="${SSL_POLICY:-ELBSecurityPolicy-TLS13-1-2-2021-06}"
    export USE_DEFAULT_IAM_ROLE="${USE_DEFAULT_IAM_ROLE:-false}"
    export CUSTOM_IAM_ROLE_NAME="${CUSTOM_IAM_ROLE_NAME:-test-role}"
    export ENABLE_S3_VERSIONING="${ENABLE_S3_VERSIONING:-false}"
    export ENABLE_HTTPS_REDIRECT="${ENABLE_HTTPS_REDIRECT:-true}"
    export HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/}"
    export DOMAIN_NAME="${DOMAIN_NAME:-example.com}"
    export CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-}"
    export AUTO_CONFIGURE_DNS="${AUTO_CONFIGURE_DNS:-false}"

    # Create temporary directory for test artifacts
    export TEST_TMPDIR=$(mktemp -d)
}

teardown_test_env() {
    unset TEST_MODE
    # Cleanup test artifacts
    if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
    # Cleanup any temp files created during tests
    rm -f /tmp/*-config.json /tmp/*-policy.json /tmp/*-trust-policy.json /tmp/*-record.json 2>/dev/null || true
}

# Helper function to create a temporary config file
create_test_config() {
    local config_file="$TEST_TMPDIR/config.env"
    cat > "$config_file" <<EOF
AWS_REGION=$AWS_REGION
AWS_PROFILE=$AWS_PROFILE
APP_NAME=$APP_NAME
ENV_NAME=$ENV_NAME
STATIC_ASSETS_BUCKET=$STATIC_ASSETS_BUCKET
UPLOADS_BUCKET=$UPLOADS_BUCKET
INSTANCE_TYPE=$INSTANCE_TYPE
MIN_INSTANCES=$MIN_INSTANCES
MAX_INSTANCES=$MAX_INSTANCES
LB_TYPE=$LB_TYPE
SSL_POLICY=$SSL_POLICY
USE_DEFAULT_IAM_ROLE=$USE_DEFAULT_IAM_ROLE
CUSTOM_IAM_ROLE_NAME=$CUSTOM_IAM_ROLE_NAME
ENABLE_S3_VERSIONING=$ENABLE_S3_VERSIONING
ENABLE_HTTPS_REDIRECT=$ENABLE_HTTPS_REDIRECT
HEALTH_CHECK_PATH=$HEALTH_CHECK_PATH
DOMAIN_NAME=$DOMAIN_NAME
CUSTOM_DOMAIN=$CUSTOM_DOMAIN
AUTO_CONFIGURE_DNS=$AUTO_CONFIGURE_DNS
EOF
    echo "$config_file"
}

# Helper function to source a script and make functions available
load_script() {
    local script_path="$1"
    if [ ! -f "$script_path" ]; then
        echo "Script not found: $script_path" >&2
        return 1
    fi
    # Source the script in a subshell to avoid polluting the test environment
    # We'll need to export functions we want to test
    source "$script_path"
}
