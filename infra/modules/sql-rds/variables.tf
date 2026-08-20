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
  description = "VPC that hosts the database."
  type        = string
}

variable "subnet_ids" {
  description = "At least two data tier subnets in different AZs."
  type        = list(string)
}

variable "directory_id" {
  description = "AWS Managed Microsoft AD directory ID for Windows Authentication."
  type        = string
}

variable "client_cidrs" {
  description = "CIDRs allowed to reach TCP 1433."
  type        = list(string)
  default     = []
}

variable "client_security_group_ids" {
  description = "Security groups allowed to reach TCP 1433."
  type        = list(string)
  default     = []
}

variable "engine" {
  description = "RDS SQL Server edition. Standard Edition supports Multi-AZ and Windows Authentication."
  type        = string
  default     = "sqlserver-se"

  validation {
    condition     = contains(["sqlserver-ex", "sqlserver-web", "sqlserver-se", "sqlserver-ee"], var.engine)
    error_message = "engine must be one of sqlserver-ex, sqlserver-web, sqlserver-se, sqlserver-ee."
  }
}

variable "engine_version" {
  description = "Engine version, for example 16.00. Null tracks the current default."
  type        = string
  default     = null
}

variable "parameter_group_family" {
  description = "Parameter group family matching the engine and version."
  type        = string
  default     = "sqlserver-se-16.0"
}

variable "instance_class" {
  description = "DB instance class."
  type        = string
  default     = "db.m6i.large"
}

variable "allocated_storage" {
  description = "Allocated storage in GiB. SQL Server Standard Edition needs at least 20."
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling. 0 disables it."
  type        = number
  default     = 500
}

variable "storage_type" {
  description = "Storage type."
  type        = string
  default     = "gp3"
}

variable "kms_key_id" {
  description = "KMS key for storage encryption. Null uses the AWS managed key."
  type        = string
  default     = null
}

variable "master_username" {
  description = "SQL Authentication master user. Cannot be 'sa' or another reserved name."
  type        = string
  default     = "sqladmin"
}

variable "multi_az" {
  description = "Deploy a standby in a second AZ."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Automated backup retention in days."
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Daily backup window, HH:MM-HH:MM UTC."
  type        = string
  default     = "04:00-05:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window."
  type        = string
  default     = "sun:06:00-sun:07:00"
}

variable "deletion_protection" {
  description = "Block accidental deletion."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy."
  type        = bool
  default     = true
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Log types to export. SQL Server supports agent and error."
  type        = list(string)
  default     = ["error"]
}

variable "timezone" {
  description = "SQL Server time zone. Null uses UTC."
  type        = string
  default     = null
}
