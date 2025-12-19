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

@test "cleanup_temp_files removes all expected temp files" {
    # Create test temp files
    local temp_files=(
        "/tmp/acm-cert-arn.txt"
        "/tmp/eb-instance-profile.txt"
        "/tmp/eb-env-url.txt"
        "/tmp/cors-config-test.json"
        "/tmp/eb-trust-policy.json"
        "/tmp/s3-access-policy.json"
        "/tmp/eb-options.json"
        "/tmp/https-options.json"
        "/tmp/custom-domain.txt"
        "/tmp/route53-test1.json"
        "/tmp/route53-test2.json"
    )

    # Create the temp files
    for file in "${temp_files[@]}"; do
        echo "test content" > "$file"
        [ -f "$file" ]  # Verify file was created
    done

    # Run cleanup function
    run cleanup_temp_files

    # Verify function succeeded
    [ "$status" -eq 0 ]

    # Verify all temp files were removed
    for file in "${temp_files[@]}"; do
        [ ! -f "$file" ]  # File should not exist
    done
}

@test "cleanup_temp_files handles missing files gracefully" {
    # Ensure temp files don't exist
    rm -f /tmp/acm-cert-arn.txt
    rm -f /tmp/eb-instance-profile.txt
    rm -f /tmp/eb-env-url.txt
    rm -f /tmp/cors-config*.json
    rm -f /tmp/eb-trust-policy.json
    rm -f /tmp/s3-access-policy.json
    rm -f /tmp/eb-options.json
    rm -f /tmp/https-options.json
    rm -f /tmp/custom-domain.txt
    rm -f /tmp/route53-*.json

    # Run cleanup function on non-existent files
    run cleanup_temp_files

    # Should succeed even if files don't exist
    [ "$status" -eq 0 ]
}

@test "cleanup_temp_files handles wildcard patterns correctly" {
    # Create files matching wildcard patterns
    echo "cors1" > "/tmp/cors-config1.json"
    echo "cors2" > "/tmp/cors-config2.json"
    echo "route1" > "/tmp/route53-1.json"
    echo "route2" > "/tmp/route53-2.json"

    # Run cleanup
    run cleanup_temp_files

    # Verify wildcard files were removed
    [ ! -f "/tmp/cors-config1.json" ]
    [ ! -f "/tmp/cors-config2.json" ]
    [ ! -f "/tmp/route53-1.json" ]
    [ ! -f "/tmp/route53-2.json" ]
}

@test "cleanup_temp_files removes only expected files" {
    # Create expected temp files and one unrelated file
    echo "temp1" > "/tmp/acm-cert-arn.txt"
    echo "temp2" > "/tmp/eb-instance-profile.txt"
    echo "should remain" > "/tmp/unrelated-file.txt"

    # Run cleanup
    run cleanup_temp_files

    # Expected files should be removed
    [ ! -f "/tmp/acm-cert-arn.txt" ]
    [ ! -f "/tmp/eb-instance-profile.txt" ]

    # Unrelated file should remain
    [ -f "/tmp/unrelated-file.txt" ]

    # Clean up the unrelated file
    rm -f "/tmp/unrelated-file.txt"
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
    assert_output --partial "EXAMPLES:"
    assert_output --partial "PREREQUISITES:"
    assert_output --partial "For more information, see README.md"
}

@test "show_usage includes all command line options" {
    run show_usage

    [ "$status" -eq 0 ]
    assert_output --partial "--help"
    assert_output --partial "--config FILE"
    assert_output --partial "--skip-ssl"
    assert_output --partial "--dry-run"
}

@test "show_usage includes examples" {
    run show_usage

    [ "$status" -eq 0 ]
    assert_output --partial "# Standard setup"
    assert_output --partial "./setup-eb-environment.sh"
    assert_output --partial "# Use custom config file"
    assert_output --partial "--config my-config.env"
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
