##############################################################################
# Management and Entra Connect servers
##############################################################################

data "aws_ssm_parameter" "windows_ami" {
  name = var.windows_ami_ssm_parameter
}

resource "aws_security_group" "management" {
  name        = "${var.name_prefix}-management"
  description = "Management and identity servers"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-management" })
}

resource "aws_vpc_security_group_ingress_rule" "rdp" {
  for_each = toset(var.allowed_rdp_cidrs)

  security_group_id = aws_security_group.management.id
  description       = "RDP"
  cidr_ipv4         = each.value
  from_port         = 3389
  to_port           = 3389
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "management_all" {
  security_group_id = aws_security_group.management.id
  description       = "All egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "management" {
  ami                    = data.aws_ssm_parameter.windows_ami.value
  instance_type          = var.management_instance_type
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.management.id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_pair_name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 60
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, var.domain_join_tags, {
    Name = "${var.name_prefix}-mgmt-01"
    Role = "management"
  })

  volume_tags = merge(var.tags, { Name = "${var.name_prefix}-mgmt-01" })

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "entra_connect" {
  count = var.enable_entra_connect_server ? 1 : 0

  ami                    = data.aws_ssm_parameter.windows_ami.value
  instance_type          = var.entra_connect_instance_type
  subnet_id              = var.subnet_ids[length(var.subnet_ids) > 1 ? 1 : 0]
  vpc_security_group_ids = [aws_security_group.management.id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_pair_name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 80
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, var.domain_join_tags, {
    Name = "${var.name_prefix}-entra-connect-01"
    Role = "entra-connect"
  })

  volume_tags = merge(var.tags, { Name = "${var.name_prefix}-entra-connect-01" })

  lifecycle {
    ignore_changes = [ami]
  }
}

##############################################################################
# State Manager associations
#
# The schedule is a safety net rather than a cron job: both scripts are
# idempotent, and re-running them heals drift and covers the case where the
# association fires before the seamless domain join has finished.
##############################################################################

resource "aws_ssm_association" "domain_config" {
  name             = aws_ssm_document.run_as_domain_admin.name
  association_name = "${var.name_prefix}-domain-config"

  schedule_expression         = var.association_schedule_expression
  apply_only_at_cron_interval = false
  compliance_severity         = "CRITICAL"

  parameters = {
    WrapperS3Uri = "s3://${var.scripts_bucket}/${aws_s3_object.scripts["wrapper"].key}"
    ScriptS3Uri  = "s3://${var.scripts_bucket}/${aws_s3_object.scripts["domain_config"].key}"
    ConfigB64    = base64encode(local.domain_config_json)
    SecretId     = var.admin_secret_arn
    RegionName   = data.aws_region.current.region
    TaskName     = "${var.name_prefix}-domain-config"
    Version      = local.scripts_version
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.management.id]
  }

  wait_for_success_timeout_seconds = var.wait_for_association_success ? 1800 : null
}

resource "aws_ssm_association" "entra_connect" {
  count = var.enable_entra_connect_server ? 1 : 0

  name             = aws_ssm_document.run_as_domain_admin.name
  association_name = "${var.name_prefix}-entra-connect-prep"

  schedule_expression         = var.association_schedule_expression
  apply_only_at_cron_interval = false
  compliance_severity         = "MEDIUM"

  parameters = {
    WrapperS3Uri = "s3://${var.scripts_bucket}/${aws_s3_object.scripts["wrapper"].key}"
    ScriptS3Uri  = "s3://${var.scripts_bucket}/${aws_s3_object.scripts["entra_connect"].key}"
    ConfigB64    = base64encode(local.entra_config_json)
    SecretId     = var.admin_secret_arn
    RegionName   = data.aws_region.current.region
    TaskName     = "${var.name_prefix}-entra-connect"
    Version      = local.scripts_version
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.entra_connect[0].id]
  }

  # The connector account and its permissions depend on the OU tree the domain
  # configuration creates.
  depends_on = [aws_ssm_association.domain_config]
}
