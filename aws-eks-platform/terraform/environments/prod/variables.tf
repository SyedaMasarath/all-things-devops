variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region, e.g. 'us-east-1', 'eu-west-2'."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDRs allowed to access the EKS public API endpoint. Restrict to your office/VPN IPs in production."
  type        = list(string)
  # Restrict to your office/VPN IPs in production
  default     = ["10.0.0.0/8"]

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0 && !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "allowed_cidr_blocks must not contain 0.0.0.0/0. Restrict to your VPN or office CIDR."
  }
}

variable "ecr_repositories" {
  description = "List of ECR repository names to create (one aws_ecr_repository per entry)"
  type        = list(string)
  default     = [
    "api-service",
    "frontend"
  ]

  validation {
    condition     = length(var.ecr_repositories) > 0
    error_message = "ecr_repositories must contain at least one repository name."
  }

  validation {
    condition     = alltrue([for r in var.ecr_repositories : can(regex("^[a-z0-9][a-z0-9/_.-]*$", r))])
    error_message = "Each ECR repository name must be lowercase alphanumeric and may contain '/', '_', '.', '-'."
  }
}
