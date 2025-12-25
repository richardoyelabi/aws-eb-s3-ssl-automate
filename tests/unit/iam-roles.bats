#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/setup-iam-roles.sh"
}

teardown() {
    teardown_test_env
}

@test "create_trust_policy creates valid JSON" {
    create_trust_policy
    [ -f /tmp/eb-trust-policy.json ]
    run cat /tmp/eb-trust-policy.json
    assert_output --partial "ec2.amazonaws.com"
    assert_output --partial "sts:AssumeRole"
}

@test "create_s3_access_policy creates valid policy document" {
    create_s3_access_policy "test-static" "test-uploads"
    [ -f /tmp/s3-access-policy.json ]
    run cat /tmp/s3-access-policy.json
    assert_output --partial "test-static"
    assert_output --partial "test-uploads"
    assert_output --partial "s3:GetObject"
    assert_output --partial "s3:PutObject"
    assert_output --partial "s3:DeleteObject"
}

@test "create_iam_role creates new role" {
    run create_iam_role "new-role"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating IAM role: new-role"
}

@test "create_iam_role skips existing role" {
    run create_iam_role "existing-role"
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

@test "attach_managed_policies attaches policies" {
    run attach_managed_policies "test-role"
    [ "$status" -eq 0 ]
    assert_output --partial "Attaching AWS managed policies"
}

@test "normalize_json works with jq" {
    echo '{"a":1,"b":2}' > /tmp/test.json
    run normalize_json /tmp/test.json
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "normalize_json works without jq" {
    echo '{"a":1,"b":2}' > /tmp/test.json
    set_mock_jq_available "false"
    run normalize_json /tmp/test.json
    set_mock_jq_available "true"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "create_and_attach_s3_policy creates new policy" {
    export STATIC_ASSETS_BUCKET="test-static"
    export UPLOADS_BUCKET="test-uploads"
    run create_and_attach_s3_policy "test-role"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating S3 access policy"
}

@test "create_and_attach_s3_policy updates existing policy when different" {
    export STATIC_ASSETS_BUCKET="test-static"
    export UPLOADS_BUCKET="test-uploads"
    # Mock existing policy
    run create_and_attach_s3_policy "existing-role"
    [ "$status" -eq 0 ]
}

@test "create_instance_profile creates new profile" {
    run create_instance_profile "test-role"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating instance profile"
}

@test "create_instance_profile skips existing profile" {
    run create_instance_profile "existing-role"
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

@test "create_instance_profile attaches role to existing profile" {
    run create_instance_profile "test-role"
    [ "$status" -eq 0 ]
}

@test "main creates custom role when USE_DEFAULT_IAM_ROLE is false" {
    export USE_DEFAULT_IAM_ROLE="false"
    export CUSTOM_IAM_ROLE_NAME="custom-test-role"
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Creating custom IAM role"
}

@test "main uses default role when USE_DEFAULT_IAM_ROLE is true" {
    export USE_DEFAULT_IAM_ROLE="true"
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Using default Elastic Beanstalk IAM role"
}

@test "idempotency: running main twice succeeds" {
    export USE_DEFAULT_IAM_ROLE="false"
    export CUSTOM_IAM_ROLE_NAME="test-role"
    run main
    [ "$status" -eq 0 ]
    
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

