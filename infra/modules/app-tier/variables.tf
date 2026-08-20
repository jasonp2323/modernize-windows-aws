variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC that hosts the application tier."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the application servers."
  type        = list(string)
}

variable "instance_profile_name" {
  description = "Instance profile from the domain-join module."
  type        = string
}

variable "domain_join_tags" {
  description = "Tags that make the domain join association pick these instances up."
  type        = map(string)
}

variable "instance_count" {
  description = "Number of application servers."
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "Instance type for the application servers."
  type        = string
  default     = "m6i.large"
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 100
}

variable "windows_ami_ssm_parameter" {
  description = "SSM public parameter naming the Windows AMI to launch."
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

variable "key_pair_name" {
  description = "EC2 key pair, used only to retrieve the local administrator password. Null to omit."
  type        = string
  default     = null
}

variable "client_cidrs" {
  description = "CIDRs allowed to reach the application over HTTP/HTTPS."
  type        = list(string)
  default     = []
}

variable "admin_cidrs" {
  description = "CIDRs allowed to RDP to the application servers."
  type        = list(string)
  default     = []
}

variable "create_load_balancer" {
  description = "Front the application servers with an internal Application Load Balancer."
  type        = bool
  default     = true
}

variable "sql_endpoint" {
  description = "RDS SQL Server endpoint, surfaced on the diagnostic page."
  type        = string
  default     = "not-configured"
}
