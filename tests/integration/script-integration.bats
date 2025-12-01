#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "config.env can be sourced" {
    # Test that config.env can be sourced independently
    source "$SCRIPT_DIR/config.env"

    # Check that key variables are available
    [ -n "$AWS_REGION" ]
    [ -n "$APP_NAME" ]
    [ -n "$ENV_NAME" ]
}
