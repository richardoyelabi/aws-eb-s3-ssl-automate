#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/configure-ssl.sh"
}

teardown() {
    teardown_test_env
}

@test "configure_https_listener configures HTTPS listener" {
    run configure_https_listener "test-app" "test-env" "arn:aws:acm:us-east-1:123456789012:certificate/test"
    [ "$status" -eq 0 ]
    assert_output --partial "Configuring HTTPS listener"
}

@test "configure_https_listener updates when config differs" {
    # Mock returns config that triggers update
    run configure_https_listener "test-app" "test-env" ""
    [ "$status" -eq 0 ]
    assert_output --partial "HTTPS listener"
}

@test "configure_https_listener adds certificate to existing list" {
    run configure_https_listener "test-app" "test-env" "arn:aws:acm:us-east-1:123456789012:certificate/new-cert"
    [ "$status" -eq 0 ]
}

@test "configure_http_redirect configures redirect when enabled" {
    export ENABLE_HTTPS_REDIRECT="true"
    run configure_http_redirect "test-app" "test-env"
    [ "$status" -eq 0 ]
    assert_output --partial "Configuring HTTP to HTTPS redirect"
}

@test "configure_http_redirect skips when disabled" {
    export ENABLE_HTTPS_REDIRECT="false"
    run configure_http_redirect "test-app" "test-env"
    [ "$status" -eq 0 ]
    assert_output --partial "HTTP to HTTPS redirect is disabled"
}

@test "configure_http_redirect handles missing load balancer" {
    export ENABLE_HTTPS_REDIRECT="true"
    run configure_http_redirect "test-app" "nonexistent-env"
    [ "$status" -eq 0 ]
    assert_output --partial "Could not find load balancer"
}

@test "verify_ssl_configuration tests HTTPS endpoint" {
    run verify_ssl_configuration "test-env.us-east-1.elasticbeanstalk.com"
    [ "$status" -eq 0 ]
}

@test "verify_ssl_configuration handles missing curl" {
    set_mock_curl_available "false"
    run verify_ssl_configuration "test-env.us-east-1.elasticbeanstalk.com"
    set_mock_curl_available "true"
    [ "$status" -eq 0 ]
    assert_output --partial "curl not available"
}

@test "main configures SSL with certificate" {
    export CUSTOM_DOMAIN="example.com"
    echo "arn:aws:acm:us-east-1:123456789012:certificate/test" > /tmp/acm-cert-arn.txt
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "SSL configuration completed"
}

@test "main configures SSL without certificate for default domain" {
    export CUSTOM_DOMAIN=""
    rm -f /tmp/acm-cert-arn.txt
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "AWS automatic certificates"
}

@test "main fails when custom domain configured but no certificate" {
    export CUSTOM_DOMAIN="example.com"
    rm -f /tmp/acm-cert-arn.txt
    export ACM_CERTIFICATE_ARN=""
    run main
    [ "$status" -ne 0 ]
    assert_output --partial "no certificate ARN found"
}

@test "configure_https_listener requires environment to exist" {
    # This test verifies that configure_https_listener properly fails when environment doesn't exist
    # This was the original bug - it was being called before environment creation

    # Use the mocked environment that returns error for nonexistent-env
    run configure_https_listener "test-app" "nonexistent-env" ""

    # Should fail because environment doesn't exist
    [ "$status" -ne 0 ]

    # Verify the expected error message appears in stderr
    assert_output --partial "No Environment found for EnvironmentName = nonexistent-env" 2>&1
}

