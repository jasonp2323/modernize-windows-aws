##############################################################################
# AWS Managed Microsoft AD
#
# This is the domain controller tier. AWS runs two DCs across two AZs, patches
# them, backs them up and gives you a delegated "Admin" account instead of a
# real Domain Admin. Every other service in this stack joins this domain:
#   - EC2 application/management servers via SSM seamless domain join
#   - FSx for Windows File Server natively
#   - RDS for SQL Server via the RDS directory integration
#   - WorkSpaces Applications fleets via AppStream directory config
##############################################################################

resource "random_password" "admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#$%^&*()-_=+[]{}"
}

locals {
  admin_password = coalesce(var.admin_password, random_password.admin.result)
}

resource "aws_directory_service_directory" "this" {
  name        = var.domain_name
  short_name  = var.domain_netbios_name
  password    = local.admin_password
  type        = "MicrosoftAD"
  edition     = var.edition
  description = "Managed Microsoft AD for ${var.name_prefix}"

  vpc_settings {
    vpc_id     = var.vpc_id
    subnet_ids = slice(var.subnet_ids, 0, 2)
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ad" })
}

##############################################################################
# DHCP options
#
# Points the whole VPC at the domain controllers for DNS so that domain join,
# Kerberos SRV lookups and FSx DNS aliases all resolve. Only the domain
# controllers are listed: AWS Managed Microsoft AD forwards anything it is not
# authoritative for to the Amazon-provided resolver, so public names and the
# private DNS names of VPC endpoints still resolve.
##############################################################################

resource "aws_vpc_dhcp_options" "this" {
  count = var.manage_dhcp_options ? 1 : 0

  domain_name         = var.domain_name
  domain_name_servers = tolist(aws_directory_service_directory.this.dns_ip_addresses)
  ntp_servers         = ["169.254.169.123"]

  tags = merge(var.tags, { Name = "${var.name_prefix}-dhcp" })
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = var.manage_dhcp_options ? 1 : 0

  vpc_id          = var.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

##############################################################################
# Credentials
#
# The delegated admin password and the domain service account credentials used
# by FSLogix automation, WorkSpaces Applications directory config and Entra
# Connect all live in Secrets Manager. Nothing reads them from state at run
# time except Terraform itself.
##############################################################################

resource "aws_secretsmanager_secret" "admin" {
  name                    = "${var.name_prefix}/ad/admin"
  description             = "Delegated administrator for ${var.domain_name} (${var.domain_netbios_name}\\Admin)."
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-ad-admin" })
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({
    domain          = var.domain_name
    netbios         = var.domain_netbios_name
    username        = "Admin"
    upn             = "Admin@${var.domain_name}"
    domain_username = "${var.domain_netbios_name}\\Admin"
    password        = local.admin_password
  })
}

# Least-privilege service account used for:
#   - joining WorkSpaces Applications fleets/image builders to the domain
#   - Entra Connect Sync AD DS connector account (optional)
# The AD object itself is created by the management server automation; this
# resource only holds the password Terraform generated for it.
resource "random_password" "service_account" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#$%^&*()-_=+"
}

resource "aws_secretsmanager_secret" "service_account" {
  name                    = "${var.name_prefix}/ad/svc-join"
  description             = "Domain service account used for directory join and directory automation."
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-ad-svc-join" })
}

resource "aws_secretsmanager_secret_version" "service_account" {
  secret_id = aws_secretsmanager_secret.service_account.id
  secret_string = jsonencode({
    domain          = var.domain_name
    netbios         = var.domain_netbios_name
    username        = var.service_account_name
    upn             = "${var.service_account_name}@${var.domain_name}"
    domain_username = "${var.domain_netbios_name}\\${var.service_account_name}"
    password        = random_password.service_account.result
  })
}
