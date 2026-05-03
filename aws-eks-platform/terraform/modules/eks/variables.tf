################################################################################
# EKS Module Variables
################################################################################

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster (e.g. '1.29')"
  type        = string
  default     = "1.29"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in 'MAJOR.MINOR' format, e.g. '1.29'. Do not include a patch version."
  }
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for node groups"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Enable public access to the EKS API server"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the EKS public API endpoint.
    Restrict this to known, trusted ranges only — never leave as 0.0.0.0/0 in production.

    Examples:
      - Corporate VPN egress:   "10.8.0.0/16"
      - Office static IP:       "203.0.113.50/32"   (replace with your real IP)
      - GitHub Actions (OIDC):  not needed — OIDC auth is token-based, not IP-based
      - CI runner NAT IP:       add if using self-hosted runners with a fixed egress IP

    Tip: run `curl -s ifconfig.me` from your workstation or VPN to get the IP to allowlist.
  EOT
  type        = list(string)

  # Placeholder — replace with your VPN/office CIDR before applying to production.
  # Example: ["10.8.0.0/16", "203.0.113.50/32"]
  default = ["10.8.0.0/16"]

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "public_access_cidrs must not contain 0.0.0.0/0. Restrict to your VPN or office CIDR."
  }
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes service IPs"
  type        = string
  default     = "172.20.0.0/16"
}

variable "app_node_instance_types" {
  description = "Instance types for application node group"
  type        = list(string)
  default     = ["m5.xlarge"]
}

variable "app_node_capacity_type" {
  description = "Capacity type for the application node group: ON_DEMAND for production stability, SPOT for cost-optimised dev/test"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.app_node_capacity_type)
    error_message = "app_node_capacity_type must be either 'ON_DEMAND' or 'SPOT'."
  }
}

variable "app_node_desired" {
  description = "Desired number of application nodes"
  type        = number
  default     = 3
}

variable "app_node_min" {
  description = "Minimum number of application nodes"
  type        = number
  default     = 3
}

variable "app_node_max" {
  description = "Maximum number of application nodes (must be >= app_node_min)"
  type        = number
  default     = 10

  validation {
    condition     = var.app_node_max >= 1
    error_message = "app_node_max must be at least 1."
  }
}

variable "vpc_cni_version" {
  description = "VPC CNI addon version"
  type        = string
  default     = "v1.16.4-eksbuild.2"
}

variable "coredns_version" {
  description = "CoreDNS addon version"
  type        = string
  default     = "v1.11.1-eksbuild.6"
}

variable "kube_proxy_version" {
  description = "kube-proxy addon version"
  type        = string
  default     = "v1.29.1-eksbuild.2"
}

variable "ebs_csi_version" {
  description = "EBS CSI driver addon version"
  type        = string
  default     = "v1.28.0-eksbuild.1"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
