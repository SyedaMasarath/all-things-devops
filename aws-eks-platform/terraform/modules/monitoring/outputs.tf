output "service_account_name" {
  description = "Name of the Cluster Autoscaler service account"
  value       = kubernetes_service_account.autoscaler.metadata[0].name
}

output "service_account_namespace" {
  description = "Namespace of the Cluster Autoscaler service account"
  value       = kubernetes_service_account.autoscaler.metadata[0].namespace
}

output "role_arn" {
  description = "IAM role ARN assigned to the Cluster Autoscaler service account"
  value       = aws_iam_role.autoscaler.arn
}
