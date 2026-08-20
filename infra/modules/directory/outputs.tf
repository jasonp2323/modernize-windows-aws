output "directory_id" {
  description = "Directory ID (d-xxxxxxxxxx)."
  value       = aws_directory_service_directory.this.id
}

output "directory_name" {
  description = "Fully qualified domain name."
  value       = aws_directory_service_directory.this.name
}

output "netbios_name" {
  description = "NetBIOS domain name."
  value       = aws_directory_service_directory.this.short_name
}

output "dns_ip_addresses" {
  description = "Domain controller DNS addresses."
  value       = tolist(aws_directory_service_directory.this.dns_ip_addresses)
}

output "security_group_id" {
  description = "Security group AWS created for the domain controllers."
  value       = aws_directory_service_directory.this.security_group_id
}

output "admin_secret_arn" {
  description = "Secrets Manager ARN holding the delegated Admin credentials."
  value       = aws_secretsmanager_secret.admin.arn
}

output "service_account_secret_arn" {
  description = "Secrets Manager ARN holding the domain service account credentials."
  value       = aws_secretsmanager_secret.service_account.arn
}

output "service_account_name" {
  description = "sAMAccountName of the domain service account."
  value       = var.service_account_name
}

output "service_account_password" {
  description = "Password generated for the domain service account."
  value       = random_password.service_account.result
  sensitive   = true
}

output "admin_password" {
  description = "Password for the delegated Admin account."
  value       = local.admin_password
  sensitive   = true
}

output "base_dn" {
  description = "Base distinguished name of the domain."
  value       = join(",", [for part in split(".", var.domain_name) : "DC=${part}"])
}

output "delegated_ou_dn" {
  description = "Distinguished name of the OU AWS delegates to you inside the managed domain."
  value       = "OU=${var.domain_netbios_name},${join(",", [for part in split(".", var.domain_name) : "DC=${part}"])}"
}
