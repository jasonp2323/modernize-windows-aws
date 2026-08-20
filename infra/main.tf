##############################################################################
# Modern Windows environment on AWS
#
# Applied in three stages so image creation - the one step that cannot be
# automated end to end - has a natural place to happen:
#
#   Stage 1  default variables. Network, directory, file systems, application
#            tier, database, management automation, Entra Connect server.
#   Stage 2  enable_image_builders = true. Build the two streaming images with
#            Image Assistant, then record their names.
#   Stage 3  enable_streaming_fleets = true (+ enable_entra_saml). Fleets,
#            stacks and Entra ID federation.
##############################################################################

data "aws_caller_identity" "current" {}

module "network" {
  source = "./modules/network"

  name_prefix          = var.name_prefix
  tags                 = local.tags
  vpc_cidr             = var.vpc_cidr
  az_count             = var.az_count
  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints
}

##############################################################################
# Domain controllers
##############################################################################

module "directory" {
  source = "./modules/directory"

  name_prefix          = var.name_prefix
  tags                 = local.tags
  vpc_id               = module.network.vpc_id
  subnet_ids           = module.network.data_subnet_ids
  domain_name          = var.domain_name
  domain_netbios_name  = var.domain_netbios_name
  edition              = var.directory_edition
  service_account_name = var.directory_service_account_name
  manage_dhcp_options  = true
}

##############################################################################
# Automation bucket
#
# Lives here rather than in the management module so the instance profile can
# be granted access without a dependency cycle.
##############################################################################

resource "aws_s3_bucket" "automation" {
  bucket        = "${var.name_prefix}-automation-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-automation" })
}

resource "aws_s3_bucket_public_access_block" "automation" {
  bucket                  = aws_s3_bucket.automation.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "automation" {
  bucket = aws_s3_bucket.automation.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "automation" {
  bucket = aws_s3_bucket.automation.id

  versioning_configuration {
    status = "Enabled"
  }
}

##############################################################################
# Domain join
##############################################################################

module "domain_join" {
  source = "./modules/domain-join"

  name_prefix      = var.name_prefix
  tags             = local.tags
  directory_id     = module.directory.directory_id
  directory_name   = module.directory.directory_name
  dns_ip_addresses = module.directory.dns_ip_addresses

  readable_secret_arns = [
    module.directory.admin_secret_arn,
    module.directory.service_account_secret_arn,
  ]
  scripts_bucket_arn = aws_s3_bucket.automation.arn
}

##############################################################################
# File systems
##############################################################################

module "fsx_shares" {
  source = "./modules/fsx"

  name_prefix         = var.name_prefix
  tags                = local.tags
  role                = "shares"
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.data_subnet_ids
  directory_id        = module.directory.directory_id
  client_cidrs        = local.workload_cidrs
  deployment_type     = var.fsx_deployment_type
  storage_capacity    = var.fsx_shares_storage_capacity
  throughput_capacity = var.fsx_shares_throughput_capacity
  aliases             = local.shares_alias
}

module "fsx_profiles" {
  source = "./modules/fsx"

  name_prefix         = var.name_prefix
  tags                = local.tags
  role                = "profiles"
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.data_subnet_ids
  directory_id        = module.directory.directory_id
  client_cidrs        = local.workload_cidrs
  deployment_type     = var.fsx_deployment_type
  storage_capacity    = var.fsx_profiles_storage_capacity
  throughput_capacity = var.fsx_profiles_throughput_capacity
  aliases             = local.profiles_alias
}

##############################################################################
# Management and domain build-out
##############################################################################

module "management" {
  source = "./modules/management"

  name_prefix           = var.name_prefix
  tags                  = local.tags
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.app_subnet_ids
  scripts_bucket        = aws_s3_bucket.automation.id
  instance_profile_name = module.domain_join.instance_profile_name
  domain_join_tags      = module.domain_join.join_tags
  key_pair_name         = var.key_pair_name
  allowed_rdp_cidrs     = var.admin_cidrs

  windows_ami_ssm_parameter = var.windows_ami_ssm_parameter
  management_instance_type  = var.management_instance_type

  domain_name                = var.domain_name
  domain_netbios_name        = var.domain_netbios_name
  delegated_ou_dn            = local.ou_root
  admin_secret_arn           = module.directory.admin_secret_arn
  service_account_secret_arn = module.directory.service_account_secret_arn

  organizational_units = local.ou_paths
  security_groups      = local.directory_groups
  join_delegation_ou_dns = [
    local.ou.app_fleet,
    local.ou.desktop_fleet,
    local.ou.image_builders,
  ]

  file_systems = local.file_systems
  fslogix      = local.fslogix

  enable_entra_connect_server = var.enable_entra_connect_server
  entra_connect_instance_type = var.entra_connect_instance_type
  entra_upn_suffix            = var.entra_upn_suffix

  association_schedule_expression = var.domain_automation_schedule
  wait_for_association_success    = var.wait_for_domain_automation
}

##############################################################################
# Application tier and database
##############################################################################

module "sql" {
  source = "./modules/sql-rds"

  name_prefix  = var.name_prefix
  tags         = local.tags
  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.data_subnet_ids
  directory_id = module.directory.directory_id
  client_cidrs = local.workload_cidrs

  engine                 = var.sql_engine
  engine_version         = var.sql_engine_version
  parameter_group_family = var.sql_parameter_group_family
  instance_class         = var.sql_instance_class
  allocated_storage      = var.sql_allocated_storage
  multi_az               = var.sql_multi_az
}

module "app_tier" {
  source = "./modules/app-tier"

  name_prefix           = var.name_prefix
  tags                  = local.tags
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.app_subnet_ids
  instance_profile_name = module.domain_join.instance_profile_name
  domain_join_tags      = module.domain_join.join_tags
  key_pair_name         = var.key_pair_name

  instance_count            = var.app_server_count
  instance_type             = var.app_server_instance_type
  windows_ami_ssm_parameter = var.windows_ami_ssm_parameter
  client_cidrs              = local.workload_cidrs
  admin_cidrs               = var.admin_cidrs
  create_load_balancer      = var.create_app_load_balancer
  sql_endpoint              = module.sql.endpoint
}

##############################################################################
# WorkSpaces Applications
##############################################################################

module "streaming" {
  source = "./modules/workspaces-applications"

  name_prefix = var.name_prefix
  tags        = local.tags
  vpc_id      = module.network.vpc_id
  subnet_ids  = module.network.stream_subnet_ids

  directory_name = var.domain_name
  organizational_unit_distinguished_names = [
    local.ou.app_fleet,
    local.ou.desktop_fleet,
    local.ou.image_builders,
  ]
  service_account_name     = "${var.domain_netbios_name}\\${var.directory_service_account_name}"
  service_account_password = module.directory.service_account_password

  enable_directory_config = var.enable_image_builders || var.enable_streaming_fleets
  base_image_name         = var.appstream_base_image_name
  enable_image_builders   = var.enable_image_builders
  image_builders          = local.image_builders

  enable_fleets      = var.enable_streaming_fleets
  fleets             = local.fleets
  enable_autoscaling = var.enable_streaming_autoscaling

  # The service account and the streaming OUs are created by the management
  # automation, not by Terraform. Apply with wait_for_domain_automation = true
  # on the run that first enables streaming.
  depends_on = [module.management]
}

##############################################################################
# Entra ID federation
##############################################################################

module "entra_saml" {
  source = "./modules/entra-saml"
  count  = var.enable_entra_saml ? 1 : 0

  name_prefix = var.name_prefix
  tags        = local.tags
  tenant_id   = var.entra_tenant_id

  stacks = {
    for key, fleet in local.fleets :
    key => {
      stack_name   = module.streaming.stack_names[key]
      stack_arn    = module.streaming.stack_arns[key]
      display_name = fleet.display_name
    }
    if var.enable_streaming_fleets
  }

  session_duration_seconds = var.entra_saml_session_duration_seconds
}
