##############################################################################
# Naming and tagging
##############################################################################

variable "name_prefix" {
  description = "Prefix for every AWS resource name. Must match resource_name_prefix in ../bootstrap."
  type        = string
  default     = "mwa"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2-11 lower case letters, digits or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment label applied as a tag."
  type        = string
  default     = "lab"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "platform-team"
}

variable "additional_tags" {
  description = "Extra tags merged into the default tag set."
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "Region for the whole environment."
  type        = string
  default     = "us-east-1"
}

##############################################################################
# Network
##############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to spread across."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway. Cheaper for a lab."
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Create SSM/Secrets Manager/logs/KMS interface endpoints and an S3 gateway endpoint."
  type        = bool
  default     = true
}

variable "admin_cidrs" {
  description = "CIDRs allowed to RDP to the management and application servers. Empty means Fleet Manager and Session Manager only."
  type        = list(string)
  default     = []
}

##############################################################################
# Directory
##############################################################################

variable "domain_name" {
  description = "Fully qualified domain name for the new forest."
  type        = string
  default     = "corp.example.com"
}

variable "domain_netbios_name" {
  description = "NetBIOS name of the domain."
  type        = string
  default     = "CORP"
}

variable "directory_edition" {
  description = "AWS Managed Microsoft AD edition: Standard or Enterprise."
  type        = string
  default     = "Standard"
}

variable "directory_service_account_name" {
  description = "sAMAccountName of the account used for directory joins and streaming automation."
  type        = string
  default     = "svc-join"
}

variable "key_pair_name" {
  description = "EC2 key pair used to retrieve local administrator passwords. Null to omit."
  type        = string
  default     = null
}

##############################################################################
# File storage
##############################################################################

variable "fsx_deployment_type" {
  description = "FSx deployment type for both file systems."
  type        = string
  default     = "MULTI_AZ_1"
}

variable "fsx_shares_storage_capacity" {
  description = "Storage in GiB for the general file share file system."
  type        = number
  default     = 100
}

variable "fsx_shares_throughput_capacity" {
  description = "Throughput in MB/s for the general file share file system."
  type        = number
  default     = 32
}

variable "fsx_profiles_storage_capacity" {
  description = "Storage in GiB for the FSLogix profile file system."
  type        = number
  default     = 200
}

variable "fsx_profiles_throughput_capacity" {
  description = "Throughput in MB/s for the FSLogix profile file system. Profile containers are latency sensitive."
  type        = number
  default     = 64
}

variable "fsx_use_dns_aliases" {
  description = "Give each file system a friendly DNS alias (files./profiles.<domain>) so UNC paths survive a file system rebuild."
  type        = bool
  default     = true
}

variable "fslogix_container_size_mb" {
  description = "Maximum size of each FSLogix container in MB. Containers are dynamic, so this is a ceiling."
  type        = number
  default     = 30000
}

variable "fslogix_enable_office_container" {
  description = "Also redirect the Office/Outlook cache into its own container."
  type        = bool
  default     = true
}

##############################################################################
# Application tier
##############################################################################

variable "app_server_count" {
  description = "Number of Windows application servers."
  type        = number
  default     = 1
}

variable "app_server_instance_type" {
  description = "Instance type for the application servers."
  type        = string
  default     = "m6i.large"
}

variable "management_instance_type" {
  description = "Instance type for the management server."
  type        = string
  default     = "t3.medium"
}

variable "entra_connect_instance_type" {
  description = "Instance type for the Entra Connect server."
  type        = string
  default     = "t3.large"
}

variable "windows_ami_ssm_parameter" {
  description = "SSM public parameter naming the Windows Server AMI."
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

variable "create_app_load_balancer" {
  description = "Front the application servers with an internal ALB."
  type        = bool
  default     = true
}

##############################################################################
# SQL Server
##############################################################################

variable "sql_engine" {
  description = "RDS SQL Server edition."
  type        = string
  default     = "sqlserver-se"
}

variable "sql_engine_version" {
  description = "Engine version. Null tracks the RDS default for the edition."
  type        = string
  default     = null
}

variable "sql_parameter_group_family" {
  description = "Parameter group family, must match the engine and major version."
  type        = string
  default     = "sqlserver-se-16.0"
}

variable "sql_instance_class" {
  description = "DB instance class."
  type        = string
  default     = "db.m6i.large"
}

variable "sql_allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 100
}

variable "sql_multi_az" {
  description = "Deploy the database Multi-AZ."
  type        = bool
  default     = false
}

##############################################################################
# WorkSpaces Applications (AppStream 2.0)
##############################################################################

variable "enable_image_builders" {
  description = "Stage 2: create image builders so you can build the streaming images."
  type        = bool
  default     = false
}

variable "enable_streaming_fleets" {
  description = "Stage 3: create the fleets and stacks. Requires images built from the image builders."
  type        = bool
  default     = false
}

variable "appstream_base_image_name" {
  description = <<-EOT
    Public base image for the image builders, for example
    "AppStream-WinServer2022-07-21-2025". Find current names with:
      aws appstream describe-images --type PUBLIC \
        --query "Images[?starts_with(Name,'AppStream-WinServer')].Name"
  EOT
  type        = string
  default     = null

  validation {
    condition     = !var.enable_image_builders || var.appstream_base_image_name != null
    error_message = "appstream_base_image_name must be set when enable_image_builders is true."
  }
}

variable "appstream_app_image_name" {
  description = "Name of the image built for the published-application fleet."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_streaming_fleets || var.appstream_app_image_name != null
    error_message = "appstream_app_image_name must be set before the fleets can be created."
  }
}

variable "appstream_desktop_image_name" {
  description = "Name of the image built for the non-persistent desktop fleet."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_streaming_fleets || var.appstream_desktop_image_name != null
    error_message = "appstream_desktop_image_name must be set before the fleets can be created."
  }
}

variable "appstream_image_builder_instance_type" {
  description = "Instance type for image builders."
  type        = string
  default     = "stream.standard.medium"
}

variable "appstream_app_fleet" {
  description = "Sizing for the published-application fleet."
  type = object({
    instance_type                      = string
    fleet_type                         = string
    desired_instances                  = number
    min_capacity                       = number
    max_capacity                       = number
    max_user_duration_in_seconds       = number
    disconnect_timeout_in_seconds      = number
    idle_disconnect_timeout_in_seconds = number
  })
  default = {
    instance_type                      = "stream.standard.medium"
    fleet_type                         = "ON_DEMAND"
    desired_instances                  = 2
    min_capacity                       = 1
    max_capacity                       = 10
    max_user_duration_in_seconds       = 57600
    disconnect_timeout_in_seconds      = 900
    idle_disconnect_timeout_in_seconds = 900
  }
}

variable "appstream_desktop_fleet" {
  description = "Sizing for the non-persistent desktop fleet."
  type = object({
    instance_type                      = string
    fleet_type                         = string
    desired_instances                  = number
    min_capacity                       = number
    max_capacity                       = number
    max_user_duration_in_seconds       = number
    disconnect_timeout_in_seconds      = number
    idle_disconnect_timeout_in_seconds = number
  })
  default = {
    instance_type                      = "stream.standard.large"
    fleet_type                         = "ON_DEMAND"
    desired_instances                  = 2
    min_capacity                       = 1
    max_capacity                       = 10
    max_user_duration_in_seconds       = 57600
    disconnect_timeout_in_seconds      = 900
    idle_disconnect_timeout_in_seconds = 1800
  }
}

variable "enable_streaming_autoscaling" {
  description = "Attach target-tracking auto scaling to the fleets."
  type        = bool
  default     = false
}

##############################################################################
# Microsoft Entra ID
##############################################################################

variable "enable_entra_connect_server" {
  description = "Deploy the Entra Connect Sync server and prepare its connector account."
  type        = bool
  default     = true
}

variable "enable_entra_saml" {
  description = "Create the Entra ID enterprise applications that federate users into the streaming stacks."
  type        = bool
  default     = false
}

variable "entra_tenant_id" {
  description = "Entra ID tenant ID. Required when enable_entra_saml is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_entra_saml || var.entra_tenant_id != null
    error_message = "entra_tenant_id must be set when enable_entra_saml is true."
  }
}

variable "entra_upn_suffix" {
  description = "Routable UPN suffix to add to the forest so synced users match a verified Entra domain, for example example.com."
  type        = string
  default     = null
}

variable "entra_saml_session_duration_seconds" {
  description = "Streaming session duration granted by the SAML assertion."
  type        = number
  default     = 3600
}

##############################################################################
# Automation behaviour
##############################################################################

variable "domain_automation_schedule" {
  description = "How often State Manager re-applies the idempotent domain automation."
  type        = string
  default     = "rate(1 hour)"
}

variable "wait_for_domain_automation" {
  description = "Block the apply until the domain automation association reports success. Turn on for the run that first enables streaming."
  type        = bool
  default     = false
}
