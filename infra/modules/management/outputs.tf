output "management_instance_id" {
  description = "Management server instance ID."
  value       = aws_instance.management.id
}

output "management_private_ip" {
  description = "Management server private IP."
  value       = aws_instance.management.private_ip
}

output "entra_connect_instance_id" {
  description = "Entra Connect server instance ID, when deployed."
  value       = try(aws_instance.entra_connect[0].id, null)
}

output "security_group_id" {
  description = "Security group for the management servers."
  value       = aws_security_group.management.id
}

output "image_prep_script_uri" {
  description = "S3 URI of the image builder preparation script."
  value       = "s3://${var.scripts_bucket}/${aws_s3_object.scripts["image_prep"].key}"
}

output "ssm_document_name" {
  description = "SSM document that runs automation as the delegated admin."
  value       = aws_ssm_document.run_as_domain_admin.name
}

output "domain_config_association_id" {
  description = "State Manager association that builds the domain."
  value       = aws_ssm_association.domain_config.association_id
}
