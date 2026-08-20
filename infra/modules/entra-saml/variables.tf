variable "name_prefix" {
  description = "Prefix for AWS resource names."
  type        = string
}

variable "display_name_prefix" {
  description = "Prefix for Entra ID application and group display names."
  type        = string
  default     = "AWS WorkSpaces Applications"
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = {}
}

variable "tenant_id" {
  description = "Entra ID tenant ID, used to build the federation metadata URL."
  type        = string
}

variable "stacks" {
  description = "WorkSpaces Applications stacks to federate, keyed by short name."
  type = map(object({
    stack_name   = string
    stack_arn    = string
    display_name = string
  }))
}

variable "session_duration_seconds" {
  description = "SAML session duration. Must be between 900 and 43200, and not longer than the role's max session duration."
  type        = number
  default     = 3600

  validation {
    condition     = var.session_duration_seconds >= 900 && var.session_duration_seconds <= 43200
    error_message = "session_duration_seconds must be between 900 and 43200."
  }
}

variable "signing_certificate_end_date" {
  description = "Expiry for the SAML token signing certificate, RFC3339."
  type        = string
  default     = "2027-01-01T00:00:00Z"
}

variable "manage_claims_mapping_policy" {
  description = "Emit the AWS Role/RoleSessionName/SessionDuration claims from Terraform. Set false to configure them in the Entra portal instead."
  type        = bool
  default     = true
}
