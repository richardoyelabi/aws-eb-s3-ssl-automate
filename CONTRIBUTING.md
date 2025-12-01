# Contributing Guide

Thank you for your interest in contributing to the AWS EB S3 SSL Automation project! This guide explains how to contribute effectively.

## Development Workflow

### 1. Prerequisites

Before contributing, ensure you have:
- ✅ Bash/shell scripting knowledge
- ✅ AWS CLI configured with appropriate permissions
- ✅ Understanding of AWS services (EB, S3, IAM, ACM, Route 53)
- ✅ Git and GitHub workflow experience

### 2. Setup Development Environment

```bash
# Clone the repository
git clone <repository-url>
cd aws-eb-s3-ssl-automate

# Initialize git submodules (required for testing framework)
git submodule update --init --recursive

# Copy configuration template
cp config.env.example config.env
# Edit config.env with your test values

# Run validation to ensure your environment is ready
./validate/run-validation.sh
```

### 3. Development Process

```bash
# 1. Create a feature branch
git checkout -b feature/your-feature-name

# 2. Make your changes
# Edit scripts, add tests, update documentation

# 3. Run tests frequently
./tests/run-tests.sh unit
./tests/run-tests.sh integration

# 4. Run validation to ensure changes don't break deployment
./validate/run-validation.sh

# 5. Test your changes end-to-end (optional, requires AWS)
./tests/run-tests.sh e2e

# 6. Update documentation if needed
# Edit README.md, TESTING.md, VALIDATION.md, etc.

# 7. Commit your changes
git add .
git commit -m "feat: add your feature description"
```

## Testing Requirements

### All Contributions Must Include Tests

Every contribution must include appropriate tests. See [TESTING.md](TESTING.md) for detailed testing guidelines.

#### For New Features
- **Unit tests** for new functions (in `tests/unit/`)
- **Integration tests** for component interactions (in `tests/integration/`)
- **Documentation updates** in TESTING.md
- **Test coverage** for success and failure scenarios

#### For Bug Fixes
- **Regression tests** that reproduce the bug
- **Unit tests** for the fixed functionality
- **Integration tests** if the bug affected component interactions

### Test Checklist

Before submitting a PR, ensure:
- [ ] Unit tests pass: `./tests/run-tests.sh unit`
- [ ] Integration tests pass: `./tests/run-tests.sh integration`
- [ ] Validation passes: `./validate/run-validation.sh`
- [ ] No existing tests are broken
- [ ] Test coverage includes edge cases and error conditions
- [ ] Tests are documented in TESTING.md

## Code Standards

### Bash Script Conventions

All bash scripts must follow these patterns (see [.cursor/rules/bash-script-patterns.mdc](.cursor/rules/bash-script-patterns.mdc)):

```bash
#!/bin/bash

# Script description
# What this script does

set -e

# Color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m"

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
```

### Idempotency Requirements

**All scripts must be idempotent** (see [README.md#idempotency](README.md#idempotency) and [.cursor/rules/idempotency-principles.mdc](.cursor/rules/idempotency-principles.mdc)):

- ✅ Check current state before making changes
- ✅ Compare current vs desired state
- ✅ Skip operations when state matches desired
- ✅ Update only when necessary
- ✅ Never create duplicate resources
- ✅ Log all actions taken or skipped

### Function Documentation

Every function must be documented:

```bash
# Creates or updates S3 bucket with proper configuration
# Idempotent: Checks if bucket exists and has correct settings
# Parameters:
#   $1 - bucket name
#   $2 - region
# Returns: 0 on success, 1 on failure
create_s3_bucket() {
    # Implementation
}
```

## Pull Request Process

### 1. Pre-Submission Checklist

- [ ] **Tests pass**: All tests run successfully
- [ ] **Validation passes**: `./validate/run-validation.sh` succeeds
- [ ] **Documentation updated**: README.md and relevant docs updated
- [ ] **Idempotency verified**: Scripts handle existing resources correctly
- [ ] **Backwards compatibility**: No breaking changes without migration path
- [ ] **Security reviewed**: No credentials or sensitive data in code

### 2. PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring
- [ ] Other

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] E2E tests added/updated (if applicable)
- [ ] Manual testing performed

## Validation
- [ ] Pre-deployment validation passes
- [ ] Idempotency verified (run script 3+ times)
- [ ] No breaking changes

## Documentation
- [ ] README.md updated
- [ ] TESTING.md updated (if tests added)
- [ ] Other docs updated as needed
```

### 3. Review Process

1. **Automated checks**: Tests and validation run automatically
2. **Code review**: At least one maintainer review required
3. **Testing verification**: Reviewer runs tests locally
4. **Idempotency testing**: Reviewer verifies 3x run behavior
5. **Merge**: Squash merge with descriptive commit message

## Documentation Standards

### README.md Updates

When adding features, update these sections:
- **Features** section: Add new capability
- **Quick Start**: Include configuration examples
- **Project Structure**: Update file listings
- **Idempotency**: Document idempotent behavior
- **Configuration Options**: Add new config variables

### Testing Documentation

- **TESTING.md**: Document new test types and examples
- **Test file comments**: Explain what each test validates
- **Mock documentation**: Update aws-mock.bash with new mocks

### Validation Documentation

- **VALIDATION.md**: Document new validation checks
- **Error messages**: Include troubleshooting for new validations
- **Best practices**: Update usage guidelines

## Issue Reporting

### Bug Reports

Please include:
- **Steps to reproduce**: Detailed steps
- **Expected behavior**: What should happen
- **Actual behavior**: What actually happens
- **Environment**: OS, AWS CLI version, bash version
- **Logs**: Relevant error output
- **Configuration**: Sanitized config.env

### Feature Requests

Please include:
- **Problem statement**: What's the problem you're solving?
- **Proposed solution**: How should it work?
- **Alternatives considered**: Other approaches?
- **Use case**: When/how would this be used?

## Getting Help

- **Documentation**: Check README.md, TESTING.md, VALIDATION.md
- **Issues**: Search existing issues before creating new ones
- **Discussions**: Use GitHub Discussions for questions
- **Code examples**: Look at existing scripts for patterns

## Recognition

Contributors are recognized in:
- **CHANGELOG.md**: For significant features/bug fixes
- **GitHub contributors**: Automatic recognition
- **Release notes**: For major contributions

Thank you for contributing to make this project better! 🚀
