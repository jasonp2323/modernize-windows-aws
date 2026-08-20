output "id" {
  description = "FSx file system ID."
  value       = aws_fsx_windows_file_system.this.id
}

output "dns_name" {
  description = "FSx file system DNS name."
  value       = aws_fsx_windows_file_system.this.dns_name
}

output "preferred_file_server_ip" {
  description = "Preferred file server IP address."
  value       = aws_fsx_windows_file_system.this.preferred_file_server_ip
}

output "security_group_id" {
  description = "Security group protecting the file system."
  value       = aws_security_group.this.id
}

output "aliases" {
  description = "DNS aliases configured on the file system."
  value       = var.aliases
}

output "unc_host" {
  description = "Host name to use in UNC paths - the first alias when one is set, otherwise the FSx DNS name."
  value       = length(var.aliases) > 0 ? var.aliases[0] : aws_fsx_windows_file_system.this.dns_name
}
