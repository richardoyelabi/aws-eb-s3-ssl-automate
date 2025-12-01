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
