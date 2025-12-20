#!/bin/bash

# RDS Database validation
# Validates RDS configuration before deployment

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

validate_rds_configuration() {
    echo ""
    log_info "Validating RDS database configuration..."

    if [ ! -f "$SCRIPT_DIR/config.env" ]; then
        log_fail "Configuration file not found: $SCRIPT_DIR/config.env"
        return 1
    fi

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    local has_errors=false
    local has_warnings=false

    # Validate required variables
    local required_vars=(
        "DB_ENGINE"
        "DB_ENGINE_VERSION"
        "DB_INSTANCE_CLASS"
        "DB_ALLOCATED_STORAGE"
        "DB_STORAGE_TYPE"
        "DB_NAME"
        "DB_USERNAME"
    )

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_fail "Required variable not set: $var"
            has_errors=true
        else
            log_success "Variable set: $var = ${!var}"
        fi
    done

    if [ "$has_errors" = true ]; then
        return 1
    fi

    log_success "All required RDS variables are set"
    return 0
}

validate_db_engine() {
    echo ""
    log_info "Validating database engine..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    local supported_engines=("postgres" "mysql" "mariadb")
    local is_supported=false

    for engine in "${supported_engines[@]}"; do
        if [ "$DB_ENGINE" = "$engine" ]; then
            is_supported=true
            break
        fi
    done

    if [ "$is_supported" = false ]; then
        log_fail "Unsupported database engine: $DB_ENGINE"
        echo "  Supported engines: ${supported_engines[*]}"
        return 1
    fi

    log_success "Database engine is supported: $DB_ENGINE"
    return 0
}

validate_instance_class() {
    echo ""
    log_info "Validating instance class..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    # Check if instance class follows AWS naming convention
    if [[ ! $DB_INSTANCE_CLASS =~ ^db\.[a-z0-9]+\.[a-z0-9]+$ ]]; then
        log_fail "Invalid instance class format: $DB_INSTANCE_CLASS"
        echo "  Expected format: db.<family>.<size> (e.g., db.t3.micro)"
        return 1
    fi

    log_success "Instance class format is valid: $DB_INSTANCE_CLASS"

    # Check if instance class is available in region (requires AWS CLI)
    if command -v aws &> /dev/null; then
        log_info "Checking if instance class is available in region..."
        
        if ! aws rds describe-orderable-db-instance-options \
            --engine "$DB_ENGINE" \
            --engine-version "$DB_ENGINE_VERSION" \
            --db-instance-class "$DB_INSTANCE_CLASS" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "OrderableDBInstanceOptions[0].DBInstanceClass" \
            --output text 2>/dev/null | grep -q "$DB_INSTANCE_CLASS"; then
            log_warn "Instance class may not be available: $DB_INSTANCE_CLASS"
            echo "  Verify with: aws rds describe-orderable-db-instance-options --engine $DB_ENGINE --region $AWS_REGION"
            return 1
        fi
        
        log_success "Instance class is available in region"
    else
        log_warn "AWS CLI not available, skipping instance class availability check"
    fi

    return 0
}

validate_storage_settings() {
    echo ""
    log_info "Validating storage settings..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    local has_errors=false

    # Validate allocated storage
    if [ "$DB_ALLOCATED_STORAGE" -lt 20 ]; then
        log_fail "Allocated storage too small: ${DB_ALLOCATED_STORAGE}GB (minimum: 20GB)"
        has_errors=true
    elif [ "$DB_ALLOCATED_STORAGE" -gt 65536 ]; then
        log_fail "Allocated storage too large: ${DB_ALLOCATED_STORAGE}GB (maximum: 65536GB)"
        has_errors=true
    else
        log_success "Allocated storage is valid: ${DB_ALLOCATED_STORAGE}GB"
    fi

    # Validate storage type
    local valid_types=("gp2" "gp3" "io1" "io2" "standard")
    local is_valid=false
    
    for type in "${valid_types[@]}"; do
        if [ "$DB_STORAGE_TYPE" = "$type" ]; then
            is_valid=true
            break
        fi
    done

    if [ "$is_valid" = false ]; then
        log_fail "Invalid storage type: $DB_STORAGE_TYPE"
        echo "  Valid types: ${valid_types[*]}"
        has_errors=true
    else
        log_success "Storage type is valid: $DB_STORAGE_TYPE"
    fi

    if [ "$has_errors" = true ]; then
        return 1
    fi

    return 0
}

validate_backup_settings() {
    echo ""
    log_info "Validating backup settings..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    local has_errors=false

    # Validate backup retention days
    if [ "$DB_BACKUP_RETENTION_DAYS" -lt 0 ] || [ "$DB_BACKUP_RETENTION_DAYS" -gt 35 ]; then
        log_fail "Invalid backup retention days: $DB_BACKUP_RETENTION_DAYS (must be 0-35)"
        has_errors=true
    else
        log_success "Backup retention days is valid: $DB_BACKUP_RETENTION_DAYS"
    fi

    # Validate backup window format (HH:MM-HH:MM)
    if [[ ! $DB_BACKUP_WINDOW =~ ^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$ ]]; then
        log_fail "Invalid backup window format: $DB_BACKUP_WINDOW"
        echo "  Expected format: HH:MM-HH:MM (e.g., 03:00-04:00)"
        has_errors=true
    else
        log_success "Backup window format is valid: $DB_BACKUP_WINDOW"
    fi

    # Validate maintenance window format (ddd:HH:MM-ddd:HH:MM)
    if [[ ! $DB_MAINTENANCE_WINDOW =~ ^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$ ]]; then
        log_fail "Invalid maintenance window format: $DB_MAINTENANCE_WINDOW"
        echo "  Expected format: ddd:HH:MM-ddd:HH:MM (e.g., mon:04:00-mon:05:00)"
        has_errors=true
    else
        log_success "Maintenance window format is valid: $DB_MAINTENANCE_WINDOW"
    fi

    if [ "$has_errors" = true ]; then
        return 1
    fi

    return 0
}

validate_database_name() {
    echo ""
    log_info "Validating database name..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    # Validate database name
    # PostgreSQL: alphanumeric and underscores, must start with letter or underscore
    if [[ ! $DB_NAME =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        log_fail "Invalid database name: $DB_NAME"
        echo "  Database name must start with a letter or underscore and contain only alphanumeric characters and underscores"
        return 1
    fi

    # Check length (PostgreSQL max is 63, MySQL is 64)
    local length=${#DB_NAME}
    if [ $length -gt 63 ]; then
        log_fail "Database name too long: $DB_NAME (${length} characters, max 63)"
        return 1
    fi

    log_success "Database name is valid: $DB_NAME"
    return 0
}

validate_username() {
    echo ""
    log_info "Validating database username..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    # Validate username
    if [[ ! $DB_USERNAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        log_fail "Invalid username: $DB_USERNAME"
        echo "  Username must start with a letter and contain only alphanumeric characters and underscores"
        return 1
    fi

    # Check length
    local length=${#DB_USERNAME}
    if [ $length -lt 1 ] || [ $length -gt 16 ]; then
        log_fail "Username length invalid: $DB_USERNAME (must be 1-16 characters)"
        return 1
    fi

    # Check for reserved usernames
    local reserved_names=("admin" "root" "rdsadmin" "postgres" "mysql" "mariadb")
    for reserved in "${reserved_names[@]}"; do
        if [ "$DB_USERNAME" = "$reserved" ]; then
            log_warn "Username is a common reserved name: $DB_USERNAME"
            echo "  Consider using a different username to avoid conflicts"
            break
        fi
    done

    log_success "Database username is valid: $DB_USERNAME"
    return 0
}

validate_password_policy() {
    echo ""
    log_info "Validating password policy..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    if [ -z "$DB_MASTER_PASSWORD" ]; then
        log_info "No password set in config - will be auto-generated"
        log_success "Auto-generated passwords meet AWS requirements"
    else
        # Validate password requirements
        local length=${#DB_MASTER_PASSWORD}
        
        if [ $length -lt 8 ]; then
            log_fail "Password too short (minimum 8 characters)"
            return 1
        fi
        
        if [ $length -gt 128 ]; then
            log_fail "Password too long (maximum 128 characters)"
            return 1
        fi
        
        # Check for printable ASCII characters
        if [[ ! $DB_MASTER_PASSWORD =~ ^[[:print:]]+$ ]]; then
            log_warn "Password contains non-printable characters"
        fi
        
        log_success "Password meets length requirements"
        log_warn "Remember: Password should not contain /, \", or @"
    fi

    return 0
}

validate_security_settings() {
    echo ""
    log_info "Validating security settings..."

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config.env"

    local has_warnings=false

    # Check if publicly accessible (should be false for security)
    if [ "$DB_PUBLICLY_ACCESSIBLE" = "true" ]; then
        log_warn "Database is configured as publicly accessible"
        echo "  For production, consider setting DB_PUBLICLY_ACCESSIBLE=false"
        has_warnings=true
    else
        log_success "Database is not publicly accessible (recommended)"
    fi

    # Check if encryption is enabled
    if [ "$DB_STORAGE_ENCRYPTED" = "true" ]; then
        log_success "Storage encryption is enabled (recommended)"
    else
        log_warn "Storage encryption is disabled"
        echo "  For production, consider setting DB_STORAGE_ENCRYPTED=true"
        has_warnings=true
    fi

    # Check Multi-AZ for production
    if [ "$DB_MULTI_AZ" = "true" ]; then
        log_success "Multi-AZ deployment is enabled (recommended for production)"
    else
        log_warn "Multi-AZ deployment is disabled"
        echo "  For production high availability, consider setting DB_MULTI_AZ=true"
        has_warnings=true
    fi

    return 0
}

main() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  RDS Database Configuration Validation${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    local exit_code=0

    validate_rds_configuration || exit_code=1
    validate_db_engine || exit_code=1
    validate_instance_class || exit_code=1
    validate_storage_settings || exit_code=1
    validate_backup_settings || exit_code=1
    validate_database_name || exit_code=1
    validate_username || exit_code=1
    validate_password_policy || exit_code=1
    validate_security_settings  # Warnings only

    echo ""
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  RDS Configuration Validation Passed ✓${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    else
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  RDS Configuration Validation Failed ✗${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    fi
    echo ""

    return $exit_code
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

