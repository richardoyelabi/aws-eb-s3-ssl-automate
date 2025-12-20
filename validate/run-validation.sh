#!/bin/bash

# Pre-deployment validation runner
# Validates prerequisites, permissions, configuration, and environment readiness
# Usage: Run before setup-eb-environment.sh to ensure deployment readiness

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

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
