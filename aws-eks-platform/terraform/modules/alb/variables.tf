variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for the EKS cluster"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL for the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name for AWS Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
  default     = "kube-system"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
