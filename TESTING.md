# Testing Framework Guide

This document explains the testing framework for the AWS EB S3 SSL Automation project.

## Overview

The testing framework uses [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System) to provide structured testing capabilities. Tests are organized by type and can run with or without AWS dependencies.

## Test Organization

```
tests/
├── bats/               # bats-core framework
├── bats-support/       # Additional utilities
├── bats-assert/        # Assertion library
├── test_helper.bash    # Shared test utilities
├── aws-mock.bash       # AWS API mocking
├── run-tests.sh        # Test runner
├── unit/               # Unit tests (no AWS required)
├── integration/        # Integration tests
└── e2e/                # End-to-end tests (AWS required)
```

## Quick Start

```bash
# Run all unit tests
./tests/run-tests.sh unit

# Run all integration tests
./tests/run-tests.sh integration

# Run all tests
./tests/run-tests.sh all

# Run end-to-end tests (requires AWS)
./tests/run-tests.sh e2e
```

## Writing Tests

### Test File Structure

All test files use the `.bats` extension and follow this structure:

```bash
#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'  # Only for tests that need AWS mocking

setup() {
    setup_test_env
    # Test-specific setup
}

teardown() {
    teardown_test_env
    # Test-specific cleanup
}

@test "test description" {
    # Arrange
    # Act
    # Assert
}
```

### Test Helpers

**test_helper.bash** provides:
- `setup_test_env()` - Initialize test environment
- `teardown_test_env()` - Clean up test environment

**aws-mock.bash** provides:
- Mock AWS CLI commands when `TEST_MODE=true`
- Prevents actual AWS API calls during testing

### Assertions

Use bats-assert for test assertions:

```bash
@test "example assertions" {
    run some_command

    # Status assertions
    [ "$status" -eq 0 ]        # Command succeeded
    [ "$status" -eq 1 ]        # Command failed

    # Output assertions
    [ "$output" = "expected" ] # Exact output match
    [[ "$output" =~ "pattern" ]] # Regex pattern match

    # Using bats-assert
    assert_success             # Command succeeded
    assert_failure             # Command failed
    assert_output "expected"   # Exact output match
    assert_line "expected line" # Line contains expected text
}
```

## Test Types

### Unit Tests (`tests/unit/`)

**Purpose**: Test individual functions in isolation
**AWS Dependency**: None (uses mocking)
**Example**: Domain validation logic

```bash
#!/usr/bin/env bats

load '../test_helper'
load '../aws-mock'

setup() {
    setup_test_env
    source "$SCRIPT_DIR/scripts/configure-custom-domain.sh"
}

@test "validate_domain_format accepts valid domains" {
    run validate_domain_format "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain_format rejects invalid domains" {
    run validate_domain_format ""
    [ "$status" -eq 1 ]
}
```

### Integration Tests (`tests/integration/`)

**Purpose**: Test component interactions
**AWS Dependency**: Minimal (may use mocking)
**Example**: Configuration loading between components

```bash
#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

@test "config.env can be sourced" {
    source "$SCRIPT_DIR/config.env"

    [ -n "$AWS_REGION" ]
    [ -n "$APP_NAME" ]
}
```

### End-to-End Tests (`tests/e2e/`)

**Purpose**: Test complete workflows
**AWS Dependency**: Full (requires real AWS credentials)
**Example**: Full setup workflow

```bash
#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env

    if ! aws sts get-caller-identity &>/dev/null; then
        skip "AWS credentials required for e2e tests"
    fi

    # Create test config with unique names
    TEST_CONFIG="/tmp/e2e-config.env"
    # ... config setup
}

teardown() {
    # Cleanup test resources
    rm -f "$TEST_CONFIG"
}

@test "full setup workflow completes" {
    CONFIG_FILE="$TEST_CONFIG" run timeout 900 "$SCRIPT_DIR/setup-eb-environment.sh"
    [ "$status" -eq 0 ] || [ "$status" -eq 124 ]  # Success or timeout
}
```

## Running Tests

### Individual Test Files

```bash
# Run specific test file
./tests/bats/bin/bats tests/unit/domain-validation.bats

# Run with verbose output
./tests/bats/bin/bats -t tests/unit/domain-validation.bats
```

### Test Runner Options

The `run-tests.sh` script supports:

```bash
./tests/run-tests.sh unit        # Unit tests only
./tests/run-tests.sh integration # Integration tests only
./tests/run-tests.sh e2e         # End-to-end tests only
./tests/run-tests.sh all         # All tests (except e2e)
```

## AWS Mocking

### How It Works

When `TEST_MODE=true`, AWS commands are intercepted and mocked:

```bash
# In test
setup_test_env  # Sets TEST_MODE=true

# This runs the mock instead of real AWS
aws sts get-caller-identity
```

### Adding New Mocks

Edit `tests/aws-mock.bash`:

```bash
mock_aws() {
    local service="$1"
    local operation="$2"
    shift 2

    case "$service.$operation" in
        sts.get-caller-identity)
            echo '{"Account": "123456789012", "UserId": "test-user"}'
            ;;
        s3api.head-bucket)
            if [[ "$*" == *"--bucket test-bucket-exists"* ]]; then
                return 0
            else
                return 1
            fi
            ;;
        # Add more mocks here
        *)
            echo "Mock not implemented: aws $service $operation" >&2
            return 1
            ;;
    esac
}
```

## Best Practices

### Test Naming
```bash
@test "validate_domain_format rejects invalid domains"
@test "s3_bucket_creation handles existing buckets"
@test "iam_role_setup creates required policies"
```

### Test Isolation
- Each test should be independent
- Use unique resource names in tests
- Clean up test artifacts in `teardown()`

### Test Coverage
- Test both success and failure cases
- Test edge cases and error conditions
- Test configuration variations

### AWS Testing
- Use mocking for unit tests (no AWS required)
- Use real AWS for e2e tests only
- Clean up test resources properly
- Use unique names to avoid conflicts

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run unit tests
  run: ./tests/run-tests.sh unit

- name: Run integration tests
  run: ./tests/run-tests.sh integration

- name: Run e2e tests (main branch only)
  if: github.ref == 'refs/heads/main'
  run: ./tests/run-tests.sh e2e
```

## Troubleshooting

### Test Failures

**Common Issues**:
1. **Missing dependencies**: Ensure bats-core and extensions are installed
2. **Path issues**: Use `$SCRIPT_DIR` for project-relative paths
3. **Mock issues**: Check that TEST_MODE is set correctly

**Debugging**:
```bash
# Run with tracing
./tests/bats/bin/bats -t tests/unit/your-test.bats

# Run single test
./tests/bats/bin/bats -f "test name" tests/unit/your-test.bats
```

### AWS Mock Issues

**Symptoms**: Tests making real AWS calls
**Cause**: TEST_MODE not set or mocking not loaded
**Fix**: Ensure `load '../aws-mock'` and `setup_test_env()` are called

## Contributing Tests

When adding new features:

1. **Add unit tests** for new functions
2. **Add integration tests** for component interactions
3. **Update mocks** if new AWS APIs are used
4. **Run all tests** before submitting PR

### Test Checklist

- [ ] Unit tests pass without AWS credentials
- [ ] Integration tests verify component interactions
- [ ] E2E tests validate full workflows (when applicable)
- [ ] Tests clean up after themselves
- [ ] Test names are descriptive
- [ ] Edge cases and error conditions tested

## Validation vs Testing

Remember the distinction:
- **Validation** (see VALIDATION.md): "Can we deploy?" - environment readiness
- **Testing** (this document): "Does the code work?" - functionality verification

Both are essential but serve different purposes. Run validation before deployment, run tests during development.
