#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
    export ORIGINAL_SCRIPT_DIR="$SCRIPT_DIR"
    export SCRIPT_DIR="$TEST_TMPDIR"
    unset INFRA_CONFIG INFRA_ENV INFRA_CONFIG_PATH
    mkdir -p "$TEST_TMPDIR/scripts"
    cp "$ORIGINAL_SCRIPT_DIR/scripts/load-infrastructure-config.sh" "$TEST_TMPDIR/scripts/"
}

teardown() {
    export SCRIPT_DIR="$ORIGINAL_SCRIPT_DIR"
    teardown_test_env
}

@test "infrastructure_config_resolve_path defaults to config.env" {
    # shellcheck disable=SC1091
    source "$TEST_TMPDIR/scripts/load-infrastructure-config.sh"
    run infrastructure_config_resolve_path "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMPDIR/config.env" ]
}

@test "infrastructure_config_resolve_path uses INFRA_ENV for config.NAME.env" {
    unset INFRA_CONFIG INFRA_CONFIG_PATH
    export INFRA_ENV="staging"
    # shellcheck disable=SC1091
    source "$TEST_TMPDIR/scripts/load-infrastructure-config.sh"
    run infrastructure_config_resolve_path "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMPDIR/config.staging.env" ]
}

@test "infrastructure_config_resolve_path prefers INFRA_CONFIG over INFRA_ENV" {
    export INFRA_CONFIG="$TEST_TMPDIR/custom.env"
    export INFRA_ENV="staging"
    # shellcheck disable=SC1091
    source "$TEST_TMPDIR/scripts/load-infrastructure-config.sh"
    run infrastructure_config_resolve_path "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMPDIR/custom.env" ]
}

@test "infrastructure_config_load reads config.staging.env when INFRA_ENV is set" {
    cat > "$TEST_TMPDIR/config.staging.env" <<EOF
AWS_REGION=us-west-2
AWS_PROFILE=staging-profile
APP_NAME=staging-app
ENV_NAME=staging-eb
EB_PLATFORM="Python 3.11"
DOMAIN_NAME=example.com
STATIC_ASSETS_BUCKET=staging-static
UPLOADS_BUCKET=staging-uploads
INSTANCE_TYPE=t3.micro
EOF
    unset INFRA_CONFIG INFRA_CONFIG_PATH
    export INFRA_ENV="staging"
    run bash -c "source \"$TEST_TMPDIR/scripts/load-infrastructure-config.sh\" && infrastructure_config_load \"$TEST_TMPDIR\" && echo \"\$AWS_PROFILE\""
    [ "$status" -eq 0 ]
    assert_output --partial "staging-profile"
}

@test "setup-eb-environment.sh does not source config.env before main" {
    run grep -n 'source.*config\.env' "$ORIGINAL_SCRIPT_DIR/setup-eb-environment.sh"
    [ "$status" -eq 1 ]
}
