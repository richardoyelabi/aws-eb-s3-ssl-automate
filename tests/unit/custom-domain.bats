#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/configure-custom-domain.sh"
}

teardown() {
    teardown_test_env
}

# Domain validation tests (from original domain-validation.bats)
@test "validate_domain_format accepts valid domains" {
    run validate_domain_format "example.com"
    [ "$status" -eq 0 ]

    run validate_domain_format "api.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain_format rejects invalid domains" {
    run validate_domain_format "-example.com"
    [ "$status" -eq 1 ]

    run validate_domain_format "example..com"
    [ "$status" -eq 1 ]

    run validate_domain_format ""
    [ "$status" -eq 1 ]
}

@test "validate_domain_format rejects domains with protocol" {
    run validate_domain_format "http://example.com"
    [ "$status" -eq 1 ]

    run validate_domain_format "https://example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain_format accepts subdomains" {
    run validate_domain_format "www.example.com"
    [ "$status" -eq 0 ]
    
    run validate_domain_format "api.v1.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain_format rejects domains starting with dot" {
    run validate_domain_format ".example.com"
    [ "$status" -eq 1 ]
}

@test "get_load_balancer_dns retrieves DNS name" {
    export ENV_NAME="test-env"
    run get_load_balancer_dns "test-env"
    [ "$status" -eq 0 ]
    assert_output --partial "test-lb-1234567890.us-east-1.elb.amazonaws.com"
}

@test "get_load_balancer_dns handles missing load balancer" {
    run get_load_balancer_dns "nonexistent-env"
    [ "$status" -ne 0 ]
    assert_output --partial "Could not find load balancer"
}

@test "get_load_balancer_hosted_zone retrieves zone ID" {
    export ENV_NAME="test-env"
    run get_load_balancer_hosted_zone "test-env"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    assert_output --partial "Z35SXDOTRQ7X7K"
}

@test "get_load_balancer_dns handles ARN extraction correctly" {
    export ENV_NAME="test-env"
    # Mock should return ARN, function should extract name and work correctly
    run get_load_balancer_dns "test-env"
    [ "$status" -eq 0 ]
    assert_output --partial "test-lb-1234567890.us-east-1.elb.amazonaws.com"
}

@test "detect_dns_provider detects GoDaddy" {
    run detect_dns_provider "godaddy.com"
    [ "$status" -eq 0 ]
    [ "$output" = "GoDaddy" ]
}

@test "detect_dns_provider detects Route 53" {
    run detect_dns_provider "example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "Route 53" ]
}

@test "detect_dns_provider returns Unknown when dig unavailable" {
    set_mock_dig_available "false"
    run detect_dns_provider "example.com"
    set_mock_dig_available "true"
    [ "$status" -eq 0 ]
    [ "$output" = "Unknown" ]
}

@test "check_existing_dns_record returns MATCHES when record exists and matches" {
    run check_existing_dns_record "Z1234567890ABC" "existing.example.com" "CNAME" "test-lb.us-east-1.elb.amazonaws.com"
    [ "$status" -eq 0 ]
    [ "$output" = "MATCHES" ]
}

@test "check_existing_dns_record returns DIFFERENT when record exists but different" {
    run check_existing_dns_record "Z1234567890ABC" "existing.example.com" "CNAME" "different-lb.us-east-1.elb.amazonaws.com"
    [ "$status" -eq 0 ]
    assert_output --partial "DIFFERENT"
}

@test "check_existing_dns_record returns NOT_FOUND when record doesn't exist" {
    run check_existing_dns_record "Z1234567890ABC" "nonexistent.example.com" "CNAME" "test-lb.us-east-1.elb.amazonaws.com"
    [ "$status" -eq 0 ]
    [ "$output" = "NOT_FOUND" ]
}

@test "configure_domain_with_route53 creates DNS record for new domain" {
    export CUSTOM_DOMAIN="new.example.com"
    run configure_domain_with_route53 "new.example.com" "test-lb.us-east-1.elb.amazonaws.com" "Z35SXDOTRQ7X7K"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating new DNS record"
}

@test "configure_domain_with_route53 skips when record already matches" {
    export CUSTOM_DOMAIN="existing.example.com"
    run configure_domain_with_route53 "existing.example.com" "test-lb.us-east-1.elb.amazonaws.com" "Z35SXDOTRQ7X7K"
    [ "$status" -eq 0 ]
    assert_output --partial "already exists and is correctly configured"
}

@test "configure_domain_with_route53 handles missing hosted zone" {
    run configure_domain_with_route53 "nonexistent.com" "test-lb.us-east-1.elb.amazonaws.com" "Z35SXDOTRQ7X7K"
    [ "$status" -ne 0 ]
    assert_output --partial "No Route 53 hosted zone found"
}

@test "verify_domain_configuration verifies DNS resolution" {
    run verify_domain_configuration "example.com" "test-lb.us-east-1.elb.amazonaws.com"
    [ "$status" -eq 0 ]
}

@test "verify_domain_configuration handles missing dig" {
    set_mock_dig_available "false"
    run verify_domain_configuration "example.com" "test-lb.us-east-1.elb.amazonaws.com"
    set_mock_dig_available "true"
    [ "$status" -eq 0 ]
    assert_output --partial "dig command not available"
}

@test "test_https_endpoint tests HTTPS connection" {
    run test_https_endpoint "example.com"
    [ "$status" -eq 0 ]
}

@test "test_https_endpoint handles missing curl" {
    set_mock_curl_available "false"
    run test_https_endpoint "example.com"
    set_mock_curl_available "true"
    [ "$status" -eq 0 ]
    assert_output --partial "curl not available"
}

@test "main skips when CUSTOM_DOMAIN is empty" {
    export CUSTOM_DOMAIN=""
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Custom domain not configured"
}

@test "main skips when CUSTOM_DOMAIN is false" {
    export CUSTOM_DOMAIN="false"
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Custom domain not configured"
}

@test "main validates domain format" {
    export CUSTOM_DOMAIN="invalid..domain"
    export ENV_NAME="test-env"
    run main
    [ "$status" -ne 0 ]
    assert_output --partial "Invalid domain format"
}

@test "main configures domain with Route53 when AUTO_CONFIGURE_DNS is true" {
    export CUSTOM_DOMAIN="example.com"
    export AUTO_CONFIGURE_DNS="true"
    export ENV_NAME="test-env"
    run main
    [ "$status" -eq 0 ]
}

