output "db_cluster_endpoint" {
  description = "Primary endpoint for the Aurora cluster"
  value       = aws_rds_cluster.this.endpoint
}

output "db_reader_endpoint" {
  description = "Reader endpoint for the Aurora cluster"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "db_name" {
  description = "Database name"
  value       = aws_rds_cluster.this.database_name
}

output "db_security_group_id" {
  description = "Security group ID for the database cluster"
  value       = aws_security_group.this.id
}

output "db_credentials_secret_arn" {
  description = "Secrets Manager ARN for database credentials"
  value       = aws_secretsmanager_secret.credentials.arn
}

output "db_kms_key_id" {
  description = "KMS key ID used to encrypt the database"
  value       = aws_rds_cluster.this.kms_key_id
}
