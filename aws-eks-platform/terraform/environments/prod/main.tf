################################################################################
# Production Environment
# aws-eks-platform/terraform/environments/prod/main.tf
################################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "eks-platform-tfstate-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "eks-platform-tfstate-lock"
    kms_key_id     = "alias/eks-platform-tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_id
}

data "aws_caller_identity" "current" {}

locals {
  environment  = "prod"
  cluster_name = "eks-platform-prod"

  common_tags = {
    Environment = local.environment
    Project     = "eks-platform"
    ManagedBy   = "terraform"
    Owner       = "platform-team"
    CostCenter  = "engineering"
  }
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  name         = "eks-platform-prod"
  vpc_cidr     = "10.0.0.0/16"
  az_count     = 3
  region       = var.aws_region
  cluster_name = local.cluster_name

  tags = local.common_tags
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = "1.29"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  # Restrict API access in production
  endpoint_public_access = true
  public_access_cidrs    = var.allowed_cidr_blocks

  # Application node group — production sizing
  app_node_instance_types = ["m5.2xlarge", "m5a.2xlarge"]
  app_node_capacity_type  = "ON_DEMAND"
  app_node_desired        = 3
  app_node_min            = 3
  app_node_max            = 20

  tags = local.common_tags
}

################################################################################
# RDS Aurora PostgreSQL
################################################################################

module "rds" {
  source = "../../modules/rds"

  identifier      = "eks-platform-prod"
  engine_version  = "15.4"
  instance_class  = "db.r7g.xlarge"
  instances       = 2 # writer + 1 reader

  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.intra_subnet_ids
  allowed_sg_ids      = [module.eks.node_security_group_id]

  # Encrypt Secrets Manager secret with the same KMS key used for EKS + EBS
  kms_key_arn = module.eks.kms_key_arn

  database_name = "platform"
  master_username = "platform_admin"

  deletion_protection      = true
  backup_retention_period  = 14
  preferred_backup_window  = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  performance_insights_enabled = true
  monitoring_interval          = 60

  tags = local.common_tags
}

################################################################################
# ALB Controller (AWS Load Balancer Controller)
################################################################################

module "alb" {
  source = "../../modules/alb"

  cluster_name      = local.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = module.vpc.vpc_id
  aws_region        = var.aws_region

  tags = local.common_tags
}

################################################################################
# Cluster Autoscaler
################################################################################

module "cluster_autoscaler" {
  source = "../../modules/monitoring"

  cluster_name      = local.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  aws_region        = var.aws_region

  tags = local.common_tags
}

################################################################################
# ECR Repositories
################################################################################

resource "aws_ecr_repository" "app" {
  for_each = toset(var.ecr_repositories)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = module.eks.kms_key_arn
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
