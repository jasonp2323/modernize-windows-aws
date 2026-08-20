output "application_client_ids" {
  description = "Entra ID application (client) IDs, one per stack."
  value       = { for k, v in azuread_application.this : k => v.client_id }
}

output "group_object_ids" {
  description = "Entra ID group object IDs whose members can stream each stack."
  value       = { for k, v in azuread_group.this : k => v.object_id }
}

output "group_display_names" {
  description = "Entra ID group display names."
  value       = { for k, v in azuread_group.this : k => v.display_name }
}

output "saml_provider_arns" {
  description = "IAM SAML identity provider ARNs."
  value       = { for k, v in aws_iam_saml_provider.this : k => v.arn }
}

output "federated_role_arns" {
  description = "IAM roles federated users assume to stream each stack."
  value       = { for k, v in aws_iam_role.federated : k => v.arn }
}

output "user_access_urls" {
  description = "Sign-in URLs to hand to users (the Entra ID application access URL)."
  value = {
    for k, v in azuread_application.this :
    k => "https://myapplications.microsoft.com/?tenantid=${var.tenant_id}"
  }
}

output "relay_states" {
  description = "Relay state configured on each Entra application."
  value       = { for k, v in var.stacks : k => "${local.relay_state_endpoint}?stack=${v.stack_name}&accountId=${data.aws_caller_identity.current.account_id}" }
}
