variable "project_name" {
  description = "Short name used to prefix every bootstrap resource."
  type        = string
  default     = "modernize-windows"
}

variable "aws_region" {
  description = "Region the bootstrap resources are created in. IAM is global, but the provider still needs a region."
  type        = string
  default     = "us-east-1"
}

##############################################################################
# HCP Terraform (Terraform Cloud) identity
##############################################################################

variable "hcp_terraform_hostname" {
  description = "HCP Terraform hostname. Change only for Terraform Enterprise."
  type        = string
  default     = "app.terraform.io"
}

variable "hcp_organization" {
  description = "HCP Terraform organization name."
  type        = string
}

variable "hcp_project" {
  description = "HCP Terraform project that holds the workspace(s). Used in the OIDC subject condition."
  type        = string
  default     = "Default Project"
}

variable "hcp_workspace_names" {
  description = <<-EOT
    Workspaces allowed to assume the run role. Each entry becomes an allowed
    OIDC subject of the form:
      organization:<org>:project:<project>:workspace:<name>:run_phase:<phase>
  EOT
  type        = list(string)
  default     = ["modernize-windows-aws"]
}

variable "hcp_run_phases" {
  description = "Run phases allowed to assume the role. `plan` and `apply` is the normal set."
  type        = list(string)
  default     = ["plan", "apply"]
}

variable "hcp_aws_audience" {
  description = "Audience value HCP Terraform puts in the OIDC token (TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE)."
  type        = string
  default     = "aws.workload.identity"
}

variable "oidc_thumbprint_list" {
  description = <<-EOT
    Optional certificate thumbprints for the OIDC provider. AWS no longer
    verifies thumbprints for providers hosted on well-known CAs, so leaving
    this empty is fine for app.terraform.io. Set it for Terraform Enterprise
    behind a private CA.
  EOT
  type        = list(string)
  default     = []
}

variable "create_oidc_provider" {
  description = "Create the IAM OIDC provider. Set to false if another stack in this account already created one for app.terraform.io."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of a pre-existing IAM OIDC provider for HCP Terraform. Required when create_oidc_provider = false."
  type        = string
  default     = null
}

##############################################################################
# Permissions granted to the run role
##############################################################################

variable "use_administrator_access" {
  description = <<-EOT
    Attach AdministratorAccess to the run role instead of the scoped policy in
    iam.tf. Fastest way to get a lab moving; not recommended beyond that.
  EOT
  type        = bool
  default     = false
}

variable "resource_name_prefix" {
  description = "Prefix the run role is allowed to manage IAM roles/policies/instance profiles under. Must match the prefix used by the infra stack."
  type        = string
  default     = "mwa"
}

##############################################################################
# Optional: create the VCS-driven workspace itself
##############################################################################

variable "manage_hcp_workspace" {
  description = "Create the VCS-driven HCP Terraform workspace and its variables from here. Requires TFE_TOKEN and a VCS connection (OAuth token) in the org."
  type        = bool
  default     = false
}

variable "vcs_repo_identifier" {
  description = "GitHub repository in <org>/<repo> form to attach to the workspace."
  type        = string
  default     = null
}

variable "vcs_branch" {
  description = "Branch HCP Terraform watches for the VCS-driven workflow."
  type        = string
  default     = "main"
}

variable "vcs_oauth_token_id" {
  description = "OAuth token ID of the VCS connection in the HCP Terraform org (ot-xxxxxxxx)."
  type        = string
  default     = null
}

variable "workspace_working_directory" {
  description = "Directory inside the repo that HCP Terraform runs from."
  type        = string
  default     = "infra"
}

variable "workspace_terraform_version" {
  description = "Terraform version pinned on the workspace."
  type        = string
  default     = "~> 1.13.0"
}

variable "workspace_auto_apply" {
  description = "Auto-apply successful plans on the VCS-driven workspace."
  type        = bool
  default     = false
}
