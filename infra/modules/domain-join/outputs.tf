output "instance_profile_name" {
  description = "Instance profile to attach to Windows instances that should join the domain."
  value       = aws_iam_instance_profile.instance.name
}

output "instance_profile_arn" {
  description = "Instance profile ARN."
  value       = aws_iam_instance_profile.instance.arn
}

output "role_name" {
  description = "IAM role name behind the instance profile."
  value       = aws_iam_role.instance.name
}

output "role_arn" {
  description = "IAM role ARN behind the instance profile."
  value       = aws_iam_role.instance.arn
}

output "join_tags" {
  description = "Tags an instance must carry to be picked up by the domain join association."
  value       = { (var.join_tag_key) = var.join_tag_value }
}
