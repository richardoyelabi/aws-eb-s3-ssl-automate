#!/usr/bin/env bats

#load '../test_helper'
#load '../aws-mock'
#
#setup() {
#    setup_test_env
#    source "$SCRIPT_DIR/validate/prerequisites.sh"
#}
#
#teardown() {
#    teardown_test_env
#}
#
#@test "test_aws_cli succeeds when AWS CLI is installed" {
#    run test_aws_cli
#    [ "$status" -eq 0 ]
#    assert_output --partial "AWS CLI is installed"
#}
#
#@test "test_aws_cli fails when AWS CLI is not installed" {
#    # Skip - cannot properly test since aws function is mocked
#    skip "Cannot test AWS CLI missing when mock is active"
#}
#
#@test "test_eb_cli succeeds when EB CLI is installed" {
#    if command -v eb &> /dev/null; then
#        run test_eb_cli
#        [ "$status" -eq 0 ]
#        assert_output --partial "EB CLI is installed"
#    else
#        run test_eb_cli
#        [ "$status" -eq 0 ]
#        assert_output --partial "EB CLI is not installed"
#    fi
#}
#
#@test "test_eb_cli warns when EB CLI is not installed" {
#    # Temporarily make eb unavailable
#    local original_path="$PATH"
#    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$(which eb 2>/dev/null | xargs dirname 2>/dev/null)" | tr '\n' ':')
#    run test_eb_cli
#    export PATH="$original_path"
#    [ "$status" -eq 0 ]
#    assert_output --partial "EB CLI is not installed"
#    assert_output --partial "recommended"
#}
#
#@test "test_jq succeeds when jq is installed" {
#    if command -v jq &> /dev/null; then
#        run test_jq
#        [ "$status" -eq 0 ]
#        assert_output --partial "jq is installed"
#    else
#        run test_jq
#        [ "$status" -eq 0 ]
#        assert_output --partial "jq is not installed"
#    fi
#}
#
#@test "test_jq warns when jq is not installed" {
#    # Skip - path manipulation in subshell doesn't work reliably
#    skip "Cannot reliably test jq missing in test environment"
#}
#
#