##############################################################################
# Network
##############################################################################

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "subnets" {
  description = "Subnet IDs by tier."
  value = {
    public = module.network.public_subnet_ids
    app    = module.network.app_subnet_ids
    data   = module.network.data_subnet_ids
    stream = module.network.stream_subnet_ids
  }
}

##############################################################################
# Directory
##############################################################################

output "directory" {
  description = "AWS Managed Microsoft AD details."
  value = {
    id               = module.directory.directory_id
    domain_name      = module.directory.directory_name
    netbios_name     = module.directory.netbios_name
    dns_ip_addresses = module.directory.dns_ip_addresses
    delegated_ou     = local.ou_root
  }
}

output "directory_secrets" {
  description = "Where the domain credentials live. Read them with `aws secretsmanager get-secret-value`."
  value = {
    admin           = module.directory.admin_secret_arn
    service_account = module.directory.service_account_secret_arn
  }
}

##############################################################################
# File storage
##############################################################################

output "file_shares" {
  description = "UNC paths for the file shares and FSLogix containers."
  value = {
    company_share  = "\\\\${local.shares_host}\\company"
    apps_share     = "\\\\${local.shares_host}\\apps"
    profiles_share = local.fslogix.ProfileUnc
    office_share   = var.fslogix_enable_office_container ? local.fslogix.OfficeUnc : null
  }
}

output "fsx_file_systems" {
  description = "FSx for Windows File Server file systems."
  value = {
    shares = {
      id       = module.fsx_shares.id
      dns_name = module.fsx_shares.dns_name
      alias    = try(local.shares_alias[0], null)
    }
    profiles = {
      id       = module.fsx_profiles.id
      dns_name = module.fsx_profiles.dns_name
      alias    = try(local.profiles_alias[0], null)
    }
  }
}

##############################################################################
# Application tier
##############################################################################

output "application_tier" {
  description = "Application servers and their internal load balancer."
  value = {
    instance_ids       = module.app_tier.instance_ids
    private_ips        = module.app_tier.private_ips
    load_balancer      = module.app_tier.load_balancer_dns_name
    management_host    = module.management.management_instance_id
    entra_connect_host = module.management.entra_connect_instance_id
  }
}

output "sql_server" {
  description = "RDS for SQL Server, domain joined for Windows Authentication."
  value = {
    endpoint           = module.sql.endpoint
    identifier         = module.sql.identifier
    master_user_secret = module.sql.master_user_secret_arn
  }
}

##############################################################################
# Streaming
##############################################################################

output "streaming" {
  description = "WorkSpaces Applications image builders, fleets and stacks."
  value = {
    image_builders = module.streaming.image_builder_names
    fleets         = module.streaming.fleet_names
    stacks         = module.streaming.stack_names
  }
}

output "entra_federation" {
  description = "Entra ID applications and the AWS roles they map to."
  value = {
    applications = try(module.entra_saml[0].application_client_ids, {})
    groups       = try(module.entra_saml[0].group_display_names, {})
    roles        = try(module.entra_saml[0].federated_role_arns, {})
    relay_states = try(module.entra_saml[0].relay_states, {})
  }
}

##############################################################################
# Operations
##############################################################################

output "automation" {
  description = "Where the domain automation lives and how to watch it."
  value = {
    scripts_bucket    = aws_s3_bucket.automation.id
    ssm_document      = module.management.ssm_document_name
    association_id    = module.management.domain_config_association_id
    image_prep_script = module.management.image_prep_script_uri
    management_log    = "C:\\ProgramData\\mwa\\logs on ${module.management.management_instance_id}"
  }
}

output "next_steps" {
  description = "What to do after this apply."
  value = compact([
    "Watch the domain build-out: aws ssm describe-association-executions --association-id ${module.management.domain_config_association_id}",
    "Connect to the management server with Fleet Manager or Session Manager: ${module.management.management_instance_id}",
    var.enable_image_builders ? "Image builders are running. Connect from the WorkSpaces Applications console, run ${module.management.image_prep_script_uri}, then build the images." : "Set enable_image_builders = true when you are ready to build the streaming images.",
    var.enable_streaming_fleets ? "Fleets are live. Entitle users through the Entra ID groups." : "Set enable_streaming_fleets = true once the images exist and their names are in tfvars.",
    var.enable_entra_connect_server ? "Finish Entra Connect Sync interactively on ${module.management.entra_connect_instance_id}." : null,
  ])
}
