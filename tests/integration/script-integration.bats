#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "config.env can be sourced" {
    # Test that config.env can be sourced independently
    source "$SCRIPT_DIR/config.env"

    # Check that key variables are available
    [ -n "$AWS_REGION" ]
    [ -n "$APP_NAME" ]
    [ -n "$ENV_NAME" ]
}

@test "setup script execution order is correct" {
    # Test that the main setup script executes steps in the correct order
    # This test verifies the fix for the SSL configuration timing issue

    # Extract function calls from the main execution block
    local function_calls=()

    # Use grep to find the specific function calls we care about
    while IFS= read -r func_name; do
        # Trim leading whitespace
        func_name=$(echo "$func_name" | sed 's/^[[:space:]]*//')
        case "$func_name" in
            setup_s3_buckets|setup_iam_roles|create_eb_environment|setup_rds_database|configure_ssl|configure_custom_domain|generate_instructions)
                function_calls+=("$func_name")
                ;;
        esac
    done < <(sed -n '/Execute setup steps/,/cleanup_temp_files/p' "$SCRIPT_DIR/setup-eb-environment.sh" | grep -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*$')

    # Verify the execution order
    local expected_order=("setup_s3_buckets" "setup_iam_roles" "create_eb_environment" "setup_rds_database" "configure_ssl" "configure_custom_domain" "generate_instructions")

    # Check that we have the expected functions in order
    local expected_index=0
    for func in "${function_calls[@]}"; do
        if [ "$func" = "${expected_order[$expected_index]}" ]; then
            expected_index=$((expected_index + 1))
        fi
    done

    # Should have found all expected functions in order
    [ "$expected_index" -eq "${#expected_order[@]}" ]

    # Verify SSL configuration happens AFTER environment creation
    local ssl_index=-1
    local env_index=-1
    for i in "${!function_calls[@]}"; do
        if [ "${function_calls[$i]}" = "configure_ssl" ]; then
            ssl_index=$i
        elif [ "${function_calls[$i]}" = "create_eb_environment" ]; then
            env_index=$i
        fi
    done

    # SSL configuration must come after environment creation
    [ "$ssl_index" -gt "$env_index" ]
    
    # Verify RDS database setup happens AFTER environment creation
    local db_index=-1
    for i in "${!function_calls[@]}"; do
        if [ "${function_calls[$i]}" = "setup_rds_database" ]; then
            db_index=$i
        fi
    done
    
    # Database setup must come after environment creation
    [ "$db_index" -gt "$env_index" ]
}

@test "database configuration variables are available" {
    # Test that database configuration variables are set
    source "$SCRIPT_DIR/config.env"
    
    [ -n "$DB_ENGINE" ]
    [ -n "$DB_ENGINE_VERSION" ]
    [ -n "$DB_INSTANCE_CLASS" ]
    [ -n "$DB_ALLOCATED_STORAGE" ]
    [ -n "$DB_NAME" ]
    [ -n "$DB_USERNAME" ]
}
