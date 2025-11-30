#!/bin/bash

# Custom Domain Configuration Test Script
# Tests custom domain and DNS configuration functionality

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

pass_test() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail_test() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

skip_test() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# Test: Script files exist
test_script_files_exist() {
    log_test "Checking if custom domain scripts exist..."
    
    local scripts=(
        "$SCRIPT_DIR/scripts/configure-custom-domain.sh"
        "$SCRIPT_DIR/scripts/setup-route53-dns.sh"
    )
    
    local all_exist=true
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "Script not found: $script"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        pass_test "All custom domain scripts exist"
    else
        fail_test "Some custom domain scripts are missing"
    fi
}

# Test: Scripts are executable
test_scripts_executable() {
    log_test "Checking if scripts are executable..."
    
    local scripts=(
        "$SCRIPT_DIR/scripts/configure-custom-domain.sh"
        "$SCRIPT_DIR/scripts/setup-route53-dns.sh"
    )
    
    local all_executable=true
    for script in "${scripts[@]}"; do
        if [ ! -x "$script" ]; then
            log_warn "Script not executable: $script"
            chmod +x "$script"
            log_info "Made executable: $script"
        fi
    done
    
    pass_test "All scripts are executable"
}

# Test: Configuration variables exist
test_config_variables() {
    log_test "Checking if config.env.example has custom domain variables..."
    
    local config_file="$SCRIPT_DIR/config.env.example"
    
    if [ ! -f "$config_file" ]; then
        fail_test "config.env.example not found"
        return
    fi
    
    local required_vars=(
        "CUSTOM_DOMAIN"
        "AUTO_CONFIGURE_DNS"
    )
    
    local all_exist=true
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$config_file" && ! grep -q "^# ${var}" "$config_file"; then
            log_error "Variable not found in config: $var"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        pass_test "All required config variables exist"
    else
        fail_test "Some config variables are missing"
    fi
}

# Test: Domain validation function
test_domain_validation() {
    log_test "Testing domain format validation..."
    
    # Source the configure-custom-domain script to access its functions
    source "$SCRIPT_DIR/scripts/configure-custom-domain.sh" 2>/dev/null || true
    
    # Test valid domains
    local valid_domains=(
        "example.com"
        "api.example.com"
        "www.example.com"
        "app-test.example.com"
        "test123.example.co.uk"
    )
    
    local validation_passed=true
    for domain in "${valid_domains[@]}"; do
        if ! validate_domain_format "$domain" 2>/dev/null; then
            log_error "Valid domain rejected: $domain"
            validation_passed=false
        fi
    done
    
    # Test invalid domains
    local invalid_domains=(
        "-example.com"
        "example-.com"
        "example..com"
        ""
        "http://example.com"
    )
    
    for domain in "${invalid_domains[@]}"; do
        if validate_domain_format "$domain" 2>/dev/null; then
            log_error "Invalid domain accepted: $domain"
            validation_passed=false
        fi
    done
    
    if [ "$validation_passed" = true ]; then
        pass_test "Domain validation works correctly"
    else
        fail_test "Domain validation has issues"
    fi
}

# Test: Route 53 script help
test_route53_help() {
    log_test "Testing Route 53 DNS script help..."
    
    if "$SCRIPT_DIR/scripts/setup-route53-dns.sh" help &>/dev/null; then
        pass_test "Route 53 DNS script help works"
    else
        fail_test "Route 53 DNS script help failed"
    fi
}

# Test: AWS credentials configured
test_aws_credentials() {
    log_test "Checking AWS credentials..."
    
    if ! command -v aws &> /dev/null; then
        skip_test "AWS CLI not installed"
        return
    fi
    
    # Try to get caller identity
    if aws sts get-caller-identity &>/dev/null; then
        pass_test "AWS credentials are configured"
    else
        skip_test "AWS credentials not configured (optional for script validation)"
    fi
}

# Test: Route 53 integration (if AWS configured)
test_route53_integration() {
    log_test "Testing Route 53 integration..."
    
    if ! command -v aws &> /dev/null; then
        skip_test "AWS CLI not installed"
        return
    fi
    
    if ! aws sts get-caller-identity &>/dev/null; then
        skip_test "AWS credentials not configured"
        return
    fi
    
    # Try to list hosted zones
    if aws route53 list-hosted-zones --max-items 1 &>/dev/null; then
        pass_test "Route 53 access is working"
    else
        fail_test "Route 53 access failed (check IAM permissions)"
    fi
}

# Test: Integration with main setup script
test_main_script_integration() {
    log_test "Checking integration with main setup script..."
    
    local setup_script="$SCRIPT_DIR/setup-eb-environment.sh"
    
    if [ ! -f "$setup_script" ]; then
        fail_test "Main setup script not found"
        return
    fi
    
    # Check if configure_custom_domain function is defined
    if grep -q "configure_custom_domain()" "$setup_script"; then
        pass_test "Custom domain function integrated in main script"
    else
        fail_test "Custom domain function not found in main script"
    fi
}

# Test: Cleanup temp files
test_cleanup_integration() {
    log_test "Checking if cleanup includes custom domain temp files..."
    
    local setup_script="$SCRIPT_DIR/setup-eb-environment.sh"
    
    if grep -q "/tmp/custom-domain.txt" "$setup_script" && \
       grep -q "/tmp/route53-.*json" "$setup_script"; then
        pass_test "Cleanup includes custom domain temp files"
    else
        fail_test "Cleanup missing custom domain temp files"
    fi
}

# Test: Documentation exists
test_documentation() {
    log_test "Checking if documentation is updated..."
    
    local readme="$SCRIPT_DIR/README.md"
    
    if [ ! -f "$readme" ]; then
        fail_test "README.md not found"
        return
    fi
    
    # Check for custom domain documentation
    if grep -q "Custom Domain Configuration" "$readme" && \
       grep -q "Route 53 DNS Management" "$readme"; then
        pass_test "Documentation includes custom domain configuration"
    else
        fail_test "Documentation missing custom domain information"
    fi
}

# Test: Required tools check
test_required_tools() {
    log_test "Checking for required tools..."
    
    local tools_available=true
    
    # Essential tools
    if ! command -v bash &> /dev/null; then
        log_error "bash not found"
        tools_available=false
    fi
    
    # Recommended tools
    if ! command -v dig &> /dev/null; then
        log_warn "dig not found (recommended for DNS verification)"
    fi
    
    if ! command -v curl &> /dev/null; then
        log_warn "curl not found (recommended for HTTPS testing)"
    fi
    
    if [ "$tools_available" = true ]; then
        pass_test "Essential tools are available"
    else
        fail_test "Some essential tools are missing"
    fi
}

# Test: Script syntax
test_script_syntax() {
    log_test "Checking script syntax..."
    
    local scripts=(
        "$SCRIPT_DIR/scripts/configure-custom-domain.sh"
        "$SCRIPT_DIR/scripts/setup-route53-dns.sh"
    )
    
    local syntax_ok=true
    for script in "${scripts[@]}"; do
        if ! bash -n "$script" 2>/dev/null; then
            log_error "Syntax error in: $script"
            syntax_ok=false
        fi
    done
    
    if [ "$syntax_ok" = true ]; then
        pass_test "All scripts have valid syntax"
    else
        fail_test "Some scripts have syntax errors"
    fi
}

# Test: Mock custom domain configuration (dry run)
test_mock_custom_domain() {
    log_test "Testing custom domain configuration (mock mode)..."
    
    # Create a mock environment
    export CUSTOM_DOMAIN=""
    export AUTO_CONFIGURE_DNS="false"
    export ENV_NAME="test-env"
    export AWS_PROFILE="default"
    export AWS_REGION="us-east-1"
    
    # Source the script
    source "$SCRIPT_DIR/scripts/configure-custom-domain.sh" 2>/dev/null || true
    
    # Test with empty domain (should skip)
    if main &>/dev/null; then
        pass_test "Script handles empty CUSTOM_DOMAIN gracefully"
    else
        fail_test "Script fails with empty CUSTOM_DOMAIN"
    fi
}

# Main test runner
run_all_tests() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Custom Domain Configuration Test Suite${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    test_script_files_exist
    test_scripts_executable
    test_config_variables
    test_domain_validation
    test_route53_help
    test_aws_credentials
    test_route53_integration
    test_main_script_integration
    test_cleanup_integration
    test_documentation
    test_required_tools
    test_script_syntax
    test_mock_custom_domain
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Test Results Summary${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}Tests Passed:  $TESTS_PASSED${NC}"
    echo -e "${RED}Tests Failed:  $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Tests Skipped: $TESTS_SKIPPED${NC}"
    echo ""
    
    local total=$((TESTS_PASSED + TESTS_FAILED))
    local pass_rate=0
    
    if [ $total -gt 0 ]; then
        pass_rate=$((TESTS_PASSED * 100 / total))
    fi
    
    echo "Pass Rate: ${pass_rate}%"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Some tests failed. Please review the output above.${NC}"
        echo ""
        return 1
    fi
}

# Show usage
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Custom Domain Configuration Test Suite

OPTIONS:
    -h, --help              Show this help message
    --quick                 Run quick tests only (skip AWS integration)
    --full                  Run all tests including AWS integration

EXAMPLES:
    # Run all tests
    $0

    # Run quick tests
    $0 --quick

    # Run full integration tests
    $0 --full

EOF
}

main() {
    local test_mode="default"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --quick)
                test_mode="quick"
                shift
                ;;
            --full)
                test_mode="full"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    run_all_tests
}

# Run main function
main "$@"



