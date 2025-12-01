#!/usr/bin/env bash

# Shared test utilities for bats-core tests

load '../bats-support/load'
load '../bats-assert/load'

# Project-specific test setup
setup_test_env() {
    export TEST_MODE=true
    export SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_DIRNAME}")/.." && pwd)"

    # Load project configuration if needed
    if [ -f "$SCRIPT_DIR/config.env" ]; then
        source "$SCRIPT_DIR/config.env"
    fi
}

teardown_test_env() {
    unset TEST_MODE
    # Cleanup any test artifacts
}
