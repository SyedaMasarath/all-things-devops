################################################################################
# Random password — stored only in Secrets Manager, never in plain state
# Note: the value will still appear in tfstate (which is S3/KMS encrypted),
# but the Secrets Manager secret itself is encrypted with a customer KMS key.
################################################################################
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!@"
}

################################################################################
# Enhanced Monitoring IAM Role
# Required when monitoring_interval > 0 on RDS cluster instances
################################################################################
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.identifier}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.identifier}-rds-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-db-sg"
  description = "Database security group for ${var.identifier}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_sg_ids
    content {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      security_group_id        = ingress.value
      description              = "Allow database access from application security group"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.identifier}-db-sg"
  })
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.identifier}-db-subnet-group"
  })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier      = var.identifier
  engine                  = "aurora-postgresql"
  engine_version          = var.engine_version
  master_username         = var.master_username
  master_password         = random_password.db_password.result
  database_name           = var.database_name
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.this.id]
  storage_encrypted       = true
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  performance_insights_enabled = var.performance_insights_enabled
  monitoring_interval          = var.monitoring_interval
  deletion_protection      = var.deletion_protection
  skip_final_snapshot      = false
  final_snapshot_identifier = "${var.identifier}-final-snapshot"

  tags = merge(var.tags, {
    Name = "${var.identifier}-rds-cluster"
  })
}

resource "aws_rds_cluster_instance" "this" {
  count                = var.instances
  identifier           = "${var.identifier}-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = var.instance_class
  engine               = aws_rds_cluster.this.engine
  engine_version       = aws_rds_cluster.this.engine_version
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.this.name
  apply_immediately    = false

  # Enhanced Monitoring — requires the IAM role created above
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = merge(var.tags, {
    Name = "${var.identifier}-rds-instance-${count.index + 1}"
  })

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}

################################################################################
# Secrets Manager — encrypted with customer KMS key, automatic rotation
################################################################################
resource "aws_secretsmanager_secret" "credentials" {
  name        = "${var.identifier}-db-credentials"
  description = "Database credentials for ${var.identifier}"

  # Encrypt with a customer-managed KMS key (not the default AWS-managed key)
  kms_key_id = var.kms_key_arn

  # Ensure the secret is not immediately deletable (7-day recovery window)
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.identifier}-db-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "credentials" {
  secret_id     = aws_secretsmanager_secret.credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.db_password.result
    host     = aws_rds_cluster.this.endpoint
    port     = aws_rds_cluster.this.port
    database = var.database_name
    # engine field is used by the AWS-managed rotation Lambda
    engine   = "aurora-postgresql"
  })

  # Ensure the cluster exists before writing credentials
  depends_on = [aws_rds_cluster.this]
}

# Automatic rotation using the AWS-managed single-user rotation Lambda.
# This rotates the master password in both Secrets Manager and the Aurora cluster.
# For multi-user rotation (separate rotation user), set use_managed_rotation = false
# and supply your own rotation Lambda ARN.
resource "aws_secretsmanager_secret_rotation" "credentials" {
  secret_id = aws_secretsmanager_secret.credentials.id

  rotation_rules {
    # Rotate every 30 days
    automatically_after_days = var.secret_rotation_days
  }

  # AWS-managed rotation Lambda — no custom Lambda needed for single-user rotation
  managed_rotation {
    enabled = true
  }
}
