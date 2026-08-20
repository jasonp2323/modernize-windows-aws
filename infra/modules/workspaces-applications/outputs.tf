output "security_group_id" {
  description = "Security group attached to fleet and image builder ENIs."
  value       = aws_security_group.fleet.id
}

output "directory_config_name" {
  description = "Directory config registered with WorkSpaces Applications."
  value       = aws_appstream_directory_config.this.directory_name
}

output "image_builder_names" {
  description = "Image builder names."
  value       = { for k, v in aws_appstream_image_builder.this : k => v.name }
}

output "fleet_names" {
  description = "Fleet names."
  value       = { for k, v in aws_appstream_fleet.this : k => v.name }
}

output "stack_names" {
  description = "Stack names, which are also the SAML relay state identifiers."
  value       = { for k, v in aws_appstream_stack.this : k => v.name }
}

output "stack_arns" {
  description = "Stack ARNs, used in the IAM federation policy."
  value       = { for k, v in aws_appstream_stack.this : k => v.arn }
}
