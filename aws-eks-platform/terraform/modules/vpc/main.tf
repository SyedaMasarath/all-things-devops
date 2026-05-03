################################################################################
# VPC Module
# Production-grade multi-AZ VPC with public/private subnets,
# NAT Gateways, VPC Flow Logs, and proper EKS tagging
################################################################################

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  public_subnet_cidrs  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + var.az_count)]
  intra_subnet_cidrs   = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + var.az_count * 2)]

  tags = merge(var.tags, {
    Module = "vpc"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${var.name}-vpc"
  })
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-igw"
  })
}

################################################################################
# Public Subnets (ALB, NAT Gateway)
################################################################################

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name                     = "${var.name}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb" = "1"
    # Required for AWS Load Balancer Controller
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

################################################################################
# Private Subnets (EKS Nodes)
################################################################################

resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, {
    Name                              = "${var.name}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

################################################################################
# Intra Subnets (RDS, ElastiCache — no internet access)
################################################################################

resource "aws_subnet" "intra" {
  count = length(local.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.intra_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, {
    Name = "${var.name}-intra-${local.azs[count.index]}"
  })
}

################################################################################
# NAT Gateways (one per AZ for HA)
################################################################################

resource "aws_eip" "nat" {
  count  = length(local.azs)
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${var.name}-nat-eip-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = length(local.azs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, {
    Name = "${var.name}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

################################################################################
# Route Tables
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = merge(local.tags, {
    Name = "${var.name}-private-rt-${local.azs[count.index]}"
  })
}

resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.this.id
  # No routes to internet — intra subnets are isolated

  tags = merge(local.tags, {
    Name = "${var.name}-intra-rt"
  })
}

################################################################################
# Route Table Associations
################################################################################

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "intra" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra.id
}

################################################################################
# VPC Flow Logs (Security & Compliance)
################################################################################

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = local.tags
}

resource "aws_flow_log" "this" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.name}-flow-log"
  })
}

resource "aws_iam_role" "vpc_flow_log" {
  name = "${var.name}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name   = "${var.name}-vpc-flow-log-policy"
  role   = aws_iam_role.vpc_flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

################################################################################
# VPC Endpoints (reduce NAT Gateway costs)
################################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.private[*].id, [aws_route_table.intra.id])

  tags = merge(local.tags, {
    Name = "${var.name}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.name}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.name}-ecr-dkr-endpoint"
  })
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.name}-secretsmanager-endpoint"
  })
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC"
  }

  tags = merge(local.tags, {
    Name = "${var.name}-vpc-endpoints-sg"
  })
}
