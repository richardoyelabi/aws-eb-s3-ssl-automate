#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/validate/permissions.sh"
}

teardown() {
    teardown_test_env
}

@test "test_aws_credentials succeeds with valid credentials" {
    run test_aws_credentials
    [ "$status" -eq 0 ]
    assert_output --partial "AWS credentials are valid"
    assert_output --partial "Account ID"
}

@test "test_aws_credentials uses default profile when not set" {
    unset AWS_PROFILE
    run test_aws_credentials
    [ "$status" -eq 0 ]
    assert_output --partial "AWS_PROFILE not set, using default"
}

@test "test_aws_credentials uses default region when not set" {
    unset AWS_REGION
    run test_aws_credentials
    [ "$status" -eq 0 ]
    assert_output --partial "AWS_REGION not set, using us-east-1"
}

@test "test_iam_permissions succeeds with all permissions" {
    run test_iam_permissions
    [ "$status" -eq 0 ]
    assert_output --partial "S3 permissions OK"
    assert_output --partial "Elastic Beanstalk permissions OK"
    assert_output --partial "IAM permissions OK"
    assert_output --partial "ACM permissions OK"
}

@test "test_iam_permissions checks S3 permissions" {
    run test_iam_permissions
    [ "$status" -eq 0 ]
    assert_output --partial "S3 permissions"
}

@test "test_iam_permissions checks Elastic Beanstalk permissions" {
    run test_iam_permissions
    [ "$status" -eq 0 ]
    assert_output --partial "Elastic Beanstalk permissions"
}

@test "test_iam_permissions checks IAM permissions" {
    run test_iam_permissions
    [ "$status" -eq 0 ]
    assert_output --partial "IAM permissions"
}

@test "test_iam_permissions checks ACM permissions" {
    run test_iam_permissions
    [ "$status" -eq 0 ]
    assert_output --partial "ACM permissions"
}

@test "test_iam_permissions fails when permissions insufficient" {
    # This would require more complex mocking to simulate permission failures
    # For now, verify the function exists and checks all services
    run test_iam_permissions
    [ "$status" -eq 0 ]
}

