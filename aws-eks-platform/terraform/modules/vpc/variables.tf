variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 3
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (used for subnet tagging)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting CloudWatch logs"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
