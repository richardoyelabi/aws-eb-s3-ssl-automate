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
    if ! command -v curl &> /dev/null; then
        skip "curl not available"
    fi
    # Mock curl to succeed
    curl() {
        return 0
    }
    run verify_ssl_configuration "test-env.us-east-1.elasticbeanstalk.com"
    [ "$status" -eq 0 ]
}

@test "verify_ssl_configuration handles missing curl" {
    local original_path="$PATH"
    export PATH=""
    run verify_ssl_configuration "test-env.us-east-1.elasticbeanstalk.com"
    export PATH="$original_path"
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

