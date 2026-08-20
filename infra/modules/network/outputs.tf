output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "AZs in use, in order."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs, ordered by AZ."
  value       = [for az in local.azs : aws_subnet.public[az].id]
}

output "app_subnet_ids" {
  description = "Application tier subnet IDs, ordered by AZ."
  value       = [for az in local.azs : aws_subnet.app[az].id]
}

output "data_subnet_ids" {
  description = "Data tier subnet IDs (AD, FSx, RDS), ordered by AZ."
  value       = [for az in local.azs : aws_subnet.data[az].id]
}

output "stream_subnet_ids" {
  description = "Streaming tier subnet IDs (WorkSpaces Applications fleets), ordered by AZ."
  value       = [for az in local.azs : aws_subnet.stream[az].id]
}

output "app_subnet_cidrs" {
  description = "Application tier CIDRs."
  value       = [for az in local.azs : aws_subnet.app[az].cidr_block]
}

output "stream_subnet_cidrs" {
  description = "Streaming tier CIDRs."
  value       = [for az in local.azs : aws_subnet.stream[az].cidr_block]
}
