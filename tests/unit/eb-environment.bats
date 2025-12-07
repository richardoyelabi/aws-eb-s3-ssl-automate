#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/create-eb-environment.sh"
}

teardown() {
    teardown_test_env
}

@test "create_application creates new application" {
    run create_application "new-app"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating Elastic Beanstalk application: new-app"
}

@test "create_application skips existing application" {
    run create_application "existing-app"
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

@test "get_solution_stack_name finds matching stack" {
    run get_solution_stack_name "Python"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    assert_output --partial "Python"
}

@test "get_solution_stack_name fails for non-existent stack" {
    run get_solution_stack_name "NonExistentPlatform"
    [ "$status" -ne 0 ]
    assert_output --partial "Could not find solution stack"
}

@test "create_environment_options creates valid JSON" {
    create_environment_options "" "test-profile"
    [ -f /tmp/eb-options.json ]
    run cat /tmp/eb-options.json
    assert_output --partial "IamInstanceProfile"
    assert_output --partial "InstanceType"
    assert_output --partial "STATIC_ASSETS_BUCKET"
}

@test "compare_configuration detects different values" {
    # Multi-line JSON like real AWS CLI output
    local current_config='[
        {
          "Namespace": "aws:autoscaling:launchconfiguration",
          "OptionName": "InstanceType",
          "Value": "t2.micro"
        }
    ]'
    run compare_configuration "$current_config" "aws:autoscaling:launchconfiguration" "InstanceType" "t3.micro"
    [ "$status" -eq 0 ]
    [ "$output" = "different" ]
}

@test "compare_configuration detects same values" {
    local current_config='[
        {
          "Namespace": "aws:autoscaling:launchconfiguration",
          "OptionName": "InstanceType",
          "Value": "t3.micro"
        }
    ]'
    run compare_configuration "$current_config" "aws:autoscaling:launchconfiguration" "InstanceType" "t3.micro"
    [ "$status" -eq 0 ]
    [ "$output" = "same" ]
}

@test "update_environment_configuration handles changes by skipping in test mode" {
    # Set different values than mock returns to trigger change detection
    export INSTANCE_TYPE="t2.large"
    run update_environment_configuration "test-app" "test-env" "" "test-profile"
    export INSTANCE_TYPE="t3.micro"
    [ "$status" -eq 0 ]
    assert_output --partial "Skipping environment update"
}

@test "create_environment creates new environment" {
    export EB_PLATFORM="Python 3.11"
    run create_environment "test-app" "new-env" "Python" "" "test-profile"
    [ "$status" -eq 0 ]
    assert_output --partial "Creating Elastic Beanstalk environment"
}

@test "create_environment skips existing environment" {
    run create_environment "test-app" "existing-env" "Python" "" "test-profile"
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

@test "get_environment_url retrieves URL" {
    run get_environment_url "test-app" "test-env"
    [ "$status" -eq 0 ]
    assert_output --partial "elasticbeanstalk.com"
}

@test "main creates application and environment" {
    export EB_PLATFORM="Python 3.11"
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "Application:"
    assert_output --partial "Environment:"
    assert_output --partial "URL:"
}

@test "idempotency: running main twice succeeds" {
    export EB_PLATFORM="Python 3.11"
    run main
    [ "$status" -eq 0 ]
    
    run main
    [ "$status" -eq 0 ]
    assert_output --partial "already exists"
}

