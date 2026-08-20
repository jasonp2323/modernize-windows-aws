##############################################################################
# Optional: create the VCS-driven HCP Terraform workspace and wire dynamic
# credentials into it. Set manage_hcp_workspace = true and export TFE_TOKEN.
#
# Everything here can just as easily be clicked together in the HCP Terraform
# UI - it is included so the whole path from "empty AWS account" to "VCS-driven
# workspace with dynamic credentials" is codified.
##############################################################################

data "tfe_project" "this" {
  count = var.manage_hcp_workspace ? 1 : 0

  name         = var.hcp_project
  organization = var.hcp_organization
}

resource "tfe_workspace" "infra" {
  count = var.manage_hcp_workspace ? 1 : 0

  name         = var.hcp_workspace_names[0]
  organization = var.hcp_organization
  project_id   = data.tfe_project.this[0].id
  description  = "Modern Windows environment on AWS - VCS-driven."

  working_directory = var.workspace_working_directory
  terraform_version = var.workspace_terraform_version
  auto_apply        = var.workspace_auto_apply

  # Default VCS-driven behaviour: a push to the tracked branch queues a plan,
  # a merge to it queues an apply (after approval unless auto_apply is on).
  file_triggers_enabled = true
  trigger_patterns      = ["${var.workspace_working_directory}/**/*"]
  queue_all_runs        = false

  vcs_repo {
    identifier     = var.vcs_repo_identifier
    branch         = var.vcs_branch
    oauth_token_id = var.vcs_oauth_token_id
  }

  lifecycle {
    precondition {
      condition     = var.vcs_repo_identifier != null && var.vcs_oauth_token_id != null
      error_message = "manage_hcp_workspace = true requires vcs_repo_identifier and vcs_oauth_token_id."
    }
  }
}

# Dynamic credentials: these two environment variables are all HCP Terraform
# needs to exchange its workload identity token for AWS credentials.
resource "tfe_variable" "aws_provider_auth" {
  count = var.manage_hcp_workspace ? 1 : 0

  workspace_id = tfe_workspace.infra[0].id
  key          = "TFC_AWS_PROVIDER_AUTH"
  value        = "true"
  category     = "env"
  description  = "Enables AWS dynamic provider credentials."
}

resource "tfe_variable" "aws_run_role" {
  count = var.manage_hcp_workspace ? 1 : 0

  workspace_id = tfe_workspace.infra[0].id
  key          = "TFC_AWS_RUN_ROLE_ARN"
  value        = aws_iam_role.run.arn
  category     = "env"
  description  = "Role assumed by plan and apply runs."
}

resource "tfe_variable" "aws_audience" {
  count = var.manage_hcp_workspace ? 1 : 0

  workspace_id = tfe_workspace.infra[0].id
  key          = "TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE"
  value        = var.hcp_aws_audience
  category     = "env"
  description  = "Audience claim in the workload identity token."
}
