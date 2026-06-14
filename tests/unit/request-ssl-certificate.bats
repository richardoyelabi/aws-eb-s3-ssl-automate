#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/request-ssl-certificate.sh"
}

teardown() {
    teardown_test_env
}

@test "request_certificate returns an ACM certificate ARN" {
    run request_certificate "newdomain.com" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "arn:aws:acm"
}

@test "wait_for_validation_records skips in test mode" {
    run wait_for_validation_records "arn:aws:acm:us-east-1:123456789012:certificate/test" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "main reuses existing certificate and shows DNS records" {
    export DOMAIN_NAME="example.com"
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Found existing certificate"
    assert_output --partial "DNS Validation Records"
    # Must not request a new certificate when one already exists
    refute_output --partial "requesting a new"
}

@test "main requests a new certificate when none exists" {
    export DOMAIN_NAME="newdomain.com"
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "requesting a new"
    assert_output --partial "DNS Validation Records"
}

@test "main accepts a positional domain argument" {
    unset DOMAIN_NAME
    run main "example.com"
    [ "$status" -eq 0 ]
    assert_output --partial "Found existing certificate"
}

@test "show_usage displays help text" {
    run show_usage
    [ "$status" -eq 0 ]
    assert_output --partial "Usage:"
}

@test "main --help displays usage" {
    run main --help
    [ "$status" -eq 0 ]
    assert_output --partial "Usage:"
}
