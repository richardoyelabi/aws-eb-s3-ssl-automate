#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env

    # Extract and source only the utility functions we need
    local cleanup_func=$(sed -n '/^cleanup_temp_files() {/,/^}$/p' "$SCRIPT_DIR/setup-eb-environment.sh")
    local show_usage_func=$(sed -n '/^show_usage() {/,/^}$/p' "$SCRIPT_DIR/setup-eb-environment.sh" | sed 's/\$0/setup-eb-environment.sh/g')

    eval "$cleanup_func"
    eval "$show_usage_func"
}

teardown() {
    teardown_test_env
}

@test "cleanup_temp_files removes environment-specific temp directory" {
    # Create a test INFRA_TMP_DIR with files
    export INFRA_TMP_DIR=$(mktemp -d)
    echo "test" > "$INFRA_TMP_DIR/acm-cert-arn.txt"
    echo "test" > "$INFRA_TMP_DIR/eb-options.json"
    echo "test" > "$INFRA_TMP_DIR/cors-config.json"

    [ -d "$INFRA_TMP_DIR" ]

    # Run cleanup
    run cleanup_temp_files

    [ "$status" -eq 0 ]
    [ ! -d "$INFRA_TMP_DIR" ]
}

@test "cleanup_temp_files handles missing directory gracefully" {
    export INFRA_TMP_DIR="/tmp/nonexistent-infra-dir-$$"

    # Run cleanup on non-existent directory
    run cleanup_temp_files

    [ "$status" -eq 0 ]
}

@test "cleanup_temp_files handles unset INFRA_TMP_DIR gracefully" {
    unset INFRA_TMP_DIR

    run cleanup_temp_files

    [ "$status" -eq 0 ]
}

@test "cleanup_temp_files removes only its own directory" {
    # Create INFRA_TMP_DIR and a sibling file
    export INFRA_TMP_DIR=$(mktemp -d)
    echo "test" > "$INFRA_TMP_DIR/eb-options.json"
    echo "should remain" > "/tmp/unrelated-file-$$.txt"

    run cleanup_temp_files

    [ "$status" -eq 0 ]
    [ ! -d "$INFRA_TMP_DIR" ]
    [ -f "/tmp/unrelated-file-$$.txt" ]

    rm -f "/tmp/unrelated-file-$$.txt"
}

@test "show_usage displays help text" {
    run show_usage

    [ "$status" -eq 0 ]
    assert_output --partial "Usage: setup-eb-environment.sh [OPTIONS]"
    assert_output --partial "AWS Elastic Beanstalk Environment Setup Script"
    assert_output --partial "OPTIONS:"
    assert_output --partial "-h, --help"
    assert_output --partial "-c, --config FILE"
    assert_output --partial "--skip-ssl"
    assert_output --partial "--dry-run"
    assert_output --partial "-y, --yes"
    assert_output --partial "Non-interactive"
    assert_output --partial "CI=true"
    assert_output --partial "EXAMPLES:"
    assert_output --partial "PREREQUISITES:"
    assert_output --partial "For more information, see README.md"
}

@test "show_usage includes all command line options" {
    run show_usage

    [ "$status" -eq 0 ]
    assert_output --partial "--help"
    assert_output --partial "--config FILE"
    assert_output --partial "--env NAME"
    assert_output --partial "--skip-ssl"
    assert_output --partial "--dry-run"
    assert_output --partial "--yes"
}

@test "show_usage documents non-interactive example" {
    run show_usage

    [ "$status" -eq 0 ]
    assert_output --partial "Unattended / CI"
    assert_output --partial "--yes"
}

@test "show_usage includes examples" {
    run show_usage

    [ "$status" -eq 0 ]
    assert_output --partial "# Standard setup"
    assert_output --partial "./setup-eb-environment.sh"
    assert_output --partial "# Use custom config file"
    assert_output --partial "--config my-config.env"
    assert_output --partial "# Use per-environment file"
    assert_output --partial "--env staging"
    assert_output --partial "# Validate configuration only"
    assert_output --partial "--dry-run"
}

@test "show_usage includes prerequisites" {
    run show_usage

    [ "$status" -eq 0 ]
    assert_output --partial "PREREQUISITES:"
    assert_output --partial "AWS CLI installed and configured"
    assert_output --partial "Valid AWS credentials"
    assert_output --partial "ACM certificate for your domain"
}

@test "show_usage output format is consistent" {
    run show_usage

    [ "$status" -eq 0 ]

    # Check that output starts with "Usage:"
    [[ "${lines[0]}" =~ ^Usage:\ .* ]]

    # Check that description follows
    [[ "${lines[1]}" =~ AWS\ Elastic\ Beanstalk\ Environment\ Setup\ Script ]]

    # Check that OPTIONS section exists
    assert_output --partial "OPTIONS:"
}

@test "show_usage handles script name correctly" {
    # The usage should show the correct script name
    run show_usage

    [ "$status" -eq 0 ]
    assert_output --partial "setup-eb-environment.sh"
}
