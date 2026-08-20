locals {
  tags = merge({
    Project     = "modernize-windows-aws"
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
    Workspace   = terraform.workspace
  }, var.additional_tags)

  ##########################################################################
  # Directory layout
  #
  # AWS Managed Microsoft AD gives you a delegated OU named after the NetBIOS
  # name. Everything this stack creates lives under it - you never get, and
  # never need, rights at the domain root.
  ##########################################################################

  base_dn = join(",", [for part in split(".", var.domain_name) : "DC=${part}"])
  ou_root = "OU=${var.domain_netbios_name},${local.base_dn}"

  ou_paths = [
    "Groups",
    "Users",
    "ServiceAccounts",
    "Servers",
    "Servers/Application",
    "Servers/Management",
    "Streaming",
    "Streaming/AppFleet",
    "Streaming/DesktopFleet",
    "Streaming/ImageBuilders",
  ]

  ou = {
    groups           = "OU=Groups,${local.ou_root}"
    users            = "OU=Users,${local.ou_root}"
    service_accounts = "OU=ServiceAccounts,${local.ou_root}"
    servers_app      = "OU=Application,OU=Servers,${local.ou_root}"
    servers_mgmt     = "OU=Management,OU=Servers,${local.ou_root}"
    app_fleet        = "OU=AppFleet,OU=Streaming,${local.ou_root}"
    desktop_fleet    = "OU=DesktopFleet,OU=Streaming,${local.ou_root}"
    image_builders   = "OU=ImageBuilders,OU=Streaming,${local.ou_root}"
  }

  directory_groups = [
    { Name = "FSLogix-Users", Description = "Users who receive an FSLogix profile container." },
    { Name = "RemoteApp-Users", Description = "Entitled to the published application stack." },
    { Name = "VirtualDesktop-Users", Description = "Entitled to the non-persistent desktop stack." },
    { Name = "FileShare-Company-RW", Description = "Read/write on the company file share." },
    { Name = "SQL-AppAdmins", Description = "Windows Authentication administrators on the application database." },
  ]

  ##########################################################################
  # File shares
  ##########################################################################

  shares_alias   = var.fsx_use_dns_aliases ? ["files.${var.domain_name}"] : []
  profiles_alias = var.fsx_use_dns_aliases ? ["profiles.${var.domain_name}"] : []

  shares_host   = var.fsx_use_dns_aliases ? local.shares_alias[0] : module.fsx_shares.dns_name
  profiles_host = var.fsx_use_dns_aliases ? local.profiles_alias[0] : module.fsx_profiles.dns_name

  admin_principal   = "${var.domain_netbios_name}\\Domain Admins"
  fslogix_principal = "${var.domain_netbios_name}\\FSLogix-Users"
  company_principal = "${var.domain_netbios_name}\\FileShare-Company-RW"
  users_principal   = "${var.domain_netbios_name}\\Domain Users"

  file_systems = [
    {
      DnsName = module.fsx_shares.dns_name
      Purpose = "shares"
      Aliases = local.shares_alias
      Shares = [
        {
          Name         = "company"
          Folder       = "company"
          Description  = "General purpose company file share."
          FullAccess   = [local.admin_principal]
          ChangeAccess = [local.company_principal]
        },
        {
          Name         = "apps"
          Folder       = "apps"
          Description  = "Application packages and shared configuration."
          FullAccess   = [local.admin_principal]
          ChangeAccess = [local.users_principal]
        },
      ]
    },
    {
      DnsName = module.fsx_profiles.dns_name
      Purpose = "fslogix"
      Aliases = local.profiles_alias
      Shares = concat([
        {
          Name         = "profiles"
          Folder       = "profiles"
          Description  = "FSLogix profile containers."
          FullAccess   = [local.admin_principal]
          ChangeAccess = [local.fslogix_principal]
        },
        ], var.fslogix_enable_office_container ? [
        {
          Name         = "odfc"
          Folder       = "odfc"
          Description  = "FSLogix Office containers."
          FullAccess   = [local.admin_principal]
          ChangeAccess = [local.fslogix_principal]
        },
      ] : [])
    },
  ]

  fslogix = {
    GpoName               = "FSLogix - Profile Containers"
    ProfileUnc            = "\\\\${local.profiles_host}\\profiles"
    OfficeUnc             = "\\\\${local.profiles_host}\\odfc"
    SizeInMBs             = var.fslogix_container_size_mb
    EnableOfficeContainer = var.fslogix_enable_office_container
    LinkOus               = [local.ou.app_fleet, local.ou.desktop_fleet]
  }

  ##########################################################################
  # Streaming
  ##########################################################################

  image_builders = {
    app = {
      display_name                           = "Published application image builder"
      description                            = "Builds the image for the single-application fleet."
      instance_type                          = var.appstream_image_builder_instance_type
      organizational_unit_distinguished_name = local.ou.image_builders
    }
    desktop = {
      display_name                           = "Desktop image builder"
      description                            = "Builds the image for the non-persistent desktop fleet."
      instance_type                          = var.appstream_image_builder_instance_type
      organizational_unit_distinguished_name = local.ou.image_builders
    }
  }

  fleets = {
    app = {
      display_name                           = "Published Application"
      description                            = "Single application streamed RemoteApp style."
      image_name                             = var.appstream_app_image_name
      instance_type                          = var.appstream_app_fleet.instance_type
      fleet_type                             = var.appstream_app_fleet.fleet_type
      stream_view                            = "APP"
      desired_instances                      = var.appstream_app_fleet.desired_instances
      min_capacity                           = var.appstream_app_fleet.min_capacity
      max_capacity                           = var.appstream_app_fleet.max_capacity
      max_user_duration_in_seconds           = var.appstream_app_fleet.max_user_duration_in_seconds
      disconnect_timeout_in_seconds          = var.appstream_app_fleet.disconnect_timeout_in_seconds
      idle_disconnect_timeout_in_seconds     = var.appstream_app_fleet.idle_disconnect_timeout_in_seconds
      organizational_unit_distinguished_name = local.ou.app_fleet
    }
    desktop = {
      display_name                           = "Virtual Desktop"
      description                            = "Non-persistent Windows desktop with an FSLogix profile."
      image_name                             = var.appstream_desktop_image_name
      instance_type                          = var.appstream_desktop_fleet.instance_type
      fleet_type                             = var.appstream_desktop_fleet.fleet_type
      stream_view                            = "DESKTOP"
      desired_instances                      = var.appstream_desktop_fleet.desired_instances
      min_capacity                           = var.appstream_desktop_fleet.min_capacity
      max_capacity                           = var.appstream_desktop_fleet.max_capacity
      max_user_duration_in_seconds           = var.appstream_desktop_fleet.max_user_duration_in_seconds
      disconnect_timeout_in_seconds          = var.appstream_desktop_fleet.disconnect_timeout_in_seconds
      idle_disconnect_timeout_in_seconds     = var.appstream_desktop_fleet.idle_disconnect_timeout_in_seconds
      organizational_unit_distinguished_name = local.ou.desktop_fleet
    }
  }

  # CIDRs that need to reach file shares, the application tier and SQL Server.
  workload_cidrs = concat(module.network.app_subnet_cidrs, module.network.stream_subnet_cidrs)
}
