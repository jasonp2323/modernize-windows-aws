variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "role" {
  description = "Short role name for this file system, for example \"shares\" or \"profiles\"."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the file system."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the file system. The first is the preferred subnet for Multi-AZ."
  type        = list(string)
}

variable "directory_id" {
  description = "AWS Managed Microsoft AD directory ID the file system joins."
  type        = string
}

variable "client_cidrs" {
  description = "CIDRs allowed to reach SMB and FSx remote management."
  type        = list(string)
}

variable "deployment_type" {
  description = "SINGLE_AZ_1, SINGLE_AZ_2 or MULTI_AZ_1."
  type        = string
  default     = "MULTI_AZ_1"

  validation {
    condition     = contains(["SINGLE_AZ_1", "SINGLE_AZ_2", "MULTI_AZ_1"], var.deployment_type)
    error_message = "deployment_type must be SINGLE_AZ_1, SINGLE_AZ_2 or MULTI_AZ_1."
  }
}

variable "storage_capacity" {
  description = "Storage in GiB. Minimum 32 for SSD."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "SSD or HDD. FSLogix containers should stay on SSD."
  type        = string
  default     = "SSD"
}

variable "throughput_capacity" {
  description = "Throughput in MB/s."
  type        = number
  default     = 32
}

variable "aliases" {
  description = <<-EOT
    Optional DNS aliases, for example ["profiles.corp.example.com"]. Using an
    alias in the FSLogix VHDLocations GPO keeps the UNC path stable if the file
    system is ever replaced. The management automation creates the matching DNS
    record and service principal names.
  EOT
  type        = list(string)
  default     = []
}

variable "backup_retention_days" {
  description = "Automatic backup retention in days. 0 disables automatic backups."
  type        = number
  default     = 7
}

variable "daily_backup_start_time" {
  description = "Daily backup window start, HH:MM UTC."
  type        = string
  default     = "05:00"
}

variable "weekly_maintenance_start_time" {
  description = "Weekly maintenance window, d:HH:MM (1 = Monday) UTC."
  type        = string
  default     = "7:06:00"
}

variable "skip_final_backup" {
  description = "Skip the final backup on destroy. True keeps lab teardown quick."
  type        = bool
  default     = true
}

variable "audit_log_destination_arn" {
  description = "CloudWatch Logs or Firehose ARN for file access auditing. Null disables auditing."
  type        = string
  default     = null
}
