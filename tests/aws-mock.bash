#!/usr/bin/env bash

# AWS CLI mocking for testing
# Load this in tests to mock AWS commands

# Mock state tracking (using environment variables that can be exported)
export MOCK_CURL_AVAILABLE="true"
export MOCK_DIG_AVAILABLE="true"
export MOCK_JQ_AVAILABLE="true"

# Helper function to extract argument value (portable alternative to grep -oP)
get_arg_value() {
    local arg_name="$1"
    local all_args="$2"
    # Use sed to extract the value after the argument
    echo "$all_args" | sed -n "s/.*${arg_name} \([^ ]*\).*/\1/p"
}

mock_aws() {
    # Handle --version flag before parsing service/operation
    if [[ "$1" == "--version" ]]; then
        echo "aws-cli/2.13.0 Python/3.11.0 Linux/5.15.0-119-generic exe/x86_64.ubuntu.22 prompt/off"
        return 0
    fi

    local service="$1"
    local operation="$2"
    shift 2
    local all_args="$*"

    case "$service.$operation" in
        # STS
        sts.get-caller-identity)
            if [[ "$all_args" == *"--query Account"* ]]; then
                echo "123456789012"
            elif [[ "$all_args" == *"--query Arn"* ]]; then
                echo "arn:aws:iam::123456789012:user/test-user"
            elif [[ "$all_args" == *"--query UserId"* ]]; then
                echo "test-user"
            else
                echo '{"Account": "123456789012", "UserId": "test-user", "Arn": "arn:aws:iam::123456789012:user/test-user"}'
            fi
            ;;

        # S3
        s3api.head-bucket)
            local bucket_name=$(get_arg_value "--bucket" "$all_args")
            if [[ "$bucket_name" == "test-static-assets" ]] || [[ "$bucket_name" == "test-uploads" ]] || [[ "$bucket_name" == "existing-bucket" ]]; then
                return 0
            else
                return 1
            fi
            ;;
        s3api.create-bucket)
            local bucket_name=$(get_arg_value "--bucket" "$all_args")
            MOCK_STATE["buckets"]="${MOCK_STATE["buckets"]} $bucket_name"
            echo '{"Location": "/'"$bucket_name"'"}'
            ;;
        s3api.get-bucket-versioning)
            local bucket_name=$(get_arg_value "--bucket" "$all_args")
            if [[ "$bucket_name" == "versioned-bucket" ]]; then
                echo "Enabled"
            else
                echo ""
            fi
            ;;
        s3api.put-bucket-versioning)
            return 0
            ;;
        s3api.get-bucket-cors)
            local bucket_name=$(get_arg_value "--bucket" "$all_args")
            if [[ "$bucket_name" == "cors-configured-bucket" ]]; then
                echo '{"CORSRules": [{"AllowedMethods": ["GET", "HEAD"], "AllowedOrigins": ["*"]}]}'
            else
                return 1
            fi
            ;;
        s3api.put-bucket-cors)
            return 0
            ;;
        s3api.get-public-access-block)
            local bucket_name=$(get_arg_value "--bucket" "$all_args")
            if [[ "$bucket_name" == "pab-configured-bucket" ]]; then
                echo '{"PublicAccessBlockConfiguration": {"BlockPublicAcls": true, "IgnorePublicAcls": true, "BlockPublicPolicy": false, "RestrictPublicBuckets": false}}'
            else
                return 1
            fi
            ;;
        s3api.put-public-access-block)
            return 0
            ;;
        s3api.list-buckets)
            echo '{"Buckets": [{"Name": "test-static-assets"}, {"Name": "test-uploads"}]}'
            ;;

        # IAM
        iam.get-role)
            local role_name=$(get_arg_value "--role-name" "$all_args")
            if [[ "$role_name" == "existing-role" ]] || [[ "$role_name" == "aws-elasticbeanstalk-ec2-role" ]]; then
                echo '{"Role": {"RoleName": "'"$role_name"'", "Arn": "arn:aws:iam::123456789012:role/'"$role_name"'"}}'
            else
                return 1
            fi
            ;;
        iam.create-role)
            local role_name=$(get_arg_value "--role-name" "$all_args")
            MOCK_STATE["roles"]="${MOCK_STATE["roles"]} $role_name"
            echo '{"Role": {"RoleName": "'"$role_name"'", "Arn": "arn:aws:iam::123456789012:role/'"$role_name"'"}}'
            ;;
        iam.attach-role-policy)
            return 0
            ;;
        iam.get-policy)
            local policy_arn=$(get_arg_value "--policy-arn" "$all_args")
            if [[ "$policy_arn" == *"existing-policy"* ]]; then
                echo '{"Policy": {"PolicyName": "existing-policy", "Arn": "'"$policy_arn"'", "DefaultVersionId": "v1"}}'
            else
                return 1
            fi
            ;;
        iam.get-policy-version)
            local version_id=$(get_arg_value "--version-id" "$all_args")
            [ -z "$version_id" ] && version_id="v1"
            echo '{"PolicyVersion": {"Document": {"Version": "2012-10-17", "Statement": []}, "VersionId": "'"$version_id"'"}}'
            ;;
        iam.list-policy-versions)
            echo '{"Versions": [{"VersionId": "v1", "IsDefaultVersion": true}, {"VersionId": "v2", "IsDefaultVersion": false}]}'
            ;;
        iam.create-policy-version)
            return 0
            ;;
        iam.delete-policy-version)
            return 0
            ;;
        iam.create-policy)
            local policy_name=$(get_arg_value "--policy-name" "$all_args")
            MOCK_STATE["policies"]="${MOCK_STATE["policies"]} $policy_name"
            echo '{"Policy": {"PolicyName": "'"$policy_name"'", "Arn": "arn:aws:iam::123456789012:policy/'"$policy_name"'"}}'
            ;;
        iam.get-instance-profile)
            local profile_name=$(get_arg_value "--instance-profile-name" "$all_args")
            if [[ "$profile_name" == "existing-profile"* ]] || [[ "$profile_name" == *"-profile" ]]; then
                echo '{"InstanceProfile": {"InstanceProfileName": "'"$profile_name"'", "Roles": [{"RoleName": "test-role"}]}}'
            else
                return 1
            fi
            ;;
        iam.create-instance-profile)
            local profile_name=$(get_arg_value "--instance-profile-name" "$all_args")
            MOCK_STATE["instance_profiles"]="${MOCK_STATE["instance_profiles"]} $profile_name"
            echo '{"InstanceProfile": {"InstanceProfileName": "'"$profile_name"'"}}'
            ;;
        iam.add-role-to-instance-profile)
            return 0
            ;;
        iam.list-roles)
            echo '{"Roles": [{"RoleName": "existing-role"}]}'
            ;;

        # Elastic Beanstalk
        elasticbeanstalk.describe-applications)
            local app_name=$(get_arg_value "--application-names" "$all_args")
            if [[ "$app_name" == "existing-app" ]] || [[ "$app_name" == "test-app" ]]; then
                echo '{"Applications": [{"ApplicationName": "'"$app_name"'", "DateCreated": "2024-01-01T00:00:00Z"}]}'
            else
                echo '{"Applications": []}'
            fi
            ;;
        elasticbeanstalk.create-application)
            local app_name=$(get_arg_value "--application-name" "$all_args")
            MOCK_STATE["applications"]="${MOCK_STATE["applications"]} $app_name"
            echo '{"Application": {"ApplicationName": "'"$app_name"'"}}'
            ;;
        elasticbeanstalk.describe-environments)
            local env_name=$(get_arg_value "--environment-names" "$all_args")
            if [[ "$env_name" == "existing-env" ]] || [[ "$env_name" == "test-env" ]]; then
                if [[ "$all_args" == *"--query"* ]]; then
                    local query=$(get_arg_value "--query" "$all_args")
                    if [[ "$query" == *"Status"* ]]; then
                        echo "Ready"
                    elif [[ "$query" == *"Health"* ]]; then
                        echo "Green"
                    elif [[ "$query" == *"CNAME"* ]] || [[ "$query" == *"EndpointURL"* ]]; then
                        echo "test-env.us-east-1.elasticbeanstalk.com"
                    elif [[ "$query" == *"[0]"* ]]; then
                        echo "Ready Green test-env.us-east-1.elasticbeanstalk.com"
                    else
                        echo '{"Environments": [{"EnvironmentName": "'"$env_name"'", "Status": "Ready", "Health": "Green", "CNAME": "test-env.us-east-1.elasticbeanstalk.com"}]}'
                    fi
                else
                    echo '{"Environments": [{"EnvironmentName": "'"$env_name"'", "Status": "Ready", "Health": "Green", "CNAME": "test-env.us-east-1.elasticbeanstalk.com"}]}'
                fi
            else
                echo '{"Environments": []}'
            fi
            ;;
        elasticbeanstalk.create-environment)
            local env_name=$(get_arg_value "--environment-name" "$all_args")
            MOCK_STATE["environments"]="${MOCK_STATE["environments"]} $env_name"
            echo '{"EnvironmentName": "'"$env_name"'", "Status": "Launching"}'
            ;;
        elasticbeanstalk.update-environment)
            echo '{"EnvironmentName": "test-env", "Status": "Updating"}'
            ;;
        elasticbeanstalk.describe-environment-resources)
            local env_name=$(get_arg_value "--environment-name" "$all_args")
            local query=$(get_arg_value "--query" "$all_args")
            if [[ "$env_name" == "nonexistent-env" ]]; then
                echo "None"
                return 1
            fi
            if [[ "$query" == *"LoadBalancers[0].Name"* ]]; then
                echo "test-lb-1234567890"
            elif [[ "$query" == *"LoadBalancers[0]"* ]]; then
                echo '{"LoadBalancers": [{"Name": "test-lb-1234567890"}]}'
            else
                echo '{"EnvironmentResources": {"LoadBalancers": [{"Name": "test-lb-1234567890"}]}}'
            fi
            ;;
        elasticbeanstalk.describe-configuration-settings)
            # Return multi-line JSON (like real AWS CLI does) for grep-based parsing
            cat << 'CONFIGJSON'
{
  "ConfigurationSettings": [
    {
      "OptionSettings": [
        {
          "Namespace": "aws:autoscaling:launchconfiguration",
          "OptionName": "InstanceType",
          "Value": "t3.micro"
        },
        {
          "Namespace": "aws:autoscaling:asg",
          "OptionName": "MinSize",
          "Value": "1"
        },
        {
          "Namespace": "aws:autoscaling:asg",
          "OptionName": "MaxSize",
          "Value": "2"
        },
        {
          "Namespace": "aws:elasticbeanstalk:application:environment",
          "OptionName": "STATIC_ASSETS_BUCKET",
          "Value": "test-static-assets"
        },
        {
          "Namespace": "aws:elasticbeanstalk:application:environment",
          "OptionName": "UPLOADS_BUCKET",
          "Value": "test-uploads"
        }
      ]
    }
  ]
}
CONFIGJSON
            ;;
        elasticbeanstalk.list-available-solution-stacks)
            local query=$(get_arg_value "--query" "$all_args")
            if [[ "$query" == *"contains"* ]]; then
                # Handle query with filter
                if [[ "$all_args" == *"Python"* ]]; then
                    echo "64bit Amazon Linux 2023 v4.0.0 running Python 3.11"
                elif [[ "$all_args" == *"Node"* ]]; then
                    echo "64bit Amazon Linux 2 v5.8.0 running Node.js 18"
                else
                    echo "None"
                fi
            else
                echo '{"SolutionStacks": ["64bit Amazon Linux 2 v5.8.0 running Node.js 18", "64bit Amazon Linux 2023 v4.0.0 running Python 3.11"]}'
            fi
            ;;
        elasticbeanstalk.describe-events)
            echo '{"Events": [{"EventDate": "2024-01-01T00:00:00Z", "Severity": "INFO", "Message": "Environment update completed"}]}'
            ;;

        # ELB/ELBv2
        elbv2.describe-load-balancers)
            local query=$(get_arg_value "--query" "$all_args")
            if [[ "$all_args" == *"--names"* ]]; then
                local lb_name=$(get_arg_value "--names" "$all_args")
                if [[ -z "$lb_name" ]] || [[ "$lb_name" == "None" ]]; then
                    echo "None"
                    return 1
                fi
                if [[ "$query" == *"DNSName"* ]]; then
                    echo "test-lb-1234567890.us-east-1.elb.amazonaws.com"
                elif [[ "$query" == *"CanonicalHostedZoneId"* ]]; then
                    echo "Z35SXDOTRQ7X7K"
                elif [[ "$query" == *"LoadBalancerArn"* ]]; then
                    echo "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-lb/1234567890abcdef"
                else
                    echo '{"LoadBalancers": [{"LoadBalancerArn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-lb/1234567890abcdef", "DNSName": "test-lb-1234567890.us-east-1.elb.amazonaws.com", "CanonicalHostedZoneId": "Z35SXDOTRQ7X7K"}]}'
                fi
            else
                echo '{"LoadBalancers": [{"LoadBalancerArn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-lb/1234567890abcdef", "DNSName": "test-lb-1234567890.us-east-1.elb.amazonaws.com"}]}'
            fi
            ;;
        elbv2.describe-listeners)
            local query=$(get_arg_value "--query" "$all_args")
            if [[ "$query" == *"ListenerArn"* ]]; then
                echo "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-lb/1234567890abcdef/abcdef1234567890"
            else
                echo '{"Listeners": [{"ListenerArn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-lb/1234567890abcdef/abcdef1234567890", "Port": 80}]}'
            fi
            ;;
        elbv2.modify-listener)
            return 0
            ;;

        # Route53
        route53.list-hosted-zones)
            local query=$(get_arg_value "--query" "$all_args")
            if [[ "$query" == *"HostedZones"* ]]; then
                if [[ "$all_args" == *"example.com"* ]] || [[ "$all_args" == *"test.com"* ]]; then
                    echo "/hostedzone/Z1234567890ABC"
                else
                    echo "None"
                fi
            else
                echo '{"HostedZones": [{"Name": "example.com.", "Id": "/hostedzone/Z1234567890ABC", "ResourceRecordSetCount": 2}]}'
            fi
            ;;
        route53.list-resource-record-sets)
            local query=$(get_arg_value "--query" "$all_args")
            if [[ "$query" == *"ResourceRecordSets"* ]]; then
                if [[ "$all_args" == *"existing.example.com"* ]]; then
                    if [[ "$all_args" == *"CNAME"* ]]; then
                        echo '[{"Name": "existing.example.com.", "Type": "CNAME", "TTL": 300, "ResourceRecords": [{"Value": "test-lb.us-east-1.elb.amazonaws.com"}]}]'
                    elif [[ "$all_args" == *"Type=='"'"'A'"'"'"* ]]; then
                        echo '[{"Name": "existing.example.com.", "Type": "A", "AliasTarget": {"DNSName": "test-lb.us-east-1.elb.amazonaws.com.", "HostedZoneId": "Z35SXDOTRQ7X7K"}}]'
                    else
                        echo '[{"Name": "existing.example.com.", "Type": "CNAME", "TTL": 300, "ResourceRecords": [{"Value": "test-lb.us-east-1.elb.amazonaws.com"}]}]'
                    fi
                else
                    echo "[]"
                fi
            else
                echo '{"ResourceRecordSets": [{"Name": "example.com.", "Type": "A", "TTL": 300}]}'
            fi
            ;;
        route53.change-resource-record-sets)
            echo '{"ChangeInfo": {"Id": "C1234567890ABC", "Status": "PENDING"}}'
            ;;
        route53.create-hosted-zone)
            echo '{"HostedZone": {"Id": "/hostedzone/Z1234567890ABC", "Name": "example.com."}, "DelegationSet": {"NameServers": ["ns-123.awsdns-12.com", "ns-456.awsdns-45.net"]}}'
            ;;

        # ACM
        acm.list-certificates)
            local query=$(get_arg_value "--query" "$all_args")
            if [[ "$query" == *"CertificateSummaryList"* ]]; then
                if [[ "$all_args" == *"example.com"* ]]; then
                    echo "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
                else
                    echo "None"
                fi
            else
                echo '{"CertificateSummaryList": [{"DomainName": "example.com", "CertificateArn": "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"}]}'
            fi
            ;;
        acm.describe-certificate)
            local query=$(get_arg_value "--query" "$all_args")
            local mock_status="${MOCK_ACM_CERT_STATUS:-ISSUED}"
            if [[ "$query" == *"Status"* ]]; then
                echo "$mock_status"
            elif [[ "$query" == *"DomainValidationOptions"* ]]; then
                echo '[{"DomainName": "example.com", "ValidationStatus": "SUCCESS", "ResourceRecord": {"Name": "_example.com", "Type": "CNAME", "Value": "validation-value"}}]'
            else
                echo '{"Certificate": {"Status": "'"$mock_status"'", "DomainName": "example.com", "DomainValidationOptions": [{"DomainName": "example.com", "ValidationStatus": "SUCCESS"}]}}'
            fi
            ;;

        *)
            echo "Mock not implemented: aws $service $operation" >&2
            return 1
            ;;
    esac
}

# Override aws command - checks TEST_MODE at runtime
aws() {
    if [ "$TEST_MODE" = "true" ]; then
        mock_aws "$@"
    else
        command aws "$@"
    fi
}

# Mock external tools
mock_curl() {
    local all_args="$*"
    # Default successful response
    if [[ "$all_args" == *"--silent"* ]] && [[ "$all_args" == *"--fail"* ]]; then
        # HTTPS connectivity test - succeed by default
        return 0
    elif [[ "$all_args" == *"--connect-timeout"* ]] && [[ "$all_args" == *"--max-time"* ]]; then
        # HTTPS endpoint test - succeed by default
        return 0
    else
        # Generic curl success
        echo "Mock curl response"
        return 0
    fi
}

mock_dig() {
    local all_args="$*"
    # Mock DNS lookups - return test values based on query type
    if [[ "$all_args" == *"NS"* ]]; then
        # NS record queries for DNS provider detection - extract domain from args
        local domain=""
        for arg in "$@"; do
            if [[ "$arg" == "NS" ]]; then
                continue
            elif [[ "$arg" == *".com" ]] && [[ "$arg" != *"+"* ]] && [[ "$arg" != *"-"* ]]; then
                domain="$arg"
                break
            fi
        done

        case "$domain" in
            godaddy.com)
                echo "ns1.godaddy.com"
                echo "ns2.godaddy.com"
                ;;
            route53-domain.com)
                echo "ns1.awsdns-12.com"
                echo "ns2.awsdns-45.net"
                ;;
            example.com)
                echo "ns1.awsdns-12.com"
                echo "ns2.awsdns-45.net"
                ;;
            *)
                echo "ns1.unknown-provider.com"
                ;;
        esac
    else
        # Regular A/CNAME lookups
        if [[ "$all_args" == *"example.com"* ]]; then
            echo "test-lb.us-east-1.elb.amazonaws.com"
        elif [[ "$all_args" == *"api.example.com"* ]]; then
            echo "api-lb.us-east-1.elb.amazonaws.com"
        else
            echo "mock-dns-response"
        fi
    fi
    return 0
}

mock_jq() {
    # Parse options and arguments
    local compact=false
    local sort_keys=false
    local filter=""
    local file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--compact-output)
                compact=true
                shift
                ;;
            -S|--sort-keys)
                sort_keys=true
                shift
                ;;
            -*)
                # Ignore other options
                shift
                ;;
            *)
                if [ -z "$filter" ]; then
                    filter="$1"
                elif [ -z "$file" ]; then
                    file="$1"
                fi
                shift
                ;;
        esac
    done

    # Read input from file or stdin
    local input
    if [ -n "$file" ] && [ -f "$file" ]; then
        input=$(cat "$file")
    else
        input=$(cat)
    fi

    # Simple mock jq that handles basic filters used in tests
    case "$filter" in
        '.')
            # Identity filter - return input as-is
            echo "$input"
            ;;
        '.[]')
            # Extract array elements - mock behavior
            if [[ "$input" == *'['* ]]; then
                # If input looks like JSON array, return mock elements
                echo '{"mock": "array_element"}'
            else
                echo "$input"
            fi
            ;;
        *'.Name'*)
            # Extract Name field - return mock names
            echo "mock-name"
            ;;
        *'.Value'*)
            # Extract Value field - return mock values
            echo "mock-value"
            ;;
        *'.Type'*)
            # Extract Type field - return CNAME for DNS tests
            echo "CNAME"
            ;;
        *)
            # Default: return input formatted as if processed by jq
            echo "$input" | tr -d '\n' | sed 's/  */ /g'
            ;;
    esac
    return 0
}

# Override external commands when in test mode
curl() {
    if [ "$TEST_MODE" = "true" ]; then
        mock_curl "$@"
    else
        command curl "$@"
    fi
}

# Function to dynamically control curl availability
mock_command() {
    if [[ "$1" = "-v" ]]; then
        local cmd="$2"
        case "$cmd" in
            curl)
                if [[ "$MOCK_CURL_AVAILABLE" = "true" ]]; then
                    echo "curl"
                    return 0
                else
                    return 1
                fi
                ;;
            dig)
                if [[ "$MOCK_DIG_AVAILABLE" = "true" ]]; then
                    echo "dig"
                    return 0
                else
                    return 1
                fi
                ;;
            jq)
                if [[ "$MOCK_JQ_AVAILABLE" = "true" ]]; then
                    echo "jq"
                    return 0
                else
                    return 1
                fi
                ;;
            *)
                builtin command "$@"
                ;;
        esac
    else
        builtin command "$@"
    fi
}

# Override command builtin to control tool availability
command() {
    if [ "$TEST_MODE" = "true" ]; then
        mock_command "$@"
    else
        builtin command "$@"
    fi
}

dig() {
    if [ "$TEST_MODE" = "true" ]; then
        mock_dig "$@"
    else
        command dig "$@"
    fi
}

jq() {
    if [ "$TEST_MODE" = "true" ]; then
        mock_jq "$@"
    else
        command jq "$@"
    fi
}

# Control functions for mock state
set_mock_curl_available() {
    export MOCK_CURL_AVAILABLE="$1"
}

set_mock_dig_available() {
    export MOCK_DIG_AVAILABLE="$1"
}

set_mock_jq_available() {
    export MOCK_JQ_AVAILABLE="$1"
}

# Export functions so they're available in subshells (needed for bats' `run` command)
export -f aws
export -f mock_aws
export -f get_arg_value
export -f curl
export -f mock_curl
export -f dig
export -f mock_dig
export -f jq
export -f mock_jq
export -f command
export -f mock_command
export -f set_mock_curl_available
export -f set_mock_dig_available
export -f set_mock_jq_available
