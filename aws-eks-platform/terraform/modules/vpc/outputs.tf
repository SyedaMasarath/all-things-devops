output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "intra_subnet_ids" {
  description = "List of intra subnet IDs (DB/cache tier)"
  value       = aws_subnet.intra[*].id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "List of public IPs for NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "azs" {
  description = "Availability zones used"
  value       = local.azs
}
