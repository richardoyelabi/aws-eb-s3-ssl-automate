#!/bin/bash

# RDS Database Setup Module
# Creates and configures PostgreSQL RDS instance with Multi-AZ deployment and automated backups

set -e

# Color codes for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Validates autoscaling configuration parameters
# Returns: 0 on success, exits on validation failure
validate_autoscaling_config() {
    if [ "${DB_STORAGE_AUTOSCALING_ENABLED:-true}" = "true" ]; then
        local max_storage="${DB_MAX_ALLOCATED_STORAGE:-100}"
        local current_storage="${DB_ALLOCATED_STORAGE:-20}"
        
        if [ "$max_storage" -le "$current_storage" ]; then
            log_error "DB_MAX_ALLOCATED_STORAGE ($max_storage GB) must be greater than DB_ALLOCATED_STORAGE ($current_storage GB)"
            exit 1
        fi
        
        log_info "Storage autoscaling validation passed: $current_storage GB -> max $max_storage GB"
    fi
    
    if [ "${DB_READ_REPLICA_ENABLED:-false}" = "true" ]; then
        local min_replicas="${DB_READ_REPLICA_MIN_CAPACITY:-1}"
        local max_replicas="${DB_READ_REPLICA_MAX_CAPACITY:-3}"
        local initial_count="${DB_READ_REPLICA_COUNT:-1}"
        
        if [ "$min_replicas" -gt "$max_replicas" ]; then
            log_error "DB_READ_REPLICA_MIN_CAPACITY ($min_replicas) cannot be greater than DB_READ_REPLICA_MAX_CAPACITY ($max_replicas)"
            exit 1
        fi
        
        if [ "$initial_count" -lt "$min_replicas" ] || [ "$initial_count" -gt "$max_replicas" ]; then
            log_error "DB_READ_REPLICA_COUNT ($initial_count) must be between min ($min_replicas) and max ($max_replicas)"
            exit 1
        fi
        
        log_info "Read replica validation passed: initial=$initial_count, range=$min_replicas-$max_replicas"
    fi
}

# Generates or retrieves database master password
# Idempotent: Checks if password already exists in Secrets Manager
# Returns: Password string (auto-generated or from config)
generate_db_password() {
    local secret_name="${APP_NAME}/${ENV_NAME}/db-password"
    
    # Check if password is provided in config
    if [ -n "$DB_MASTER_PASSWORD" ]; then
        log_info "Using database password from config.env"
        echo "$DB_MASTER_PASSWORD"
        return 0
    fi
    
    log_info "Checking for existing database password in Secrets Manager..."
    
    # Check if secret already exists
    local existing_secret=$(aws secretsmanager describe-secret \
        --secret-id "$secret_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_secret" ]; then
        log_info "Password already exists in Secrets Manager"
        log_info "Retrieving existing password..."
        
        local password=$(aws secretsmanager get-secret-value \
            --secret-id "$secret_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "SecretString" \
            --output text)
        
        echo "$password"
        return 0
    fi
    
    log_info "Generating secure database password..."
    
    # Generate secure random password (32 chars, alphanumeric + special chars)
    local password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    
    log_info "Storing password in AWS Secrets Manager..."
    
    aws secretsmanager create-secret \
        --name "$secret_name" \
        --description "Master password for ${APP_NAME} ${ENV_NAME} RDS database" \
        --secret-string "$password" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --tags Key=Application,Value="$APP_NAME" Key=Environment,Value="$ENV_NAME" \
        > /dev/null
    
    log_info "Password stored in Secrets Manager: $secret_name"
    
    echo "$password"
}

# Gets VPC and subnets from Elastic Beanstalk environment
# Returns: VPC ID
get_eb_vpc_info() {
    local env_name=$1
    
    log_info "Getting VPC information from EB environment: $env_name"
    
    local vpc_id=$(aws elasticbeanstalk describe-configuration-settings \
        --application-name "$APP_NAME" \
        --environment-name "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "ConfigurationSettings[0].OptionSettings[?OptionName=='VPCId'].Value" \
        --output text)
    
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
        log_warn "VPC ID not found in EB configuration, querying from EC2 instance..."
        
        # Get instance ID from EB environment resources
        local instance_id=$(aws elasticbeanstalk describe-environment-resources \
            --environment-name "$env_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "EnvironmentResources.Instances[0].Id" \
            --output text)
        
        if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
            log_error "Could not determine VPC ID: No instances found in EB environment"
            exit 1
        fi
        
        # Get VPC ID from the EC2 instance
        vpc_id=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "Reservations[0].Instances[0].VpcId" \
            --output text)
        
        if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
            log_error "Could not determine VPC ID from EC2 instance"
            exit 1
        fi
        
        log_info "Retrieved VPC from EC2 instance: $vpc_id"
    else
        log_info "Found VPC from EB configuration: $vpc_id"
    fi
    
    echo "$vpc_id"
}

# Gets or retrieves EB security group ID
# Returns: Security group ID
get_eb_security_group() {
    local env_name=$1
    
    log_info "Getting security group from EB environment: $env_name"
    
    local sg_id=$(aws elasticbeanstalk describe-configuration-settings \
        --application-name "$APP_NAME" \
        --environment-name "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "ConfigurationSettings[0].OptionSettings[?OptionName=='SecurityGroups'].Value" \
        --output text)
    
    if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
        log_warn "Could not determine security group from EB environment, will use instance security group"
        
        # Try to get instance security group from launch configuration
        sg_id=$(aws elasticbeanstalk describe-configuration-settings \
            --application-name "$APP_NAME" \
            --environment-name "$env_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "ConfigurationSettings[0].OptionSettings[?Namespace=='aws:autoscaling:launchconfiguration' && OptionName=='SecurityGroups'].Value | [0]" \
            --output text)
    fi
    
    # Check if we got a security group name instead of ID (IDs start with "sg-")
    if [ -n "$sg_id" ] && [ "$sg_id" != "None" ] && [[ ! "$sg_id" =~ ^sg- ]]; then
        log_warn "Got security group name instead of ID: $sg_id"
        log_info "Retrieving security group ID from EC2 instance..."
        
        # Get instance ID from EB environment resources
        local instance_id=$(aws elasticbeanstalk describe-environment-resources \
            --environment-name "$env_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "EnvironmentResources.Instances[0].Id" \
            --output text)
        
        if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
            log_error "Could not determine security group ID: No instances found in EB environment"
            exit 1
        fi
        
        # Get security group ID from the EC2 instance
        sg_id=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
            --output text)
        
        if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
            log_error "Could not determine security group ID from EC2 instance"
            exit 1
        fi
        
        log_info "Retrieved security group ID from EC2 instance: $sg_id"
    else
        log_info "Found security group: $sg_id"
    fi
    
    echo "$sg_id"
}

# Creates or retrieves DB subnet group
# Idempotent: Checks if subnet group exists before creating
# Parameters:
#   $1 - subnet_group_name
#   $2 - vpc_id
# Returns: 0 on success
get_or_create_db_subnet_group() {
    local subnet_group_name=$1
    local vpc_id=$2
    
    log_info "Checking if DB subnet group exists: $subnet_group_name"
    
    # Check if subnet group already exists
    local existing_subnet_group=$(aws rds describe-db-subnet-groups \
        --db-subnet-group-name "$subnet_group_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "DBSubnetGroups[0].DBSubnetGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_subnet_group" ] && [ "$existing_subnet_group" != "None" ]; then
        log_info "DB subnet group already exists: $subnet_group_name"
        log_info "Skipping subnet group creation"
        return 0
    fi
    
    log_info "DB subnet group does not exist, creating..."
    
    # Get all subnets in the VPC
    log_info "Retrieving subnets from VPC: $vpc_id"
    
    local subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "Subnets[*].SubnetId" \
        --output text)
    
    if [ -z "$subnets" ]; then
        log_error "No subnets found in VPC: $vpc_id"
        exit 1
    fi
    
    local subnet_count=$(echo "$subnets" | wc -w)
    log_info "Found $subnet_count subnet(s) in VPC"
    
    # Create subnet group
    log_info "Creating DB subnet group: $subnet_group_name"
    
    aws rds create-db-subnet-group \
        --db-subnet-group-name "$subnet_group_name" \
        --db-subnet-group-description "Subnet group for ${APP_NAME} ${ENV_NAME} RDS database" \
        --subnet-ids $subnets \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --tags Key=Application,Value="$APP_NAME" Key=Environment,Value="$ENV_NAME" \
        > /dev/null
    
    log_info "DB subnet group created successfully"
}

# Creates or retrieves DB security group
# Idempotent: Checks if security group exists before creating
# Parameters:
#   $1 - security_group_name
#   $2 - vpc_id
#   $3 - eb_security_group_id
# Returns: Security group ID
get_or_create_db_security_group() {
    local sg_name=$1
    local vpc_id=$2
    local eb_sg_id=$3
    
    log_info "Checking if DB security group exists: $sg_name"
    
    # Check if security group already exists
    local existing_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$vpc_id" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_sg" ] && [ "$existing_sg" != "None" ]; then
        log_info "DB security group already exists: $existing_sg"
        
        # Check if ingress rule exists
        local existing_rule=$(aws ec2 describe-security-groups \
            --group-ids "$existing_sg" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\` && ToPort==\`5432\`].UserIdGroupPairs[?GroupId==\`$eb_sg_id\`]" \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$existing_rule" ]; then
            log_info "Adding ingress rule to allow access from EB security group..."
            
            aws ec2 authorize-security-group-ingress \
                --group-id "$existing_sg" \
                --protocol tcp \
                --port 5432 \
                --source-group "$eb_sg_id" \
                --profile "$AWS_PROFILE" \
                --region "$AWS_REGION" 2>/dev/null || log_warn "Ingress rule may already exist"
            
            log_info "Ingress rule added"
        else
            log_info "Ingress rule already configured correctly"
        fi
        
        echo "$existing_sg"
        return 0
    fi
    
    log_info "Creating DB security group: $sg_name"
    
    # Create security group
    local sg_id=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "Security group for ${APP_NAME} ${ENV_NAME} RDS database" \
        --vpc-id "$vpc_id" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "GroupId" \
        --output text)
    
    log_info "Security group created: $sg_id"
    
    # Add ingress rule for PostgreSQL from EB security group
    log_info "Adding ingress rule to allow PostgreSQL access from EB instances..."
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 5432 \
        --source-group "$eb_sg_id" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    
    log_info "Ingress rule added successfully"
    
    # Tag security group
    aws ec2 create-tags \
        --resources "$sg_id" \
        --tags Key=Application,Value="$APP_NAME" Key=Environment,Value="$ENV_NAME" Key=Name,Value="$sg_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    
    echo "$sg_id"
}

# Checks if DB instance exists and compares configuration
# Idempotent: Returns status of existing database
# Parameters:
#   $1 - db_instance_identifier
# Returns: EXISTS_MATCHES, EXISTS_DIFFERS, or NOT_EXISTS
check_existing_db_instance() {
    local db_identifier=$1
    
    log_info "Checking if DB instance exists: $db_identifier"
    
    # Check if instance exists
    local existing_db=$(aws rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "DBInstances[0]" \
        --output json 2>/dev/null || echo "")
    
    if [ -z "$existing_db" ] || [ "$existing_db" = "null" ]; then
        log_info "DB instance does not exist"
        echo "NOT_EXISTS"
        return 0
    fi
    
    log_info "DB instance already exists"
    
    # Compare key configuration parameters
    local existing_class=$(echo "$existing_db" | grep -o '"DBInstanceClass": *"[^"]*"' | cut -d'"' -f4)
    local existing_engine=$(echo "$existing_db" | grep -o '"Engine": *"[^"]*"' | cut -d'"' -f4)
    local existing_multi_az=$(echo "$existing_db" | grep -o '"MultiAZ": *[^,}]*' | awk '{print $2}' | tr -d ',')
    
    log_info "Existing configuration:"
    log_info "  Instance class: $existing_class"
    log_info "  Engine: $existing_engine"
    log_info "  Multi-AZ: $existing_multi_az"
    
    # Compare with desired configuration
    if [ "$existing_class" = "$DB_INSTANCE_CLASS" ] && \
       [ "$existing_engine" = "$DB_ENGINE" ] && \
       [ "$existing_multi_az" = "$DB_MULTI_AZ" ]; then
        log_info "DB instance configuration matches desired state"
        echo "EXISTS_MATCHES"
    else
        log_warn "DB instance configuration differs from desired state"
        echo "EXISTS_DIFFERS:$existing_class,$existing_engine,$existing_multi_az"
    fi
}

# Enables storage autoscaling on existing database instance
# Idempotent: Checks if autoscaling is already configured
# Parameters:
#   $1 - db_instance_identifier
# Returns: 0 on success
enable_storage_autoscaling_if_needed() {
    local db_identifier=$1
    
    if [ "${DB_STORAGE_AUTOSCALING_ENABLED:-true}" != "true" ]; then
        log_info "Storage autoscaling is disabled, skipping"
        return 0
    fi
    
    log_info "Checking storage autoscaling configuration..."
    
    local max_storage=$(aws rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "DBInstances[0].MaxAllocatedStorage" \
        --output text 2>/dev/null || echo "")
    
    local desired_max="${DB_MAX_ALLOCATED_STORAGE:-100}"
    
    if [ -z "$max_storage" ] || [ "$max_storage" = "None" ] || [ "$max_storage" = "null" ]; then
        log_info "Storage autoscaling not configured, enabling..."
        
        aws rds modify-db-instance \
            --db-instance-identifier "$db_identifier" \
            --max-allocated-storage "$desired_max" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --apply-immediately \
            > /dev/null
        
        log_info "Storage autoscaling enabled: max ${desired_max}GB"
    elif [ "$max_storage" != "$desired_max" ]; then
        log_warn "Storage autoscaling is configured but max differs: current=${max_storage}GB, desired=${desired_max}GB"
        log_info "Updating max allocated storage to ${desired_max}GB..."
        
        aws rds modify-db-instance \
            --db-instance-identifier "$db_identifier" \
            --max-allocated-storage "$desired_max" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --apply-immediately \
            > /dev/null
        
        log_info "Storage autoscaling updated"
    else
        log_info "Storage autoscaling already configured correctly: max ${max_storage}GB"
    fi
}

# Creates or updates DB instance
# Idempotent: Checks existing state before creating/updating
# Parameters:
#   $1 - db_instance_identifier
#   $2 - master_password
#   $3 - db_subnet_group_name
#   $4 - db_security_group_id
# Returns: 0 on success
create_or_update_db_instance() {
    local db_identifier=$1
    local master_password=$2
    local subnet_group=$3
    local security_group=$4
    
    local status=$(check_existing_db_instance "$db_identifier")
    
    if [[ $status == "EXISTS_MATCHES" ]]; then
        log_info "DB instance already exists and is correctly configured"
        log_info "Skipping DB instance creation"
        enable_storage_autoscaling_if_needed "$db_identifier"
        return 0
    elif [[ $status == EXISTS_DIFFERS:* ]]; then
        log_warn "DB instance exists but configuration differs"
        log_warn "Manual updates may be required for:"
        log_warn "  - Instance class changes (requires downtime)"
        log_warn "  - Multi-AZ enablement (can be done online)"
        log_info "Continuing with existing instance..."
        enable_storage_autoscaling_if_needed "$db_identifier"
        return 0
    fi
    
    log_info "Creating RDS database instance: $db_identifier"
    log_info "Configuration:"
    log_info "  Engine: $DB_ENGINE $DB_ENGINE_VERSION"
    log_info "  Instance class: $DB_INSTANCE_CLASS"
    log_info "  Storage: ${DB_ALLOCATED_STORAGE}GB ($DB_STORAGE_TYPE)"
    log_info "  Multi-AZ: $DB_MULTI_AZ"
    log_info "  Backup retention: $DB_BACKUP_RETENTION_DAYS days"
    log_info "  Encrypted: $DB_STORAGE_ENCRYPTED"
    
    if [ "${DB_STORAGE_AUTOSCALING_ENABLED:-true}" = "true" ]; then
        log_info "  Storage autoscaling: enabled (max: ${DB_MAX_ALLOCATED_STORAGE:-100}GB)"
    else
        log_info "  Storage autoscaling: disabled"
    fi
    
    # Build create-db-instance command
    local create_cmd="aws rds create-db-instance \
        --db-instance-identifier \"$db_identifier\" \
        --db-instance-class \"$DB_INSTANCE_CLASS\" \
        --engine \"$DB_ENGINE\" \
        --engine-version \"$DB_ENGINE_VERSION\" \
        --master-username \"$DB_USERNAME\" \
        --master-user-password \"$master_password\" \
        --allocated-storage \"$DB_ALLOCATED_STORAGE\" \
        --storage-type \"$DB_STORAGE_TYPE\" \
        --db-name \"$DB_NAME\" \
        --db-subnet-group-name \"$subnet_group\" \
        --vpc-security-group-ids \"$security_group\" \
        --multi-az \
        --backup-retention-period \"$DB_BACKUP_RETENTION_DAYS\" \
        --preferred-backup-window \"$DB_BACKUP_WINDOW\" \
        --preferred-maintenance-window \"$DB_MAINTENANCE_WINDOW\" \
        --storage-encrypted \
        --publicly-accessible \
        --enable-cloudwatch-logs-exports postgresql upgrade"
    
    if [ "${DB_STORAGE_AUTOSCALING_ENABLED:-true}" = "true" ]; then
        create_cmd="$create_cmd --max-allocated-storage \"${DB_MAX_ALLOCATED_STORAGE:-100}\""
    fi
    
    create_cmd="$create_cmd \
        --tags Key=Application,Value=\"$APP_NAME\" Key=Environment,Value=\"$ENV_NAME\" Key=Name,Value=\"$db_identifier\" \
        --profile \"$AWS_PROFILE\" \
        --region \"$AWS_REGION\""
    
    eval "$create_cmd > /dev/null"
    
    log_info "DB instance creation initiated"
    log_info "Waiting for DB instance to become available (this may take 5-10 minutes)..."
    
    # Wait for instance to be available
    aws rds wait db-instance-available \
        --db-instance-identifier "$db_identifier" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    
    log_info "DB instance is now available"
}

# Creates or updates read replicas for the database instance
# Idempotent: Checks if read replicas exist before creating
# Parameters:
#   $1 - db_instance_identifier (primary)
# Returns: 0 on success
create_or_update_read_replicas() {
    local primary_db_identifier=$1
    
    if [ "${DB_READ_REPLICA_ENABLED:-false}" != "true" ]; then
        log_info "Read replicas are disabled, skipping"
        return 0
    fi
    
    local replica_count="${DB_READ_REPLICA_COUNT:-1}"
    log_info "Checking read replica configuration (target: $replica_count replica(s))..."
    
    local existing_replicas=$(aws rds describe-db-instances \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "DBInstances[?ReadReplicaSourceDBInstanceIdentifier=='$primary_db_identifier'].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    local existing_count=0
    if [ -n "$existing_replicas" ] && [ "$existing_replicas" != "None" ]; then
        existing_count=$(echo "$existing_replicas" | wc -w)
    fi
    
    log_info "Found $existing_count existing read replica(s)"
    
    if [ "$existing_count" -ge "$replica_count" ]; then
        log_info "Read replica count meets or exceeds target, skipping creation"
        return 0
    fi
    
    local replicas_to_create=$((replica_count - existing_count))
    log_info "Creating $replicas_to_create additional read replica(s)..."
    
    for i in $(seq 1 "$replicas_to_create"); do
        local replica_number=$((existing_count + i))
        local replica_identifier="${primary_db_identifier}-replica-${replica_number}"
        
        log_info "Creating read replica: $replica_identifier"
        
        aws rds create-db-instance-read-replica \
            --db-instance-identifier "$replica_identifier" \
            --source-db-instance-identifier "$primary_db_identifier" \
            --db-instance-class "$DB_INSTANCE_CLASS" \
            --publicly-accessible \
            --tags Key=Application,Value="$APP_NAME" Key=Environment,Value="$ENV_NAME" Key=Name,Value="$replica_identifier" Key=Type,Value="ReadReplica" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            > /dev/null
        
        log_info "Read replica creation initiated: $replica_identifier"
    done
    
    log_info "Waiting for read replicas to become available..."
    
    for i in $(seq 1 "$replicas_to_create"); do
        local replica_number=$((existing_count + i))
        local replica_identifier="${primary_db_identifier}-replica-${replica_number}"
        
        aws rds wait db-instance-available \
            --db-instance-identifier "$replica_identifier" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION"
        
        log_info "Read replica available: $replica_identifier"
    done
    
    log_info "All read replicas are now available"
}

# Configures autoscaling for read replicas
# Idempotent: Checks if autoscaling is already configured
# Parameters:
#   $1 - db_instance_identifier (primary)
# Returns: 0 on success
configure_read_replica_autoscaling() {
    local primary_db_identifier=$1
    
    if [ "${DB_READ_REPLICA_ENABLED:-false}" != "true" ]; then
        log_info "Read replicas are disabled, skipping autoscaling configuration"
        return 0
    fi
    
    log_info "Configuring autoscaling for read replicas..."
    
    local min_capacity="${DB_READ_REPLICA_MIN_CAPACITY:-1}"
    local max_capacity="${DB_READ_REPLICA_MAX_CAPACITY:-3}"
    local target_cpu="${DB_READ_REPLICA_TARGET_CPU:-70}"
    local scale_in_cooldown="${DB_READ_REPLICA_SCALE_IN_COOLDOWN:-300}"
    local scale_out_cooldown="${DB_READ_REPLICA_SCALE_OUT_COOLDOWN:-60}"
    
    local resource_id="db:${primary_db_identifier}"
    local policy_name="${primary_db_identifier}-cpu-autoscaling"
    
    log_info "Autoscaling configuration:"
    log_info "  Min replicas: $min_capacity"
    log_info "  Max replicas: $max_capacity"
    log_info "  Target CPU: ${target_cpu}%"
    log_info "  Scale-in cooldown: ${scale_in_cooldown}s"
    log_info "  Scale-out cooldown: ${scale_out_cooldown}s"
    
    log_info "Registering scalable target..."
    
    aws application-autoscaling register-scalable-target \
        --service-namespace rds \
        --resource-id "$resource_id" \
        --scalable-dimension rds:replica:ReadReplicaCount \
        --min-capacity "$min_capacity" \
        --max-capacity "$max_capacity" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        2>/dev/null || log_warn "Scalable target may already be registered"
    
    log_info "Creating target tracking scaling policy..."
    
    cat > /tmp/scaling-policy-config.json <<EOF
{
    "TargetValue": ${target_cpu}.0,
    "PredefinedMetricSpecification": {
        "PredefinedMetricType": "RDSReaderAverageCPUUtilization"
    },
    "ScaleInCooldown": ${scale_in_cooldown},
    "ScaleOutCooldown": ${scale_out_cooldown}
}
EOF
    
    aws application-autoscaling put-scaling-policy \
        --service-namespace rds \
        --resource-id "$resource_id" \
        --scalable-dimension rds:replica:ReadReplicaCount \
        --policy-name "$policy_name" \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration file:///tmp/scaling-policy-config.json \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        > /dev/null
    
    rm -f /tmp/scaling-policy-config.json
    
    log_info "Read replica autoscaling configured successfully"
}

# Updates EB environment with database connection details
# Idempotent: Uses update-environment which handles existing values
# Parameters:
#   $1 - db_instance_identifier
#   $2 - master_password
# Returns: 0 on success
update_eb_environment_variables() {
    local db_identifier=$1
    local master_password=$2
    local env_name="$ENV_NAME"
    
    log_info "Getting database endpoint..."
    
    # Get database endpoint
    local db_endpoint=$(aws rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "DBInstances[0].Endpoint.Address" \
        --output text)
    
    local db_port=$(aws rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "DBInstances[0].Endpoint.Port" \
        --output text)
    
    if [ -z "$db_endpoint" ] || [ "$db_endpoint" = "None" ]; then
        log_error "Could not retrieve database endpoint"
        exit 1
    fi
    
    log_info "Database endpoint: $db_endpoint:$db_port"
    
    # Construct DATABASE_URL
    local database_url="postgresql://${DB_USERNAME}:${master_password}@${db_endpoint}:${db_port}/${DB_NAME}"
    
    log_info "Updating Elastic Beanstalk environment variables..."
    
    # Create option settings JSON
    cat > /tmp/db-env-options.json <<EOF
[
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DATABASE_URL",
        "Value": "${database_url}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_HOST",
        "Value": "${db_endpoint}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_PORT",
        "Value": "${db_port}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_NAME",
        "Value": "${DB_NAME}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_USERNAME",
        "Value": "${DB_USERNAME}"
    },
    {
        "Namespace": "aws:elasticbeanstalk:application:environment",
        "OptionName": "DB_PASSWORD",
        "Value": "${master_password}"
    }
]
EOF
    
    # Update environment
    log_info "Initiating environment update with database variables..."
    aws elasticbeanstalk update-environment \
        --application-name "$APP_NAME" \
        --environment-name "$env_name" \
        --option-settings file:///tmp/db-env-options.json \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"

    log_info "Waiting for environment update to complete (this may take a few minutes)..."
    aws elasticbeanstalk wait environment-updated \
        --application-name "$APP_NAME" \
        --environment-names "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"

    log_info "Environment variables updated successfully"
    log_info "Database connection details:"
    log_info "  Host: $db_endpoint"
    log_info "  Port: $db_port"
    log_info "  Database: $DB_NAME"
    log_info "  Username: $DB_USERNAME"
    
    # Clean up temp file
    rm -f /tmp/db-env-options.json
}

# Main function to orchestrate RDS setup
# Idempotent: All sub-functions follow check-before-create pattern
main() {
    log_info "Starting RDS database setup..."

    local db_identifier="${APP_NAME}-${ENV_NAME}-db"
    local env_name="$ENV_NAME"
    local subnet_group_name="${APP_NAME}-${ENV_NAME}-db-subnet-group"
    local security_group_name="${APP_NAME}-${ENV_NAME}-db-sg"
    
    # Validate autoscaling configuration
    validate_autoscaling_config
    
    # Verify EB environment exists
    log_info "Verifying Elastic Beanstalk environment exists..."
    
    local eb_env_exists=$(aws elasticbeanstalk describe-environments \
        --environment-names "$env_name" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "Environments[?Status!='Terminated']" \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$eb_env_exists" = "[]" ] || [ -z "$eb_env_exists" ]; then
        log_error "Elastic Beanstalk environment does not exist: $env_name"
        log_error "Database setup must run after EB environment creation"
        exit 1
    fi
    
    log_info "EB environment found: $env_name"
    
    # Get VPC and security group information
    local vpc_id=$(get_eb_vpc_info "$env_name")
    local eb_sg_id=$(get_eb_security_group "$env_name")
    
    # Generate or retrieve database password
    local master_password=$(generate_db_password)
    
    # Create subnet group
    get_or_create_db_subnet_group "$subnet_group_name" "$vpc_id"
    
    # Create security group
    local db_sg_id=$(get_or_create_db_security_group "$security_group_name" "$vpc_id" "$eb_sg_id")
    
    # Create or verify DB instance
    create_or_update_db_instance "$db_identifier" "$master_password" "$subnet_group_name" "$db_sg_id"
    
    # Create read replicas if enabled
    create_or_update_read_replicas "$db_identifier"
    
    # Configure autoscaling for read replicas
    configure_read_replica_autoscaling "$db_identifier"
    
    # Update EB environment variables
    update_eb_environment_variables "$db_identifier" "$master_password"
    
    log_info "RDS database setup completed successfully!"
    log_info ""
    log_info "Database Details:"
    log_info "  Instance ID: $db_identifier"
    log_info "  Subnet Group: $subnet_group_name"
    log_info "  Security Group: $db_sg_id"
    
    if [ "${DB_STORAGE_AUTOSCALING_ENABLED:-true}" = "true" ]; then
        log_info "  Storage Autoscaling: Enabled (max: ${DB_MAX_ALLOCATED_STORAGE:-100}GB)"
    else
        log_info "  Storage Autoscaling: Disabled"
    fi
    
    if [ "${DB_READ_REPLICA_ENABLED:-false}" = "true" ]; then
        local replica_count=$(aws rds describe-db-instances \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "DBInstances[?ReadReplicaSourceDBInstanceIdentifier=='$db_identifier'].DBInstanceIdentifier" \
            --output text 2>/dev/null | wc -w)
        log_info "  Read Replicas: $replica_count (autoscaling: ${DB_READ_REPLICA_MIN_CAPACITY:-1}-${DB_READ_REPLICA_MAX_CAPACITY:-3})"
    else
        log_info "  Read Replicas: Disabled"
    fi
    
    log_info ""
    log_info "Next steps:"
    log_info "  1. Deploy your application to Elastic Beanstalk"
    log_info "  2. Run database migrations from your application"
    log_info "  3. Test database connectivity"
    
    if [ "${DB_READ_REPLICA_ENABLED:-false}" = "true" ]; then
        log_info "  4. Configure your application to use read replicas for read-heavy operations"
        log_info "  5. Monitor CPU utilization to verify autoscaling triggers"
    fi
}

# Only run main if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

