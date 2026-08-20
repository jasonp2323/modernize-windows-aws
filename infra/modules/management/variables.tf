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
  description = "VPC that hosts the management servers."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the management servers."
  type        = list(string)
}

variable "scripts_bucket" {
  description = "S3 bucket that holds the PowerShell automation."
  type        = string
}

variable "instance_profile_name" {
  description = "Instance profile from the domain-join module."
  type        = string
}

variable "domain_join_tags" {
  description = "Tags that make the domain join association pick these instances up."
  type        = map(string)
}

variable "key_pair_name" {
  description = "EC2 key pair, used only to retrieve the local administrator password. Null to omit."
  type        = string
  default     = null
}

variable "windows_ami_ssm_parameter" {
  description = "SSM public parameter naming the Windows AMI to launch."
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

variable "management_instance_type" {
  description = "Instance type for the management server."
  type        = string
  default     = "t3.medium"
}

variable "allowed_rdp_cidrs" {
  description = "CIDRs allowed to RDP to the management servers. Empty means Fleet Manager / Session Manager only."
  type        = list(string)
  default     = []
}

##############################################################################
# Domain configuration payload
##############################################################################

variable "domain_name" {
  description = "Fully qualified domain name."
  type        = string
}

variable "domain_netbios_name" {
  description = "NetBIOS domain name."
  type        = string
}

variable "delegated_ou_dn" {
  description = "Distinguished name of the delegated OU that everything is created under."
  type        = string
}

variable "admin_secret_arn" {
  description = "Secrets Manager ARN with the delegated admin credentials."
  type        = string
}

variable "service_account_secret_arn" {
  description = "Secrets Manager ARN with the directory service account credentials."
  type        = string
}

variable "organizational_units" {
  description = "OU paths to create under the delegated OU, using / to nest."
  type        = list(string)
}

variable "security_groups" {
  description = "Directory security groups to create."
  type = list(object({
    Name        = string
    Description = string
  }))
}

variable "join_delegation_ou_dns" {
  description = "OU distinguished names where the service account may create and manage computer objects."
  type        = list(string)
}

variable "file_systems" {
  description = "FSx file systems, their shares and DNS aliases."
  type = list(object({
    DnsName = string
    Purpose = string # "fslogix" applies the FSLogix ACL model, anything else uses Modify
    Aliases = list(string)
    Shares = list(object({
      Name         = string
      Folder       = string
      Description  = string
      FullAccess   = list(string)
      ChangeAccess = list(string)
    }))
  }))
}

variable "fslogix" {
  description = "FSLogix GPO settings."
  type = object({
    GpoName               = string
    ProfileUnc            = string
    OfficeUnc             = string
    SizeInMBs             = number
    EnableOfficeContainer = bool
    LinkOus               = list(string)
  })
}

##############################################################################
# Entra Connect
##############################################################################

variable "enable_entra_connect_server" {
  description = "Deploy a domain-joined server with Entra Connect Sync staged and its connector account prepared."
  type        = bool
  default     = true
}

variable "entra_connect_instance_type" {
  description = "Instance type for the Entra Connect server."
  type        = string
  default     = "t3.large"
}

variable "entra_upn_suffix" {
  description = "Routable UPN suffix to add to the forest, matching a verified Entra ID domain. Null to skip."
  type        = string
  default     = null
}

variable "entra_connect_download_url" {
  description = "Download URL for the Entra Connect Sync installer."
  type        = string
  default     = "https://download.microsoft.com/download/B/0/0/B00291D0-5A83-4DE7-86F5-980BC00DE05A/AzureADConnect.msi"
}

##############################################################################
# Association behaviour
##############################################################################

variable "association_schedule_expression" {
  description = "How often State Manager re-applies the (idempotent) domain automation."
  type        = string
  default     = "rate(1 hour)"
}

variable "wait_for_association_success" {
  description = "Make terraform apply block until the domain configuration association succeeds. Useful when the WorkSpaces Applications stage is applied in the same run."
  type        = bool
  default     = false
}
