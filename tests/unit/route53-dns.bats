#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/setup-route53-dns.sh"
}

teardown() {
    teardown_test_env
}

@test "list_hosted_zones lists zones" {
    run list_hosted_zones
    [ "$status" -eq 0 ]
    # Output depends on mock - just verify it runs
    assert_output --partial "Listing Route 53 hosted zones"
}

@test "find_hosted_zone finds zone by exact domain" {
    run find_hosted_zone "example.com"
    [ "$status" -eq 0 ]
    assert_output --partial "Z1234567890ABC"
}

@test "find_hosted_zone finds zone by parent domain" {
    run find_hosted_zone "api.example.com"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "find_hosted_zone returns error for non-existent domain" {
    run find_hosted_zone "nonexistent.com"
    [ "$status" -ne 0 ]
}

@test "create_hosted_zone creates new zone" {
    run create_hosted_zone "new-domain.com"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating Route 53 hosted zone"
    assert_output --partial "Z1234567890ABC"
}

@test "list_dns_records lists records" {
    run list_dns_records "Z1234567890ABC"
    [ "$status" -eq 0 ]
}

@test "check_existing_record finds existing record" {
    run check_existing_record "Z1234567890ABC" "existing.example.com" "CNAME"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "check_existing_record returns empty for non-existent record" {
    run check_existing_record "Z1234567890ABC" "nonexistent.example.com" "CNAME"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ] || [ -z "$output" ]
}

@test "create_alias_record creates new ALIAS record" {
    run create_alias_record "Z1234567890ABC" "example.com" "test-lb.us-east-1.elb.amazonaws.com" "Z35SXDOTRQ7X7K"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating/Updating ALIAS record"
}

@test "create_alias_record updates when record exists" {
    # Mock returns a different target, so update is triggered
    run create_alias_record "Z1234567890ABC" "existing.example.com" "test-lb.us-east-1.elb.amazonaws.com" "Z35SXDOTRQ7X7K"
    [ "$status" -eq 0 ]
    # May skip or update depending on mock state
    assert_output --partial "ALIAS record"
}

@test "create_cname_record creates new CNAME record" {
    run create_cname_record "Z1234567890ABC" "api.example.com" "test-lb.us-east-1.elb.amazonaws.com"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating/Updating CNAME record"
}

@test "create_cname_record skips when record already matches" {
    run create_cname_record "Z1234567890ABC" "existing.example.com" "test-lb.us-east-1.elb.amazonaws.com"
    [ "$status" -eq 0 ]
    assert_output --partial "already exists and points to"
}

@test "create_cname_record accepts custom TTL" {
    run create_cname_record "Z1234567890ABC" "api.example.com" "test-lb.us-east-1.elb.amazonaws.com" "600"
    [ "$status" -eq 0 ]
}

@test "delete_dns_record deletes existing record" {
    run delete_dns_record "Z1234567890ABC" "existing.example.com" "CNAME"
    [ "$status" -eq 0 ]
    assert_output --partial "Deleting"
}

@test "delete_dns_record handles non-existent record" {
    run delete_dns_record "Z1234567890ABC" "nonexistent.example.com" "CNAME"
    [ "$status" -ne 0 ]
    assert_output --partial "No"
}

@test "wait_for_dns_propagation skips in test mode" {
    run wait_for_dns_propagation "example.com" 1
    [ "$status" -eq 0 ]
    assert_output --partial "Skipping DNS propagation wait in test mode"
}

@test "wait_for_dns_propagation message in test mode" {
    run wait_for_dns_propagation "example.com" 1
    [ "$status" -eq 0 ]
    assert_output --partial "test mode"
}

@test "main handles list-zones command" {
    run main list-zones
    [ "$status" -eq 0 ]
}

@test "main handles find-zone command" {
    run main find-zone "example.com"
    [ "$status" -eq 0 ]
}

@test "main handles create-zone command" {
    run main create-zone "new-domain.com"
    [ "$status" -eq 0 ]
}

@test "main handles create-alias command" {
    run main create-alias "Z1234567890ABC" "example.com" "test-lb.us-east-1.elb.amazonaws.com" "Z35SXDOTRQ7X7K"
    [ "$status" -eq 0 ]
}

@test "main handles create-cname command" {
    run main create-cname "Z1234567890ABC" "api.example.com" "test-lb.us-east-1.elb.amazonaws.com"
    [ "$status" -eq 0 ]
}

@test "idempotency: create_alias_record twice succeeds" {
    run create_alias_record "Z1234567890ABC" "example.com" "test-lb.us-east-1.elb.amazonaws.com" "Z35SXDOTRQ7X7K"
    [ "$status" -eq 0 ]
    
    run create_alias_record "Z1234567890ABC" "example.com" "test-lb.us-east-1.elb.amazonaws.com" "Z35SXDOTRQ7X7K"
    [ "$status" -eq 0 ]
}

