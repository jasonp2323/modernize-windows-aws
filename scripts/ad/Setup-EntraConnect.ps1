<#
.SYNOPSIS
    Prepares this server, and the domain, for Microsoft Entra Connect Sync.

.DESCRIPTION
    Runs on the domain-joined Entra Connect server as the delegated admin (see
    Invoke-DomainScript.ps1). It does everything that can be automated:

      1. Creates the AD DS connector account used by Entra Connect Sync.
      2. Downloads and installs the Entra Connect Sync package (wizard only -
         the sync configuration itself is interactive and needs an Entra ID
         Hybrid Identity Administrator, so it is not scripted here).
      3. Grants the connector account the permissions AWS documents for
         AWS Managed Microsoft AD (basic read + msDS-ConsistencyGuid write on
         every OU under the delegated OU).
      4. Optionally adds a routable UPN suffix to the forest so synced users
         have UPNs matching a verified Entra ID domain.

    Reference:
    https://docs.aws.amazon.com/directoryservice/latest/admin-guide/ms_ad_connect_ms_entra_sync.html

.PARAMETER ConfigB64
    Base64 of the JSON configuration document rendered by Terraform.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigB64
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step { param([string]$Message) Write-Host "[$(Get-Date -Format o)] $Message" }

Import-Module AWSPowerShell.NetCore -ErrorAction SilentlyContinue
if (-not (Get-Command Get-SECSecretValue -ErrorAction SilentlyContinue)) {
    Import-Module AWSPowerShell -ErrorAction SilentlyContinue
}

$cfg = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ConfigB64)) | ConvertFrom-Json
$domain = $cfg.DomainName
$ouRoot = $cfg.OuRoot

Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeManagementTools | Out-Null
Import-Module ActiveDirectory
$dc = (Get-ADDomainController -DomainName $domain -Discover -Service PrimaryDC).HostName[0]

##############################################################################
# 1. Connector account
##############################################################################

$secret = (Get-SECSecretValue -SecretId $cfg.ConnectorSecretId -Region $cfg.Region).SecretString | ConvertFrom-Json
$sam = $secret.username
$password = ConvertTo-SecureString -String $secret.password -AsPlainText -Force
$accountsOu = "OU=ServiceAccounts,$ouRoot"

$user = Get-ADUser -Filter "SamAccountName -eq '$sam'" -Server $dc -ErrorAction SilentlyContinue
if (-not $user) {
    Write-Step "Creating Entra Connect AD DS connector account $sam."
    New-ADUser -Name $sam -SamAccountName $sam -UserPrincipalName "$sam@$domain" `
        -Path $accountsOu -AccountPassword $password -Enabled $true `
        -PasswordNeverExpires $true -CannotChangePassword $true `
        -Description 'AD DS connector account for Microsoft Entra Connect Sync.' -Server $dc | Out-Null
}
else {
    Write-Step "Connector account $sam exists, resetting password to the Secrets Manager value."
    Set-ADAccountPassword -Identity $user -Reset -NewPassword $password -Server $dc
}

##############################################################################
# 2. Entra Connect Sync package
##############################################################################

$installerDir = 'C:\ProgramData\mwa\installers'
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null
$msi = Join-Path $installerDir 'AzureADConnect.msi'

if (-not (Test-Path 'C:\Program Files\Microsoft Azure Active Directory Connect\AzureADConnect.exe')) {
    if (-not (Test-Path $msi)) {
        Write-Step "Downloading Entra Connect Sync from $($cfg.EntraConnectDownloadUrl)."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $cfg.EntraConnectDownloadUrl -OutFile $msi -UseBasicParsing
    }

    Write-Step 'Installing Entra Connect Sync (wizard only, no configuration).'
    $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) {
        throw "Entra Connect installer exited with $($proc.ExitCode)."
    }
}
else {
    Write-Step 'Entra Connect Sync already installed.'
}

##############################################################################
# 3. Connector account permissions (per the AWS tutorial)
##############################################################################

$modulePath = 'C:\Program Files\Microsoft Azure Active Directory Connect\AdSyncConfig\AdSyncConfig.psm1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force

    $connectorDn = (Get-ADUser -Identity $sam -Server $dc).DistinguishedName
    $ous = Get-ADOrganizationalUnit -SearchBase $ouRoot -SearchScope Subtree -Filter * -Server $dc |
        Select-Object -ExpandProperty DistinguishedName

    foreach ($ou in @($ouRoot) + $ous) {
        try {
            Set-ADSyncBasicReadPermissions -ADConnectorAccountDN $connectorDn -ADobjectDN $ou -Confirm:$false
            Set-ADSyncMsDsConsistencyGuidPermissions -ADConnectorAccountDN $connectorDn -ADobjectDN $ou -Confirm:$false
            Write-Step "Granted sync permissions on $ou."
        }
        catch {
            Write-Warning "Could not set permissions on ${ou}: $($_.Exception.Message)"
        }
    }
}
else {
    Write-Warning "AdSyncConfig.psm1 not found at $modulePath - re-run after the installer completes."
}

##############################################################################
# 4. Routable UPN suffix
##############################################################################

if ($cfg.UpnSuffix) {
    try {
        $forest = Get-ADForest -Server $dc
        if ($forest.UPNSuffixes -notcontains $cfg.UpnSuffix) {
            Write-Step "Adding UPN suffix $($cfg.UpnSuffix) to the forest."
            Set-ADForest -Identity $forest -UPNSuffixes @{Add = $cfg.UpnSuffix } -Server $dc
        }
    }
    catch {
        Write-Warning "Could not add the UPN suffix (this needs forest-level rights): $($_.Exception.Message)"
    }
}

Write-Step @"
Entra Connect Sync is installed but not configured. Finish interactively:
  1. RDP or Fleet Manager into this server as $($cfg.NetBiosName)\Admin.
  2. Launch Microsoft Entra Connect -> Customize.
  3. 'Use an existing service account' -> $($cfg.NetBiosName)\$sam (password is in
     Secrets Manager: $($cfg.ConnectorSecretId)).
  4. User sign-in: choose Pass-through Authentication, or 'Do not configure'
     when the applications federate straight to Entra ID.
  5. Connect your directories -> forest $domain -> use existing AD account.
  6. Domain/OU filtering: select $ouRoot only.
"@
