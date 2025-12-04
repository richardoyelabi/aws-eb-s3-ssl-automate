#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/setup-s3-buckets.sh"
}

teardown() {
    teardown_test_env
}

@test "create_bucket_if_not_exists creates new bucket" {
    run create_bucket_if_not_exists "new-bucket" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating S3 bucket: new-bucket"
}

@test "create_bucket_if_not_exists skips existing bucket" {
    run create_bucket_if_not_exists "existing-bucket" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

@test "create_bucket_if_not_exists handles us-east-1 region" {
    run create_bucket_if_not_exists "test-bucket" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "create_bucket_if_not_exists handles other regions" {
    run create_bucket_if_not_exists "test-bucket" "us-west-2"
    [ "$status" -eq 0 ]
}

@test "configure_static_assets_bucket enables versioning when configured" {
    export ENABLE_S3_VERSIONING="true"
    run configure_static_assets_bucket "test-static-assets" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "configure_static_assets_bucket skips versioning when disabled" {
    export ENABLE_S3_VERSIONING="false"
    run configure_static_assets_bucket "test-static-assets" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "configure_static_assets_bucket configures CORS" {
    run configure_static_assets_bucket "test-static-assets" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "Configuring CORS"
}

@test "configure_static_assets_bucket skips CORS when already configured" {
    run configure_static_assets_bucket "cors-configured-bucket" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "CORS already configured"
}

@test "configure_static_assets_bucket configures public access block" {
    run configure_static_assets_bucket "test-static-assets" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "configure_static_assets_bucket skips public access block when already configured" {
    run configure_static_assets_bucket "pab-configured-bucket" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "already configured"
}

@test "configure_uploads_bucket enables versioning when configured" {
    export ENABLE_S3_VERSIONING="true"
    run configure_uploads_bucket "test-uploads" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "configure_uploads_bucket configures CORS for uploads" {
    run configure_uploads_bucket "test-uploads" "us-east-1"
    [ "$status" -eq 0 ]
    assert_output --partial "Configuring CORS"
}

@test "configure_uploads_bucket configures public access block for uploads" {
    run configure_uploads_bucket "test-uploads" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "main creates and configures both buckets" {
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Static Assets:"
    assert_output --partial "Uploads:"
}

@test "idempotency: running main twice succeeds" {
    run main
    [ "$status" -eq 0 ]
    
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

