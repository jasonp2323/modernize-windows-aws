variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "directory_id" {
  description = "AWS Managed Microsoft AD directory ID."
  type        = string
}

variable "directory_name" {
  description = "Fully qualified domain name."
  type        = string
}

variable "dns_ip_addresses" {
  description = "Domain controller DNS addresses."
  type        = list(string)
}

variable "join_tag_key" {
  description = "Tag key that selects instances for domain join."
  type        = string
  default     = "DomainJoin"
}

variable "join_tag_value" {
  description = "Tag value that selects instances for domain join."
  type        = string
  default     = "true"
}

variable "readable_secret_arns" {
  description = "Secrets Manager ARNs the instances may read (domain admin, service account, SQL master)."
  type        = list(string)
  default     = []
}

variable "scripts_bucket_arn" {
  description = "S3 bucket holding the PowerShell automation. Null to skip the grant."
  type        = string
  default     = null
}
