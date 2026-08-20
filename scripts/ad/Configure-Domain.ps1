<#
.SYNOPSIS
    Builds out the Active Directory structure, FSx shares and FSLogix policy
    for the sample modern Windows environment.

.DESCRIPTION
    Runs on the management server, as the AWS Managed Microsoft AD delegated
    admin (see Invoke-DomainScript.ps1). Everything is idempotent: it is safe to
    re-run, and State Manager will re-run it whenever the association changes.

    Steps:
      1. Install RSAT / GPMC.
      2. Create the OU tree under the delegated OU.
      3. Create security groups and the directory service account.
      4. Delegate computer-object rights on the streaming OUs to that account so
         WorkSpaces Applications fleets can join the domain.
      5. Create the SMB shares on both FSx file systems and set NTFS ACLs
         (FSLogix-recommended permissions on the profile share).
      6. Register FSx DNS aliases (CNAME + SPNs) when aliases are configured.
      7. Create and link the FSLogix GPO (profile containers, optional Office
         containers) plus a small streaming-host policy.

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
$netbios = $cfg.NetBiosName
$ouRoot = $cfg.OuRoot

##############################################################################
# 1. Tooling
##############################################################################

Write-Step 'Ensuring RSAT and Group Policy tooling is installed.'
$features = @('RSAT-AD-PowerShell', 'RSAT-ADDS-Tools', 'GPMC', 'RSAT-DNS-Server')
foreach ($feature in $features) {
    $state = Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
    if ($state -and -not $state.Installed) {
        Write-Step "Installing $feature."
        Install-WindowsFeature -Name $feature -IncludeManagementTools | Out-Null
    }
}
Import-Module ActiveDirectory
Import-Module GroupPolicy

$dc = (Get-ADDomainController -DomainName $domain -Discover -Service PrimaryDC).HostName[0]
Write-Step "Using domain controller $dc."

##############################################################################
# 2. Organizational units
##############################################################################

function New-OuPath {
    param([string]$Path)   # e.g. "Servers/Application"

    $segments = $Path.Split('/')
    $parent = $ouRoot
    foreach ($segment in $segments) {
        $dn = "OU=$segment,$parent"
        $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$segment'" -SearchBase $parent -SearchScope OneLevel -Server $dc -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Step "Creating OU $dn."
            New-ADOrganizationalUnit -Name $segment -Path $parent -Server $dc -ProtectedFromAccidentalDeletion $false | Out-Null
        }
        $parent = $dn
    }
    return $parent
}

foreach ($ou in $cfg.Ous) { New-OuPath -Path $ou | Out-Null }

##############################################################################
# 3. Groups and service account
##############################################################################

$groupsOu = "OU=Groups,$ouRoot"
foreach ($group in $cfg.Groups) {
    $existing = Get-ADGroup -Filter "Name -eq '$($group.Name)'" -Server $dc -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Step "Creating group $($group.Name)."
        New-ADGroup -Name $group.Name -SamAccountName $group.Name -GroupCategory Security `
            -GroupScope Global -Path $groupsOu -Description $group.Description -Server $dc | Out-Null
    }
}

function Set-ServiceAccount {
    param([string]$SecretId, [string]$Description)

    $secret = (Get-SECSecretValue -SecretId $SecretId -Region $cfg.Region).SecretString | ConvertFrom-Json
    $sam = $secret.username
    $password = ConvertTo-SecureString -String $secret.password -AsPlainText -Force
    $accountsOu = "OU=ServiceAccounts,$ouRoot"

    $user = Get-ADUser -Filter "SamAccountName -eq '$sam'" -Server $dc -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Step "Creating service account $sam."
        $user = New-ADUser -Name $sam -SamAccountName $sam -UserPrincipalName "$sam@$domain" `
            -Path $accountsOu -AccountPassword $password -Enabled $true `
            -PasswordNeverExpires $true -CannotChangePassword $true `
            -Description $Description -Server $dc -PassThru
    }
    else {
        Write-Step "Service account $sam exists, resetting password to the Secrets Manager value."
        Set-ADAccountPassword -Identity $user -Reset -NewPassword $password -Server $dc
        Set-ADUser -Identity $user -Enabled $true -PasswordNeverExpires $true -Server $dc
    }

    return (Get-ADUser -Identity $sam -Server $dc)
}

$joinAccount = Set-ServiceAccount -SecretId $cfg.ServiceAccountSecretId `
    -Description 'Directory join and streaming automation account.'

##############################################################################
# 4. Delegate computer object rights on the streaming and server OUs
#
# WorkSpaces Applications (AppStream 2.0) image builders and fleets create and
# delete computer objects in these OUs on every instance they start.
##############################################################################

$computerClassGuid = [Guid]'bf967a86-0de6-11d0-a285-00aa003049e2'
$allGuid = [Guid]'00000000-0000-0000-0000-000000000000'

function Grant-ComputerObjectRights {
    param([string]$OuDn, [System.Security.Principal.SecurityIdentifier]$Sid)

    $entry = [ADSI]"LDAP://$dc/$OuDn"
    $security = $entry.psbase.ObjectSecurity

    $rules = @(
        # Create and delete computer objects directly in this OU.
        New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $Sid, 'CreateChild, DeleteChild', 'Allow', $computerClassGuid, 'All'),
        # Manage the computer objects that land there (password reset, SPN and
        # DNS host name writes, account restrictions).
        New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $Sid, 'GenericAll', 'Allow', $allGuid, 'Descendents', $computerClassGuid)
    )

    foreach ($rule in $rules) { $security.AddAccessRule($rule) | Out-Null }
    $entry.psbase.CommitChanges()
    Write-Step "Delegated computer object rights on $OuDn."
}

foreach ($ou in $cfg.JoinDelegationOus) {
    Grant-ComputerObjectRights -OuDn $ou -Sid $joinAccount.SID
}

##############################################################################
# 5. FSx shares and NTFS permissions
##############################################################################

function New-FsxShare {
    param(
        [string]$FileSystemDns,
        [pscustomobject]$Share,
        [string]$Purpose
    )

    $uncRoot = "\\$FileSystemDns\share"
    $folder = Join-Path $uncRoot $Share.Folder
    if (-not (Test-Path $folder)) {
        Write-Step "Creating folder $folder."
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $existing = Invoke-Command -ComputerName $FileSystemDns -ConfigurationName FSxRemoteAdmin `
        -ScriptBlock { param($n) Get-FSxSmbShare -Name $n -ErrorAction SilentlyContinue } -ArgumentList $Share.Name

    if (-not $existing) {
        Write-Step "Creating SMB share $($Share.Name) on $FileSystemDns."
        Invoke-Command -ComputerName $FileSystemDns -ConfigurationName FSxRemoteAdmin -ScriptBlock {
            param($name, $path, $description)
            New-FSxSmbShare -Name $name -Path $path -Description $description
        } -ArgumentList $Share.Name, "D:\share\$($Share.Folder)", $Share.Description
    }

    # Share-level permissions are deliberately permissive; the NTFS ACLs below
    # are what actually enforce access.
    foreach ($grant in @(
            @{ Accounts = $Share.FullAccess; Right = 'Full' },
            @{ Accounts = $Share.ChangeAccess; Right = 'Change' })) {
        foreach ($account in $grant.Accounts) {
            try {
                Invoke-Command -ComputerName $FileSystemDns -ConfigurationName FSxRemoteAdmin -ScriptBlock {
                    param($name, $accountName, $right)
                    Grant-FSxSmbShareAccess -Name $name -AccountName $accountName -AccessRight $right -Force
                } -ArgumentList $Share.Name, $account, $grant.Right
            }
            catch {
                Write-Warning "Could not grant $($grant.Right) on $($Share.Name) to ${account}: $($_.Exception.Message)"
            }
        }
    }

    Write-Step "Applying NTFS permissions to $folder ($Purpose)."
    & icacls $folder /inheritance:r | Out-Null
    & icacls $folder /grant "SYSTEM:(OI)(CI)F" | Out-Null
    foreach ($principal in $Share.FullAccess) {
        & icacls $folder /grant "${principal}:(OI)(CI)F" | Out-Null
    }

    if ($Purpose -eq 'fslogix') {
        # FSLogix-recommended layout: users may create their own container
        # folder but cannot traverse other users' containers; ownership grants
        # full control inside their own.
        foreach ($principal in $Share.ChangeAccess) {
            & icacls $folder /grant "${principal}:(AD,RD,REA,X)" | Out-Null
        }
        & icacls $folder /grant "CREATOR OWNER:(OI)(CI)(IO)F" | Out-Null
    }
    else {
        foreach ($principal in $Share.ChangeAccess) {
            & icacls $folder /grant "${principal}:(OI)(CI)M" | Out-Null
        }
    }
}

foreach ($fs in $cfg.FileSystems) {
    foreach ($share in $fs.Shares) {
        New-FsxShare -FileSystemDns $fs.DnsName -Share $share -Purpose $fs.Purpose
    }

    ##########################################################################
    # 6. DNS aliases: CNAME in AD DNS plus SPNs on the FSx computer object, so
    #    Kerberos still works when clients use the alias.
    ##########################################################################
    foreach ($alias in $fs.Aliases) {
        $short = $alias.Split('.')[0]
        try {
            $record = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $domain -Name $short -RRType CName -ErrorAction SilentlyContinue
            if (-not $record) {
                Write-Step "Creating DNS CNAME $alias -> $($fs.DnsName)."
                Add-DnsServerResourceRecordCName -ComputerName $dc -ZoneName $domain -Name $short -HostNameAlias $fs.DnsName
            }

            $fsxComputerName = $fs.DnsName.Split('.')[0].ToUpper()
            $fsxComputer = Get-ADComputer -Filter "Name -eq '$fsxComputerName'" -Server $dc -ErrorAction SilentlyContinue
            if ($fsxComputer) {
                Write-Step "Adding SPNs for $alias to $fsxComputerName."
                & setspn -S "HOST/$short" $fsxComputerName | Out-Null
                & setspn -S "HOST/$alias" $fsxComputerName | Out-Null
            }
        }
        catch {
            Write-Warning "Could not register alias ${alias}: $($_.Exception.Message)"
        }
    }
}

##############################################################################
# 7. FSLogix policy
#
# Configured as registry policy rather than through the FSLogix ADMX so the
# stack does not depend on the ADMX files being staged in SYSVOL first. The
# ADMX templates are copied to the central store as a convenience when they are
# present on this server.
##############################################################################

function Set-PolicyValue {
    param([string]$Gpo, [string]$Key, [string]$Name, $Value, [string]$Type)
    Set-GPRegistryValue -Name $Gpo -Key $Key -ValueName $Name -Value $Value -Type $Type | Out-Null
}

$fsl = $cfg.FsLogix
$gpoName = $fsl.GpoName

if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    Write-Step "Creating GPO $gpoName."
    New-GPO -Name $gpoName -Comment 'FSLogix profile containers on FSx for Windows File Server.' | Out-Null
}

$profileKey = 'HKLM\SOFTWARE\FSLogix\Profiles'
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'Enabled' -Value 1 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'VHDLocations' -Value $fsl.ProfileUnc -Type MultiString
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'SizeInMBs' -Value $fsl.SizeInMBs -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'IsDynamic' -Value 1 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'VolumeType' -Value 'VHDX' -Type String
# One folder per user, named <SID>_<samaccountname> for readability.
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'FlipFlopProfileDirectoryName' -Value 1 -Type DWord
# Non-persistent hosts: never leave a stale local profile behind.
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'ProfileType' -Value 0 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'LockedRetryCount' -Value 3 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'LockedRetryInterval' -Value 15 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'ReAttachIntervalSeconds' -Value 15 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'ReAttachRetryCount' -Value 3 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'PreventLoginWithFailure' -Value 1 -Type DWord
Set-PolicyValue -Gpo $gpoName -Key $profileKey -Name 'PreventLoginWithTempProfile' -Value 1 -Type DWord

if ($fsl.EnableOfficeContainer) {
    $officeKey = 'HKLM\SOFTWARE\Policies\FSLogix\ODFC'
    Set-PolicyValue -Gpo $gpoName -Key $officeKey -Name 'Enabled' -Value 1 -Type DWord
    Set-PolicyValue -Gpo $gpoName -Key $officeKey -Name 'VHDLocations' -Value $fsl.OfficeUnc -Type MultiString
    Set-PolicyValue -Gpo $gpoName -Key $officeKey -Name 'SizeInMBs' -Value $fsl.SizeInMBs -Type DWord
    Set-PolicyValue -Gpo $gpoName -Key $officeKey -Name 'IsDynamic' -Value 1 -Type DWord
    Set-PolicyValue -Gpo $gpoName -Key $officeKey -Name 'VolumeType' -Value 'VHDX' -Type String
    Set-PolicyValue -Gpo $gpoName -Key $officeKey -Name 'FlipFlopProfileDirectoryName' -Value 1 -Type DWord
}

# The GPO applies to the computer objects in the streaming and app OUs. Which
# users actually get a container is controlled on the host by the local
# "FSLogix Profile Include List" group, which the FSLogix agent creates and
# which the image build script populates - see scripts/image.
foreach ($linkOu in $fsl.LinkOus) {
    $existingLink = (Get-GPInheritance -Target $linkOu).GpoLinks | Where-Object { $_.DisplayName -eq $gpoName }
    if (-not $existingLink) {
        Write-Step "Linking $gpoName to $linkOu."
        New-GPLink -Name $gpoName -Target $linkOu -LinkEnabled Yes | Out-Null
    }
}

# Best effort: stage the FSLogix ADMX templates in the central store if they
# were installed on this server, so the settings are editable in GPMC.
$admxSource = 'C:\Program Files\FSLogix\Apps\admx'
$centralStore = "\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions"
if (Test-Path $admxSource) {
    try {
        New-Item -ItemType Directory -Force -Path $centralStore, "$centralStore\en-US" | Out-Null
        Copy-Item "$admxSource\*.admx" $centralStore -Force
        Copy-Item "$admxSource\en-US\*.adml" "$centralStore\en-US" -Force
        Write-Step 'Copied FSLogix ADMX templates to the central store.'
    }
    catch {
        Write-Warning "Could not stage ADMX templates: $($_.Exception.Message)"
    }
}

Write-Step 'Domain configuration complete.'
