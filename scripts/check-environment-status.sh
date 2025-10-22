#!/bin/bash

# Quick script to check Elastic Beanstalk environment status
# Useful for checking status after script timeout or during troubleshooting

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Color codes
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.env"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║     Elastic Beanstalk Environment Status Checker              ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if environment exists
echo -e "${CYAN}Checking environment: $ENV_NAME${NC}"
echo ""

if ! aws elasticbeanstalk describe-environments \
    --application-name "$APP_NAME" \
    --environment-names "$ENV_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" 2>/dev/null | grep -q "$ENV_NAME"; then
    echo -e "${RED}[ERROR]${NC} Environment '$ENV_NAME' not found"
    exit 1
fi

# Get environment details
echo "═══════════════════════════════════════════════════════════════"
echo "  Environment Status"
echo "═══════════════════════════════════════════════════════════════"
echo ""

env_info=$(aws elasticbeanstalk describe-environments \
    --application-name "$APP_NAME" \
    --environment-names "$ENV_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query "Environments[0].[Status,Health,HealthStatus,EndpointURL]" \
    --output text)

status=$(echo "$env_info" | awk '{print $1}')
health=$(echo "$env_info" | awk '{print $2}')
health_status=$(echo "$env_info" | awk '{print $3}')
url=$(echo "$env_info" | awk '{print $4}')

# Color code the status
case "$status" in
    "Ready")
        status_color="${GREEN}"
        ;;
    "Launching"|"Updating")
        status_color="${YELLOW}"
        ;;
    "Terminated"|"Terminating")
        status_color="${RED}"
        ;;
    *)
        status_color="${NC}"
        ;;
esac

# Color code the health
case "$health" in
    "Green")
        health_color="${GREEN}"
        ;;
    "Yellow")
        health_color="${YELLOW}"
        ;;
    "Red"|"Grey")
        health_color="${RED}"
        ;;
    *)
        health_color="${NC}"
        ;;
esac

echo -e "Status:        ${status_color}${status}${NC}"
echo -e "Health:        ${health_color}${health}${NC}"
echo -e "Health Status: ${health_status}"
echo -e "URL:           ${url}"
echo ""

# Show recent events
echo "═══════════════════════════════════════════════════════════════"
echo "  Recent Events (Last 10)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

aws elasticbeanstalk describe-events \
    --application-name "$APP_NAME" \
    --environment-name "$ENV_NAME" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --max-items 10 \
    --query "Events[*].[EventDate,Severity,Message]" \
    --output table

echo ""

# Provide recommendations based on status
if [ "$status" = "Ready" ]; then
    if [ "$health" = "Green" ]; then
        echo -e "${GREEN}✓${NC} Environment is healthy and ready!"
        echo ""
        echo "You can access your application at: http://$url"
    elif [ "$health" = "Yellow" ]; then
        echo -e "${YELLOW}⚠${NC} Environment is ready but health is degraded."
        echo "Check the events above for details."
    else
        echo -e "${RED}✗${NC} Environment is ready but not healthy."
        echo "Check the events and application logs for issues."
    fi
elif [ "$status" = "Launching" ] || [ "$status" = "Updating" ]; then
    echo -e "${YELLOW}⏳${NC} Environment is still $status..."
    echo "This typically takes 5-10 minutes. Run this script again to check progress."
elif [ "$status" = "Terminated" ] || [ "$status" = "Terminating" ]; then
    echo -e "${RED}✗${NC} Environment is $status."
    echo "Check the events above for error details."
fi

echo ""

