output "run_role_arn" {
  description = "Set this as TFC_AWS_RUN_ROLE_ARN on the HCP Terraform workspace."
  value       = aws_iam_role.run.arn
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider trusted for HCP Terraform workload identity."
  value       = local.oidc_provider_arn
}

output "allowed_oidc_subjects" {
  description = "Exact subjects allowed to assume the run role."
  value       = local.allowed_subjects
}

output "workspace_environment_variables" {
  description = "Environment variables to set on the HCP Terraform workspace when it is not managed from here."
  value = {
    TFC_AWS_PROVIDER_AUTH              = "true"
    TFC_AWS_RUN_ROLE_ARN               = aws_iam_role.run.arn
    TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE = var.hcp_aws_audience
  }
}

output "workspace_id" {
  description = "ID of the managed HCP Terraform workspace, when manage_hcp_workspace = true."
  value       = try(tfe_workspace.infra[0].id, null)
}
