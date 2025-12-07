#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

# Mock state variables for controlling test behavior
export MOCK_COMMAND_AWS=""
export MOCK_COMMAND_EB=""
export MOCK_COMMAND_JQ=""
export MOCK_AWS_VERSION=""
export MOCK_EB_VERSION=""
export MOCK_JQ_VERSION=""

# Override command builtin to control tool availability
command() {
    local cmd="$2"
    
    # Handle -v flag
    if [[ "$1" == "-v" ]]; then
        case "$cmd" in
            aws)
                [[ "$MOCK_COMMAND_AWS" == "available" ]] && return 0 || return 1
                ;;
            eb)
                [[ "$MOCK_COMMAND_EB" == "available" ]] && return 0 || return 1
                ;;
            jq)
                [[ "$MOCK_COMMAND_JQ" == "available" ]] && return 0 || return 1
                ;;
            *)
                # For other commands, use real command
                builtin command "$@"
                ;;
        esac
    else
        # For non -v usage, use real command
        builtin command "$@"
    fi
}

# Mock eb CLI
eb() {
    if [[ "$1" == "--version" ]]; then
        if [[ -n "$MOCK_EB_VERSION" ]]; then
            echo "$MOCK_EB_VERSION"
            return 0
        else
            return 1
        fi
    fi
}

# Mock jq CLI
jq() {
    if [[ "$1" == "--version" ]]; then
        if [[ -n "$MOCK_JQ_VERSION" ]]; then
            echo "$MOCK_JQ_VERSION"
            return 0
        else
            return 1
        fi
    fi
}

setup() {
    setup_test_env
    
    # Reset mock state
    export MOCK_COMMAND_AWS=""
    export MOCK_COMMAND_EB=""
    export MOCK_COMMAND_JQ=""
    export MOCK_AWS_VERSION=""
    export MOCK_EB_VERSION=""
    export MOCK_JQ_VERSION=""
    
    # Source only the function definitions from prerequisites.sh
    # We use sed to exclude the auto-execution lines at the end
    local temp_script="$TEST_TMPDIR/prerequisites-sourced.sh"
    sed '/^# Run all prerequisite checks/,$d' "$SCRIPT_DIR/validate/prerequisites.sh" > "$temp_script"
    source "$temp_script"
    rm -f "$temp_script"
}

teardown() {
    teardown_test_env
    unset MOCK_COMMAND_AWS
    unset MOCK_COMMAND_EB
    unset MOCK_COMMAND_JQ
    unset MOCK_AWS_VERSION
    unset MOCK_EB_VERSION
    unset MOCK_JQ_VERSION
}

# ==============================================================================
# test_aws_cli Tests
# ==============================================================================

@test "test_aws_cli succeeds when AWS CLI is installed and returns version" {
    export MOCK_COMMAND_AWS="available"
    export MOCK_AWS_VERSION="aws-cli/2.13.0 Python/3.11.0 Linux/5.15.0 exe/x86_64"
    
    run test_aws_cli
    [ "$status" -eq 0 ]
    assert_output --partial "Testing AWS CLI installation"
    assert_output --partial "AWS CLI is installed"
    assert_output --partial "aws-cli/2.13.0"
}

@test "test_aws_cli fails when AWS CLI is not installed" {
    export MOCK_COMMAND_AWS="not_available"
    
    run test_aws_cli
    [ "$status" -eq 1 ]
    assert_output --partial "Testing AWS CLI installation"
    assert_output --partial "AWS CLI is not installed"
}

@test "test_aws_cli handles AWS CLI version command failure gracefully" {
    export MOCK_COMMAND_AWS="available"
    export MOCK_AWS_VERSION=""
    
    run test_aws_cli
    [ "$status" -eq 0 ]
    assert_output --partial "Testing AWS CLI installation"
    assert_output --partial "AWS CLI is installed"
}

# ==============================================================================
# test_eb_cli Tests
# ==============================================================================

@test "test_eb_cli succeeds when EB CLI is installed and returns version" {
    export MOCK_COMMAND_EB="available"
    export MOCK_EB_VERSION="EB CLI 3.20.3 (Python 3.9.5)"
    
    run test_eb_cli
    [ "$status" -eq 0 ]
    assert_output --partial "Testing EB CLI installation"
    assert_output --partial "EB CLI is installed"
    assert_output --partial "EB CLI 3.20.3"
}

@test "test_eb_cli succeeds with warning when EB CLI is not installed" {
    export MOCK_COMMAND_EB="not_available"
    
    run test_eb_cli
    [ "$status" -eq 0 ]
    assert_output --partial "Testing EB CLI installation"
    assert_output --partial "EB CLI is not installed"
    assert_output --partial "recommended"
    assert_output --partial "pip install awsebcli"
}

@test "test_eb_cli handles EB CLI version command failure gracefully" {
    export MOCK_COMMAND_EB="available"
    export MOCK_EB_VERSION=""
    
    run test_eb_cli
    [ "$status" -eq 0 ]
    assert_output --partial "Testing EB CLI installation"
    assert_output --partial "EB CLI is installed"
}

# ==============================================================================
# test_jq Tests
# ==============================================================================

@test "test_jq succeeds when jq is installed and returns version" {
    export MOCK_COMMAND_JQ="available"
    export MOCK_JQ_VERSION="jq-1.6"
    
    run test_jq
    [ "$status" -eq 0 ]
    assert_output --partial "Testing jq installation"
    assert_output --partial "jq is installed"
    assert_output --partial "jq-1.6"
}

@test "test_jq succeeds with warning when jq is not installed" {
    export MOCK_COMMAND_JQ="not_available"
    
    run test_jq
    [ "$status" -eq 0 ]
    assert_output --partial "Testing jq installation"
    assert_output --partial "jq is not installed"
    assert_output --partial "recommended"
}

@test "test_jq shows installation instructions when not installed" {
    export MOCK_COMMAND_JQ="not_available"
    
    run test_jq
    [ "$status" -eq 0 ]
    assert_output --partial "apt-get install jq"
    assert_output --partial "brew install jq"
}

@test "test_jq handles jq version command failure gracefully" {
    export MOCK_COMMAND_JQ="available"
    export MOCK_JQ_VERSION=""
    
    run test_jq
    [ "$status" -eq 0 ]
    assert_output --partial "Testing jq installation"
    assert_output --partial "jq is installed"
}

# ==============================================================================
# Edge Cases and Integration Tests
# ==============================================================================

@test "test_aws_cli produces correct log format with color codes" {
    export MOCK_COMMAND_AWS="available"
    export MOCK_AWS_VERSION="aws-cli/2.13.0"
    
    run test_aws_cli
    [ "$status" -eq 0 ]
    # Check for INFO log marker
    assert_output --partial "[INFO]"
    # Check for success marker
    assert_output --regexp "\[.*✓.*\]"
}

@test "test_aws_cli produces failure log format when not installed" {
    export MOCK_COMMAND_AWS="not_available"
    
    run test_aws_cli
    [ "$status" -eq 1 ]
    # Check for failure marker
    assert_output --regexp "\[.*✗.*\]"
}

@test "test_eb_cli produces warning log format when not installed" {
    export MOCK_COMMAND_EB="not_available"
    
    run test_eb_cli
    [ "$status" -eq 0 ]
    # Check for WARN log marker
    assert_output --partial "[WARN]"
}

@test "test_jq produces warning log format when not installed" {
    export MOCK_COMMAND_JQ="not_available"
    
    run test_jq
    [ "$status" -eq 0 ]
    # Check for WARN log marker
    assert_output --partial "[WARN]"
}

@test "multiple prerequisite checks can run independently - all available" {
    export MOCK_COMMAND_AWS="available"
    export MOCK_COMMAND_EB="available"
    export MOCK_COMMAND_JQ="available"
    export MOCK_AWS_VERSION="aws-cli/2.13.0"
    export MOCK_EB_VERSION="EB CLI 3.20.3"
    export MOCK_JQ_VERSION="jq-1.6"
    
    run test_aws_cli
    [ "$status" -eq 0 ]
    
    run test_eb_cli
    [ "$status" -eq 0 ]
    
    run test_jq
    [ "$status" -eq 0 ]
}

@test "multiple prerequisite checks can run independently - mixed availability" {
    export MOCK_COMMAND_AWS="available"
    export MOCK_COMMAND_EB="not_available"
    export MOCK_COMMAND_JQ="available"
    export MOCK_AWS_VERSION="aws-cli/2.13.0"
    export MOCK_JQ_VERSION="jq-1.6"
    
    run test_aws_cli
    [ "$status" -eq 0 ]
    
    run test_eb_cli
    [ "$status" -eq 0 ]
    assert_output --partial "not installed"
    
    run test_jq
    [ "$status" -eq 0 ]
}

@test "test_aws_cli only fails for missing AWS CLI, not for version issues" {
    export MOCK_COMMAND_AWS="available"
    export MOCK_AWS_VERSION=""
    
    run test_aws_cli
    [ "$status" -eq 0 ]
    assert_output --partial "AWS CLI is installed"
}
