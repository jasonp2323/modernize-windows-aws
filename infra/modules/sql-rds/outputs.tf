output "endpoint" {
  description = "Connection endpoint, host:port."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Connection host name."
  value       = aws_db_instance.this.address
}

output "identifier" {
  description = "DB instance identifier."
  value       = aws_db_instance.this.identifier
}

output "security_group_id" {
  description = "Security group protecting the database."
  value       = aws_security_group.this.id
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master password."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "directory_role_name" {
  description = "IAM role RDS uses to join the domain."
  value       = aws_iam_role.directory.name
}
