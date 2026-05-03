output "service_account_name" {
  description = "Name of the Kubernetes service account created for the ALB controller"
  value       = kubernetes_service_account.alb.metadata[0].name
}

output "service_account_namespace" {
  description = "Namespace of the service account created for the ALB controller"
  value       = kubernetes_service_account.alb.metadata[0].namespace
}

output "role_arn" {
  description = "IAM role ARN assigned to the ALB controller service account"
  value       = aws_iam_role.alb.arn
}
