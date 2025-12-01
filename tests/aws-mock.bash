#!/usr/bin/env bash

# AWS CLI mocking for testing
# Load this in tests to mock AWS commands

mock_aws() {
    local service="$1"
    local operation="$2"
    shift 2

    case "$service.$operation" in
        sts.get-caller-identity)
            echo '{"Account": "123456789012", "UserId": "test-user", "Arn": "arn:aws:iam::123456789012:user/test-user"}'
            ;;
        s3api.head-bucket)
            if [[ "$*" == *"--bucket test-bucket-exists"* ]]; then
                return 0
            else
                return 1
            fi
            ;;
        elasticbeanstalk.describe-applications)
            echo '{"Applications": [{"ApplicationName": "test-app", "DateCreated": "2024-01-01T00:00:00Z"}]}'
            ;;
        # Add more mocks as needed
        *)
            echo "Mock not implemented: aws $service $operation" >&2
            return 1
            ;;
    esac
}

# Override aws command when TEST_MODE is set
if [ "$TEST_MODE" = true ]; then
    aws() {
        mock_aws "$@"
    }
fi
