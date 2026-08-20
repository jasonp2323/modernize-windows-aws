output "instance_ids" {
  description = "Application server instance IDs."
  value       = aws_instance.app[*].id
}

output "private_ips" {
  description = "Application server private IPs."
  value       = aws_instance.app[*].private_ip
}

output "security_group_id" {
  description = "Security group protecting the application servers."
  value       = aws_security_group.app.id
}

output "load_balancer_dns_name" {
  description = "Internal load balancer DNS name, when created."
  value       = try(aws_lb.app[0].dns_name, null)
}
