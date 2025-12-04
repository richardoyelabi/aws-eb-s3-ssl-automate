#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/validate/environment.sh"
}

teardown() {
    teardown_test_env
}

@test "check_existing_resources detects existing application" {
    export APP_NAME="existing-app"
    run check_existing_resources
    [ "$status" -eq 0 ]
    assert_output --partial "Application already exists"
}

@test "check_existing_resources detects new application" {
    export APP_NAME="new-app"
    run check_existing_resources
    [ "$status" -eq 0 ]
    assert_output --partial "does not exist"
}

@test "check_existing_resources detects existing environment" {
    export APP_NAME="test-app"
    export ENV_NAME="existing-env"
    run check_existing_resources
    [ "$status" -eq 0 ]
    assert_output --partial "Environment already exists"
}

@test "check_existing_resources detects new environment" {
    export APP_NAME="test-app"
    export ENV_NAME="new-env"
    run check_existing_resources
    [ "$status" -eq 0 ]
    assert_output --partial "does not exist"
}

@test "check_existing_resources detects existing buckets" {
    export STATIC_ASSETS_BUCKET="test-static-assets"
    export UPLOADS_BUCKET="test-uploads"
    run check_existing_resources
    [ "$status" -eq 0 ]
    assert_output --partial "Bucket already exists"
}

@test "check_existing_resources detects new buckets" {
    export STATIC_ASSETS_BUCKET="new-bucket"
    export UPLOADS_BUCKET="another-new-bucket"
    run check_existing_resources
    [ "$status" -eq 0 ]
    assert_output --partial "does not exist"
}

@test "check_existing_resources checks all resources" {
    export APP_NAME="test-app"
    export ENV_NAME="test-env"
    export STATIC_ASSETS_BUCKET="test-static-assets"
    export UPLOADS_BUCKET="test-uploads"
    run check_existing_resources
    [ "$status" -eq 0 ]
    # Should check application, environment, and both buckets
    assert_output --partial "Checking for existing resources"
}

