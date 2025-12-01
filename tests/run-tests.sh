#!/bin/bash

# Test runner for bats-core tests
# Usage: ./tests/run-tests.sh [unit|integration|e2e|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Simple logging functions for test runner
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

run_unit_tests() {
    log_info "Running unit tests..."
    ./tests/bats/bin/bats tests/unit/
}

run_integration_tests() {
    log_info "Running integration tests..."
    ./tests/bats/bin/bats tests/integration/
}

run_e2e_tests() {
    log_warn "Running end-to-end tests (requires AWS credentials)..."
    ./tests/bats/bin/bats tests/e2e/
}

# Parse arguments
case "${1:-all}" in
    unit) run_unit_tests ;;
    integration) run_integration_tests ;;
    e2e) run_e2e_tests ;;
    all)
        run_unit_tests
        run_integration_tests
        # Skip e2e by default (requires AWS creds)
        ;;
    *)
        echo "Usage: $0 [unit|integration|e2e|all]"
        exit 1
        ;;
esac
