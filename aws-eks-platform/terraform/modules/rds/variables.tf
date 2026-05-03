variable "identifier" {
  description = "Resource name prefix for the RDS cluster"
  type        = string
}

variable "kms_key_arn" {
  description = <<-EOT
    ARN of the customer-managed KMS key used to encrypt the Secrets Manager secret.
    This should be the same KMS key used for EKS secrets and EBS volumes to centralise
    key management. Pass module.eks.kms_key_arn from the environment root.
  EOT
  type        = string
}

variable "secret_rotation_days" {
  description = "Number of days between automatic Secrets Manager password rotations."
  type        = number
  default     = 30

  validation {
    condition     = var.secret_rotation_days >= 1 && var.secret_rotation_days <= 365
    error_message = "secret_rotation_days must be between 1 and 365."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "Instance class for RDS cluster instances"
  type        = string
  default     = "db.r7g.large"
}

variable "instances" {
  description = "Number of RDS cluster instances"
  type        = number
  default     = 2
}

variable "vpc_id" {
  description = "VPC ID where the database will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the RDS subnet group"
  type        = list(string)
}

variable "allowed_sg_ids" {
  description = "Security groups allowed to reach the database"
  type        = list(string)
  default     = []
}

variable "database_name" {
  description = "Database name to create in the Aurora cluster"
  type        = string
}

variable "master_username" {
  description = "Master username for the database"
  type        = string
  default     = "admin"
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for the database cluster"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "How many days to retain automated backups"
  type        = number
  default     = 14
}

variable "preferred_backup_window" {
  description = "Preferred daily backup window in UTC"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Preferred weekly maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "CloudWatch monitoring interval in seconds"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
