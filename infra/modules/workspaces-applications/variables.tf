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
  description = "VPC that hosts the streaming ENIs."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for fleets and image builders."
  type        = list(string)
}

variable "directory_name" {
  description = "Fully qualified domain name the fleets join."
  type        = string
}

variable "organizational_unit_distinguished_names" {
  description = "OUs the directory config makes available for fleet and image builder computer objects."
  type        = list(string)
}

variable "service_account_name" {
  description = "Domain service account in DOMAIN\\user form, delegated computer object rights on the streaming OUs."
  type        = string
}

variable "service_account_password" {
  description = "Password for the directory service account."
  type        = string
  sensitive   = true
}

variable "base_image_name" {
  description = <<-EOT
    Public base image the image builders start from, for example
    "AppStream-WinServer2022-07-21-2025". List current names with:
      aws appstream describe-images --type PUBLIC \
        --query "Images[?starts_with(Name,'AppStream-WinServer')].Name"
  EOT
  type        = string
  default     = null
}

variable "enable_image_builders" {
  description = "Create the image builders. Turn on for stage 2, off once the images exist."
  type        = bool
  default     = false
}

variable "image_builders" {
  description = "Image builders to create."
  type = map(object({
    display_name                           = string
    description                            = string
    instance_type                          = string
    organizational_unit_distinguished_name = string
  }))
  default = {}
}

variable "enable_fleets" {
  description = "Create the fleets and stacks. Requires images built with Image Assistant."
  type        = bool
  default     = false
}

variable "fleets" {
  description = "Fleets and their matching stacks."
  type = map(object({
    display_name                           = string
    description                            = string
    image_name                             = string
    instance_type                          = string
    fleet_type                             = string # ALWAYS_ON or ON_DEMAND
    stream_view                            = string # APP or DESKTOP
    desired_instances                      = number
    min_capacity                           = number
    max_capacity                           = number
    max_user_duration_in_seconds           = number
    disconnect_timeout_in_seconds          = number
    idle_disconnect_timeout_in_seconds     = number
    organizational_unit_distinguished_name = string
  }))
  default = {}
}

variable "user_settings" {
  description = "Stack user settings, keyed by action. DOMAIN_PASSWORD_SIGNIN must stay enabled for domain-joined fleets."
  type        = map(string)
  default = {
    CLIPBOARD_COPY_FROM_LOCAL_DEVICE = "ENABLED"
    CLIPBOARD_COPY_TO_LOCAL_DEVICE   = "ENABLED"
    FILE_UPLOAD                      = "ENABLED"
    FILE_DOWNLOAD                    = "ENABLED"
    PRINTING_TO_LOCAL_DEVICE         = "ENABLED"
    DOMAIN_PASSWORD_SIGNIN           = "ENABLED"
    DOMAIN_SMART_CARD_SIGNIN         = "DISABLED"
  }
}

variable "enable_autoscaling" {
  description = "Attach target-tracking auto scaling to the fleets."
  type        = bool
  default     = false
}

variable "autoscaling_target_utilization" {
  description = "Target fleet capacity utilization percentage."
  type        = number
  default     = 75
}
