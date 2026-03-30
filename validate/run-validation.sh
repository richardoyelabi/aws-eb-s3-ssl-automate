#!/bin/bash

# Pre-deployment validation runner
# Validates prerequisites, permissions, configuration, and environment readiness
# Usage: Run before setup-eb-environment.sh to ensure deployment readiness

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/load-infrastructure-config.sh"

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Runs validate/*.sh using the same config resolution as setup-eb-environment.sh:
INFRA_CONFIG, then --config FILE, then --env NAME / INFRA_ENV, then config.env.

OPTIONS:
    -h, --help          Show this help
    -c, --config FILE   Explicit configuration file
    -e, --env NAME      Use config.NAME.env in the project root

EOF
}

cli_config=""
cli_env=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -c|--config)
            cli_config="$2"
            shift 2
            ;;
        -e|--env)
            cli_env="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

infrastructure_config_export_for_children "$SCRIPT_DIR" "$cli_config" "$cli_env"

echo ""
echo -e "${CYAN}🔍 AWS EB Environment Validation${NC}"
echo -e "${CYAN}=================================${NC}"
echo ""

# Run validation checks in order
./validate/prerequisites.sh
./validate/permissions.sh
./validate/config.sh
./validate/rds.sh
./validate/environment.sh

echo ""
echo -e "${GREEN}✅ All validations passed!${NC}"
echo -e "${GREEN}Ready to deploy with: ./setup-eb-environment.sh${NC}"
echo ""
