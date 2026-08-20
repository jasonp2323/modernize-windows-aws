##############################################################################
# RDS for SQL Server, joined to AWS Managed Microsoft AD
#
# RDS keeps SQL Authentication for the master user (that is how RDS works -
# mixed mode) and adds Windows Authentication for domain principals. Logins for
# domain groups still have to be created inside SQL Server; see the note in
# docs/OPERATIONS.md.
##############################################################################

data "aws_partition" "current" {}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-sql"
  description = "RDS for SQL Server"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sql" })
}

resource "aws_vpc_security_group_ingress_rule" "sql_from_cidrs" {
  for_each = toset(var.client_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "SQL Server from application and management tiers"
  cidr_ipv4         = each.value
  from_port         = 1433
  to_port           = 1433
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sql_from_sgs" {
  for_each = toset(var.client_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "SQL Server from an allowed security group"
  referenced_security_group_id = each.value
  from_port                    = 1433
  to_port                      = 1433
  ip_protocol                  = "tcp"
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-sql"
  description = "Data tier subnets for RDS for SQL Server"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-sql" })
}

##############################################################################
# Directory access role
##############################################################################

data "aws_iam_policy_document" "rds_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "directory" {
  name               = "${var.name_prefix}-rds-directory"
  description        = "Lets RDS join SQL Server instances to AWS Managed Microsoft AD."
  assume_role_policy = data.aws_iam_policy_document.rds_assume.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-directory" })
}

resource "aws_iam_role_policy_attachment" "directory" {
  role       = aws_iam_role.directory.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSDirectoryServiceAccess"
}

##############################################################################
# Instance
##############################################################################

resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-sql"
  family      = var.parameter_group_family
  description = "Parameter group for ${var.name_prefix} SQL Server"

  tags = merge(var.tags, { Name = "${var.name_prefix}-sql" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-sql"
  engine         = var.engine
  engine_version = var.engine_version
  license_model  = "license-included"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id

  username = var.master_username
  # RDS creates and rotates the master password in Secrets Manager, so it never
  # lands in Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  multi_az               = var.multi_az
  publicly_accessible    = false
  port                   = 1433

  # Windows Authentication against AWS Managed Microsoft AD.
  domain               = var.directory_id
  domain_iam_role_name = aws_iam_role.directory.name

  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-sql-final"

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  timezone                        = var.timezone

  tags = merge(var.tags, { Name = "${var.name_prefix}-sql" })
}
