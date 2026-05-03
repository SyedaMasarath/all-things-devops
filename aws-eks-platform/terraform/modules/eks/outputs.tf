output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.this.id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  description = "EKS cluster certificate authority"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "EKS node security group ID"
  value       = aws_security_group.nodes.id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "IAM OIDC provider URL"
  value       = aws_iam_openid_connect_provider.eks.url
}

output "node_group_role_arn" {
  description = "Node group IAM role ARN"
  value       = aws_iam_role.node_group.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for EKS secrets encryption"
  value       = aws_kms_key.eks.arn
}
