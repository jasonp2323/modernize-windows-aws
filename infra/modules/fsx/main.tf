##############################################################################
# FSx for Windows File Server
#
# One instance of this module = one file system. The stack creates two:
#   - "shares"   : departmental/application SMB shares
#   - "profiles" : FSLogix profile and Office containers, deliberately on a
#                  separate file system so profile I/O, backups, throughput and
#                  blast radius are isolated from general file shares.
#
# The file system joins AWS Managed Microsoft AD directly - no domain join
# scripting, and AWS keeps the computer object healthy.
##############################################################################

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-fsx-${var.role}"
  description = "FSx for Windows File Server - ${var.role}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-fsx-${var.role}" })
}

locals {
  # SMB plus the RPC endpoint mapper and dynamic range FSx uses for remote
  # management (New-FSxSmbShare over PowerShell remoting).
  client_ports = {
    smb           = { from = 445, to = 445, protocol = "tcp", description = "SMB" }
    winrm         = { from = 5985, to = 5985, protocol = "tcp", description = "FSx remote PowerShell" }
    rpc_epm       = { from = 135, to = 135, protocol = "tcp", description = "RPC endpoint mapper" }
    rpc_ephemeral = { from = 49152, to = 65535, protocol = "tcp", description = "RPC dynamic ports" }
  }

  client_rules = {
    for pair in setproduct(keys(local.client_ports), var.client_cidrs) :
    "${pair[0]}-${replace(pair[1], "/", "_")}" => {
      port = local.client_ports[pair[0]]
      cidr = pair[1]
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = local.client_rules

  security_group_id = aws_security_group.this.id
  description       = each.value.port.description
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port.from
  to_port           = each.value.port.to
  ip_protocol       = each.value.port.protocol
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_fsx_windows_file_system" "this" {
  active_directory_id = var.directory_id
  deployment_type     = var.deployment_type

  storage_capacity    = var.storage_capacity
  storage_type        = var.storage_type
  throughput_capacity = var.throughput_capacity

  subnet_ids          = var.deployment_type == "MULTI_AZ_1" ? slice(var.subnet_ids, 0, 2) : [var.subnet_ids[0]]
  preferred_subnet_id = var.deployment_type == "MULTI_AZ_1" ? var.subnet_ids[0] : null
  security_group_ids  = [aws_security_group.this.id]

  aliases = var.aliases

  automatic_backup_retention_days   = var.backup_retention_days
  daily_automatic_backup_start_time = var.daily_backup_start_time
  weekly_maintenance_start_time     = var.weekly_maintenance_start_time
  copy_tags_to_backups              = true
  skip_final_backup                 = var.skip_final_backup

  dynamic "audit_log_configuration" {
    for_each = var.audit_log_destination_arn == null ? [] : [1]

    content {
      audit_log_destination             = var.audit_log_destination_arn
      file_access_audit_log_level       = "SUCCESS_AND_FAILURE"
      file_share_access_audit_log_level = "SUCCESS_AND_FAILURE"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-fsx-${var.role}"
    Role = var.role
  })
}
