# Database Setup Guide

Comprehensive guide for managing your PostgreSQL RDS database in the Elastic Beanstalk environment.

## Overview

The automation creates a PostgreSQL RDS database instance with production-ready defaults:

- Multi-AZ deployment for high availability
- Automated backups with configurable retention
- Encryption at rest and in transit
- Private access via VPC security groups
- Secure password management via AWS Secrets Manager

## Table of Contents

- [Configuration Options](#configuration-options)
- [Security](#security)
- [Backup and Recovery](#backup-and-recovery)
- [Scaling and Performance](#scaling-and-performance)
- [Connection Pooling](#connection-pooling)
- [Migrations](#migrations)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## Configuration Options

### Instance Classes

Choose an instance class based on your workload:

**Development/Testing:**
- `db.t3.micro` - 2 vCPU, 1 GB RAM (Free tier eligible)
- `db.t3.small` - 2 vCPU, 2 GB RAM
- `db.t4g.micro` - 2 vCPU (ARM), 1 GB RAM (cheaper)

**Production:**
- `db.t3.medium` - 2 vCPU, 4 GB RAM
- `db.m5.large` - 2 vCPU, 8 GB RAM
- `db.m5.xlarge` - 4 vCPU, 16 GB RAM
- `db.r5.large` - 2 vCPU, 16 GB RAM (memory-optimized)

**High Performance:**
- `db.m5.2xlarge` - 8 vCPU, 32 GB RAM
- `db.r5.2xlarge` - 8 vCPU, 64 GB RAM

### Storage Types

**gp3 (General Purpose SSD v3)** - Recommended
- 3,000 IOPS baseline
- 125 MB/s throughput baseline
- Cost-effective for most workloads

**gp2 (General Purpose SSD v2)**
- 3 IOPS per GB (max 16,000)
- Good for variable workloads
- Older generation

**io1/io2 (Provisioned IOPS)**
- For I/O-intensive workloads
- Configurable IOPS (up to 64,000)
- Higher cost

### Database Engines

Currently supported:
- PostgreSQL (recommended)
- MySQL
- MariaDB

To use a different engine, update `DB_ENGINE` in `config.env`:

```bash
DB_ENGINE="mysql"
DB_ENGINE_VERSION="8.0.35"
```

## Security

### Network Security

The database is created with these security defaults:

1. **Private Subnet**: Not publicly accessible
2. **VPC Isolation**: Same VPC as EB environment
3. **Security Group**: Only allows connections from EB instances
4. **Port**: PostgreSQL standard port 5432

### Password Management

**Option 1: Auto-generated (Recommended)**

Leave `DB_MASTER_PASSWORD` empty:

```bash
DB_MASTER_PASSWORD=""
```

The script will:
1. Generate a secure 32-character password
2. Store it in AWS Secrets Manager
3. Configure it in your EB environment

**Option 2: Manual Password**

Set a password in `config.env`:

```bash
DB_MASTER_PASSWORD="YourSecurePassword123!"
```

Password requirements:
- 8-128 characters
- Cannot contain: `/`, `"`, `@`
- Should include: uppercase, lowercase, numbers, symbols

### Encryption

**At Rest:**
- Enabled by default via `DB_STORAGE_ENCRYPTED="true"`
- Uses AWS KMS for key management
- Applied to database, backups, and read replicas

**In Transit:**
- All connections use SSL/TLS
- Enforced automatically by RDS

### IAM Access

Your EB instances have IAM permissions to:
- Retrieve database password from Secrets Manager
- Connect to the database via security group rules

## Backup and Recovery

### Automated Backups

Configured via `config.env`:

```bash
DB_BACKUP_RETENTION_DAYS="7"         # 0-35 days (0 = disabled)
DB_BACKUP_WINDOW="03:00-04:00"       # Daily backup window (UTC)
```

Backups include:
- Full daily snapshot
- Transaction logs for point-in-time recovery
- Stored in S3 (managed by AWS)

### Manual Snapshots

Create a manual snapshot:

```bash
aws rds create-db-snapshot \
  --db-instance-identifier my-app-prod-db \
  --db-snapshot-identifier my-app-prod-manual-backup-$(date +%Y%m%d) \
  --profile default \
  --region us-east-1
```

### Point-in-Time Recovery

Restore to any point within the retention period:

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier my-app-prod-db \
  --target-db-instance-identifier my-app-prod-db-restored \
  --restore-time "2024-01-15T12:00:00Z" \
  --profile default \
  --region us-east-1
```

### Disaster Recovery

1. **Create snapshot**
2. **Copy to another region** (optional)
3. **Restore from snapshot when needed**

```bash
# Copy snapshot to another region
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier arn:aws:rds:us-east-1:123456789012:snapshot:my-snapshot \
  --target-db-snapshot-identifier my-snapshot-dr \
  --source-region us-east-1 \
  --region us-west-2 \
  --profile default
```

## Scaling and Performance

### Vertical Scaling (Instance Size)

**Change instance class** (requires downtime):

```bash
aws rds modify-db-instance \
  --db-instance-identifier my-app-prod-db \
  --db-instance-class db.m5.large \
  --apply-immediately \
  --profile default \
  --region us-east-1
```

**Note**: Set `--apply-immediately` to scale now, or omit it to scale during next maintenance window.

### Storage Scaling

**Increase storage** (no downtime):

```bash
aws rds modify-db-instance \
  --db-instance-identifier my-app-prod-db \
  --allocated-storage 50 \
  --apply-immediately \
  --profile default \
  --region us-east-1
```

**Note**: You can only increase storage, never decrease it.

### Read Replicas

For read-heavy workloads, create read replicas:

```bash
aws rds create-db-instance-read-replica \
  --db-instance-identifier my-app-prod-db-replica \
  --source-db-instance-identifier my-app-prod-db \
  --db-instance-class db.t3.small \
  --availability-zone us-east-1b \
  --profile default \
  --region us-east-1
```

Configure your application to:
- Write to primary instance
- Read from replica(s)
- Handle replication lag

### Performance Insights

Enable Performance Insights for detailed monitoring:

```bash
aws rds modify-db-instance \
  --db-instance-identifier my-app-prod-db \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --apply-immediately \
  --profile default \
  --region us-east-1
```

## Connection Pooling

PostgreSQL has limited connections (~100-300 depending on instance class). Use connection pooling to handle more concurrent requests.

### Using PgBouncer

**In your application** (recommended for Dockerized apps):

```dockerfile
# Dockerfile
FROM python:3.11-slim

# Install PgBouncer
RUN apt-get update && apt-get install -y pgbouncer

# Copy PgBouncer config
COPY pgbouncer.ini /etc/pgbouncer/pgbouncer.ini

# Start both PgBouncer and your app
CMD pgbouncer -d /etc/pgbouncer/pgbouncer.ini && python app.py
```

**PgBouncer config** (`pgbouncer.ini`):

```ini
[databases]
mydb = host=$DB_HOST port=$DB_PORT dbname=$DB_NAME

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

### Using RDS Proxy

For managed connection pooling (recommended for production):

```bash
aws rds create-db-proxy \
  --db-proxy-name my-app-prod-db-proxy \
  --engine-family POSTGRESQL \
  --auth SecretArn=arn:aws:secretsmanager:us-east-1:123456789012:secret:my-app/prod/db-password-ABCDEF \
  --role-arn arn:aws:iam::123456789012:role/rds-proxy-role \
  --vpc-subnet-ids subnet-12345678 subnet-87654321 \
  --profile default \
  --region us-east-1
```

## Migrations

### Using Django

```bash
# Connect to your database
export DATABASE_URL="postgresql://user:pass@host:5432/dbname"

# Run migrations
python manage.py migrate
```

### Using Alembic (Python)

```bash
# Initialize Alembic
alembic init alembic

# Create migration
alembic revision --autogenerate -m "Initial schema"

# Apply migration
alembic upgrade head
```

### Using Flyway (Java)

```bash
# Install Flyway
wget -qO- https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/9.16.0/flyway-commandline-9.16.0-linux-x64.tar.gz | tar xvz

# Configure connection
flyway -url="jdbc:postgresql://host:5432/dbname" \
       -user="username" \
       -password="password" \
       migrate
```

### Using Liquibase

```bash
liquibase \
  --driver=org.postgresql.Driver \
  --url="jdbc:postgresql://host:5432/dbname" \
  --username="username" \
  --password="password" \
  update
```

## Monitoring

### CloudWatch Metrics

Key metrics to monitor:

- **CPUUtilization**: Keep below 80%
- **DatabaseConnections**: Monitor connection pool exhaustion
- **FreeableMemory**: Ensure sufficient RAM
- **ReadLatency/WriteLatency**: Check disk performance
- **FreeStorageSpace**: Monitor storage usage

### CloudWatch Alarms

Create alarms for critical metrics:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name my-app-prod-db-high-cpu \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=my-app-prod-db \
  --profile default \
  --region us-east-1
```

### Slow Query Log

Enable slow query logging:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name default.postgres16 \
  --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate" \
  --profile default \
  --region us-east-1
```

View logs in CloudWatch Logs:
- Log group: `/aws/rds/instance/my-app-prod-db/postgresql`

## Troubleshooting

### Cannot Connect to Database

**Check security group rules:**

```bash
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --profile default \
  --region us-east-1
```

Verify:
- Inbound rule allows PostgreSQL (5432) from EB security group
- EB instances are in the same VPC

**Check database status:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-app-prod-db \
  --query "DBInstances[0].DBInstanceStatus" \
  --profile default \
  --region us-east-1
```

Should return `"available"`.

### Too Many Connections

**Check current connections:**

```sql
SELECT count(*) FROM pg_stat_activity;
```

**Solutions:**
1. Increase `max_connections` parameter (requires reboot)
2. Implement connection pooling (PgBouncer or RDS Proxy)
3. Scale up to larger instance class

### Slow Queries

**Find slow queries:**

```sql
SELECT
  pid,
  now() - pg_stat_activity.query_start AS duration,
  query,
  state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds'
ORDER BY duration DESC;
```

**Solutions:**
1. Add indexes
2. Optimize queries
3. Scale up instance class
4. Enable query caching

### Storage Full

**Check storage:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-app-prod-db \
  --query "DBInstances[0].AllocatedStorage" \
  --profile default \
  --region us-east-1
```

**Solution:** Increase allocated storage (see [Storage Scaling](#storage-scaling))

### High CPU Usage

**Identify CPU-intensive queries:**

```sql
SELECT
  query,
  calls,
  total_time,
  mean_time,
  max_time
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;
```

**Solutions:**
1. Optimize queries
2. Add indexes
3. Scale up instance class
4. Consider read replicas for read-heavy workloads

## Best Practices

1. **Always enable Multi-AZ** for production
2. **Use automated backups** with 7-30 day retention
3. **Enable encryption** at rest and in transit
4. **Use connection pooling** to manage connections efficiently
5. **Monitor CloudWatch metrics** and set up alarms
6. **Regular performance reviews** using Performance Insights
7. **Test disaster recovery** procedures periodically
8. **Keep database engine updated** to latest minor version
9. **Use parameter groups** for custom configuration
10. **Document your schema** and migration procedures

## Additional Resources

- [Amazon RDS User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [Database Performance Tuning](https://aws.amazon.com/blogs/database/category/database/amazon-rds/)

