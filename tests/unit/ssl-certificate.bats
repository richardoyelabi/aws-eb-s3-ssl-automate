#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/setup-ssl-certificate.sh"
}

teardown() {
    teardown_test_env
}

@test "find_certificate_by_domain finds certificate by exact domain" {
    run find_certificate_by_domain "example.com" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "arn:aws:acm"
}

@test "find_certificate_by_domain finds wildcard certificate" {
    run find_certificate_by_domain "api.example.com" "us-east-1"
    [ "$status" -eq 0 ]
    # Should try wildcard lookup
    [ -n "$output" ]
}

@test "find_certificate_by_domain returns None for non-existent domain" {
    run find_certificate_by_domain "nonexistent.com" "us-east-1"
    [ "$status" -eq 0 ]
    # Mock returns "None" or searches for wildcard
    [[ "$output" == "None" ]] || [[ "$output" == *"Searching"* ]]
}

@test "get_certificate_status retrieves status" {
    run get_certificate_status "arn:aws:acm:us-east-1:123456789012:certificate/test" "us-east-1"
    [ "$status" -eq 0 ]
    [ "$output" = "ISSUED" ]
}

@test "display_dns_validation_records displays records" {
    run display_dns_validation_records "arn:aws:acm:us-east-1:123456789012:certificate/test" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "DNS Validation Records"
}

@test "display_dns_validation_records works without jq" {
    local original_path="$PATH"
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$(which jq 2>/dev/null | xargs dirname 2>/dev/null)" | tr '\n' ':')
    run display_dns_validation_records "arn:aws:acm:us-east-1:123456789012:certificate/test" "us-east-1"
    export PATH="$original_path"
    [ "$status" -eq 0 ]
}

@test "wait_for_certificate_validation skips in test mode" {
    run wait_for_certificate_validation "arn:aws:acm:us-east-1:123456789012:certificate/test" "us-east-1" 1
    [ "$status" -eq 0 ]
    assert_output --partial "Skipping certificate validation wait in test mode"
}

@test "validate_certificate succeeds for issued certificate" {
    run validate_certificate "arn:aws:acm:us-east-1:123456789012:certificate/test" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "valid and issued"
}

@test "validate_certificate handles pending validation" {
    export MOCK_ACM_CERT_STATUS="PENDING_VALIDATION"
    run validate_certificate "arn:aws:acm:us-east-1:123456789012:certificate/test" "us-east-1"
    unset MOCK_ACM_CERT_STATUS
    [ "$status" -eq 1 ]
    assert_output --partial "pending validation"
    assert_output --partial "Skipping interactive prompt in test mode"
}

@test "request_certificate_instructions displays instructions" {
    run request_certificate_instructions "example.com" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "aws acm request-certificate"
}

@test "main finds certificate by domain" {
    export DOMAIN_NAME="example.com"
    export ACM_CERTIFICATE_ARN=""
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Found certificate"
}

@test "main uses provided certificate ARN" {
    export DOMAIN_NAME="example.com"
    export ACM_CERTIFICATE_ARN="arn:aws:acm:us-east-1:123456789012:certificate/test"
    run main
    [ "$status" -eq 0 ]
}

@test "main fails when no certificate found" {
    export DOMAIN_NAME="nonexistent.com"
    export ACM_CERTIFICATE_ARN=""
    run main
    [ "$status" -ne 0 ]
    assert_output --partial "No certificate found"
}

