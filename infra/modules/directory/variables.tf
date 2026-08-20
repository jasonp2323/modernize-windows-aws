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
  description = "VPC that hosts the directory."
  type        = string
}

variable "subnet_ids" {
  description = "At least two subnets in different AZs for the domain controllers."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "AWS Managed Microsoft AD requires two subnets in different Availability Zones."
  }
}

variable "domain_name" {
  description = "Fully qualified domain name, for example corp.example.com."
  type        = string
}

variable "domain_netbios_name" {
  description = "NetBIOS (short) name, for example CORP."
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9-]{1,15}$", var.domain_netbios_name))
    error_message = "NetBIOS name must be 1-15 upper case letters, digits or hyphens."
  }
}

variable "edition" {
  description = "Standard or Enterprise. Standard is enough for this sample."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Enterprise"], var.edition)
    error_message = "edition must be Standard or Enterprise."
  }
}

variable "admin_password" {
  description = "Password for the delegated Admin account. Leave null to generate one and store it in Secrets Manager."
  type        = string
  default     = null
  sensitive   = true
}

variable "service_account_name" {
  description = "sAMAccountName of the domain service account used for directory join and automation."
  type        = string
  default     = "svc-join"
}

variable "manage_dhcp_options" {
  description = "Create and associate a DHCP options set pointing the VPC at the domain controllers."
  type        = bool
  default     = true
}

variable "secret_recovery_window_in_days" {
  description = "Secrets Manager recovery window. 0 deletes immediately, which is convenient for a lab you rebuild often."
  type        = number
  default     = 7
}
