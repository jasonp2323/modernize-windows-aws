##############################################################################
# Management tier
#
#   - an S3 bucket holding the PowerShell automation
#   - a domain-joined management server (RSAT/GPMC) that runs it
#   - an optional Entra Connect Sync server
#   - the SSM document + State Manager associations that drive both
#
# The management server is what turns "a managed directory exists" into "a
# domain with OUs, groups, service accounts, delegated join rights, SMB shares
# and an FSLogix policy".
##############################################################################

data "aws_region" "current" {}

locals {
  scripts = {
    wrapper       = "${path.module}/../../../scripts/ad/Invoke-DomainScript.ps1"
    domain_config = "${path.module}/../../../scripts/ad/Configure-Domain.ps1"
    entra_connect = "${path.module}/../../../scripts/ad/Setup-EntraConnect.ps1"
    image_prep    = "${path.module}/../../../scripts/image/Prepare-StreamingImage.ps1"
  }

  # Any change to the scripts bumps this, which changes the association
  # parameters and makes State Manager re-run them.
  scripts_version = substr(sha256(join("", [for f in values(local.scripts) : filesha256(f)])), 0, 16)

  domain_config_json = jsonencode({
    DomainName             = var.domain_name
    NetBiosName            = var.domain_netbios_name
    Region                 = data.aws_region.current.region
    OuRoot                 = var.delegated_ou_dn
    ServiceAccountSecretId = var.service_account_secret_arn
    Ous                    = var.organizational_units
    Groups                 = var.security_groups
    JoinDelegationOus      = var.join_delegation_ou_dns
    FileSystems            = var.file_systems
    FsLogix                = var.fslogix
  })

  entra_config_json = jsonencode({
    DomainName              = var.domain_name
    NetBiosName             = var.domain_netbios_name
    Region                  = data.aws_region.current.region
    OuRoot                  = var.delegated_ou_dn
    ConnectorSecretId       = var.service_account_secret_arn
    UpnSuffix               = var.entra_upn_suffix
    EntraConnectDownloadUrl = var.entra_connect_download_url
  })
}

##############################################################################
# Automation scripts
#
# The bucket itself lives in the root module so the instance profile can be
# granted access to it without creating a dependency cycle with this module.
##############################################################################

resource "aws_s3_object" "scripts" {
  for_each = local.scripts

  bucket      = var.scripts_bucket
  key         = "scripts/${basename(each.value)}"
  source      = each.value
  source_hash = filemd5(each.value)

  tags = var.tags
}

##############################################################################
# SSM document: run an S3-hosted script under domain admin credentials
##############################################################################

locals {
  runner_commands = [
    "$ErrorActionPreference = 'Stop'",
    "Write-Host 'automation version {{Version}}'",
    "$dir = 'C:\\ProgramData\\mwa\\bin'",
    "New-Item -ItemType Directory -Force -Path $dir | Out-Null",
    "Import-Module AWSPowerShell.NetCore -ErrorAction SilentlyContinue",
    "function Get-S3File { param($Uri, $Dest) $u = [Uri]$Uri; Read-S3Object -BucketName $u.Host -Key $u.AbsolutePath.TrimStart('/') -File $Dest | Out-Null }",
    "Get-S3File -Uri '{{WrapperS3Uri}}' -Dest \"$dir\\Invoke-DomainScript.ps1\"",
    "Get-S3File -Uri '{{ScriptS3Uri}}' -Dest \"$dir\\Target.ps1\"",
    "& \"$dir\\Invoke-DomainScript.ps1\" -ScriptPath \"$dir\\Target.ps1\" -ConfigB64 '{{ConfigB64}}' -SecretId '{{SecretId}}' -Region '{{RegionName}}' -TaskName '{{TaskName}}'",
  ]
}

resource "aws_ssm_document" "run_as_domain_admin" {
  name            = "${var.name_prefix}-run-as-domain-admin"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Downloads a PowerShell script from S3 and runs it as the AWS Managed Microsoft AD delegated admin."
    parameters = {
      WrapperS3Uri = { type = "String", description = "S3 URI of Invoke-DomainScript.ps1." }
      ScriptS3Uri  = { type = "String", description = "S3 URI of the script to run." }
      ConfigB64    = { type = "String", description = "Base64 JSON configuration passed to the script." }
      SecretId     = { type = "String", description = "Secrets Manager ID holding the domain admin credentials." }
      RegionName   = { type = "String", description = "Region for AWS API calls." }
      TaskName     = { type = "String", description = "Scheduled task name.", default = "mwa-domain-config" }
      Version      = { type = "String", description = "Changes when the automation changes, forcing a re-run.", default = "1" }
    }
    mainSteps = [{
      action = "aws:runPowerShellScript"
      name   = "runAsDomainAdmin"
      inputs = {
        timeoutSeconds = "3600"
        runCommand     = local.runner_commands
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-run-as-domain-admin" })
}
