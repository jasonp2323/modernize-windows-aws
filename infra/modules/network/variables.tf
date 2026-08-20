variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones. Two is the minimum for AWS Managed Microsoft AD, Multi-AZ FSx and RDS."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "subnet_newbits" {
  description = "Bits added to the VPC prefix length for each subnet. 8 on a /16 gives /24 subnets."
  type        = number
  default     = 8
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways so private subnets can reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs. Cheaper for a lab, not HA."
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Create interface endpoints for SSM/Secrets Manager/logs/KMS and an S3 gateway endpoint."
  type        = bool
  default     = true
}
