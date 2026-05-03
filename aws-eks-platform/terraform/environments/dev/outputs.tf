################################################################################
# Development Environment Outputs
# Run `terraform output` after apply to retrieve these values.
################################################################################

################################################################################
# EKS
################################################################################

output "cluster_id" {
  description = "EKS cluster name / ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "kubeconfig_command" {
  description = "Run this command to update your local kubeconfig for the dev cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name} --alias dev"
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — used when creating new IRSA roles"
  value       = module.eks.oidc_provider_arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for EKS secrets, EBS volumes, and ECR encryption"
  value       = module.eks.kms_key_arn
}

################################################################################
# Networking
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes)"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB, NAT Gateways)"
  value       = module.vpc.public_subnet_ids
}

output "intra_subnet_ids" {
  description = "Intra subnet IDs (RDS — no internet access)"
  value       = module.vpc.intra_subnet_ids
}

################################################################################
# Database
################################################################################

output "db_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = module.rds.db_cluster_endpoint
}

output "db_credentials_secret_arn" {
  description = "Secrets Manager ARN containing DB credentials"
  value       = module.rds.db_credentials_secret_arn
  sensitive   = true
}

################################################################################
# ECR
################################################################################

output "ecr_repository_urls" {
  description = "Map of ECR repository names to their full URLs"
  value       = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

################################################################################
# AWS Account
################################################################################

output "aws_account_id" {
  description = "AWS account ID this environment is deployed to"
  value       = data.aws_caller_identity.current.account_id
}
