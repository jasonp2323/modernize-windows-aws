<#
.SYNOPSIS
    Prepares an Amazon WorkSpaces Applications (AppStream 2.0) image builder for
    FSLogix-backed, domain-joined streaming.

.DESCRIPTION
    Run this INSIDE the image builder session, as Administrator, before you use
    Image Assistant to create the image. It is deliberately a manual, one-time
    step: image creation is not a Terraform lifecycle, and the resulting image
    name is an input to the fleets.

    What it does:
      1. Installs the FSLogix agent.
      2. Adds the FSLogix profile include/exclude groups so only the intended
         directory group gets a container.
      3. Applies the registry settings that must be baked into the image (the
         rest arrive by GPO once the fleet instance is domain joined).
      4. Turns off the machine-wide settings that fight with non-persistent
         desktops (Store auto-update, first-logon animation, Windows Search
         index rebuild noise).
      5. Optionally installs a line-of-business application from S3.

.PARAMETER FsLogixGroup
    Directory group whose members get an FSLogix profile container, for example
    CORP\FSLogix-Users.

.PARAMETER ApplicationS3Uri
    Optional s3://bucket/key of an MSI or EXE installer to stage and run.

.PARAMETER ApplicationArguments
    Silent-install arguments for the installer above.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FsLogixGroup,
    [Parameter(Mandatory = $false)][string]$ApplicationS3Uri,
    [Parameter(Mandatory = $false)][string]$ApplicationArguments = '/qn /norestart',
    [Parameter(Mandatory = $false)][string]$FsLogixDownloadUrl = 'https://aka.ms/fslogix_download'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step { param([string]$Message) Write-Host "[$(Get-Date -Format o)] $Message" }

$staging = 'C:\ProgramData\mwa\image'
New-Item -ItemType Directory -Force -Path $staging | Out-Null

##############################################################################
# 1. FSLogix agent
##############################################################################

if (-not (Test-Path 'C:\Program Files\FSLogix\Apps\frx.exe')) {
    Write-Step 'Downloading FSLogix.'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $zip = Join-Path $staging 'FSLogix.zip'
    Invoke-WebRequest -Uri $FsLogixDownloadUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath (Join-Path $staging 'FSLogix') -Force

    $installer = Get-ChildItem -Path (Join-Path $staging 'FSLogix') -Recurse -Filter 'FSLogixAppsSetup.exe' |
        Where-Object { $_.FullName -match 'x64' } | Select-Object -First 1
    if (-not $installer) { throw 'FSLogixAppsSetup.exe (x64) not found in the downloaded archive.' }

    Write-Step "Installing FSLogix from $($installer.FullName)."
    $proc = Start-Process -FilePath $installer.FullName -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) { throw "FSLogix installer exited with $($proc.ExitCode)." }
}
else {
    Write-Step 'FSLogix already installed.'
}

##############################################################################
# 2. Include/exclude groups
#
# FSLogix creates local groups at install time. By default "Everyone" is in the
# include list; replacing that with a directory group keeps service and admin
# logons on local profiles.
##############################################################################

Write-Step "Scoping FSLogix profile containers to $FsLogixGroup."
try {
    Remove-LocalGroupMember -Group 'FSLogix Profile Include List' -Member 'Everyone' -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group 'FSLogix Profile Include List' -Member $FsLogixGroup -ErrorAction Stop
}
catch {
    Write-Warning "Could not update the include list ($($_.Exception.Message)). The image builder must be domain joined for group lookups to resolve."
}

foreach ($account in @('Administrator', 'ImageBuilderAdmin')) {
    try { Add-LocalGroupMember -Group 'FSLogix Profile Exclude List' -Member $account -ErrorAction SilentlyContinue } catch {}
}

##############################################################################
# 3. Registry settings baked into the image
##############################################################################

$profileKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'
New-Item -Path $profileKey -Force | Out-Null
# Roam the whole profile and keep the container attached across the session.
New-ItemProperty -Path $profileKey -Name 'Enabled' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $profileKey -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $profileKey -Name 'FlipFlopProfileDirectoryName' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $profileKey -Name 'RoamSearch' -Value 0 -PropertyType DWord -Force | Out-Null

# Non-persistent hosts: stop Windows from spending the first minute of every
# session on things the user will never see again.
$explorerPolicy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
New-Item -Path $explorerPolicy -Force | Out-Null
New-ItemProperty -Path $explorerPolicy -Name 'EnableFirstLogonAnimation' -Value 0 -PropertyType DWord -Force | Out-Null

$storePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
New-Item -Path $storePolicy -Force | Out-Null
New-ItemProperty -Path $storePolicy -Name 'AutoDownload' -Value 2 -PropertyType DWord -Force | Out-Null

##############################################################################
# 4. Optional line-of-business application
##############################################################################

if ($ApplicationS3Uri) {
    Import-Module AWSPowerShell.NetCore -ErrorAction SilentlyContinue
    if (-not (Get-Command Read-S3Object -ErrorAction SilentlyContinue)) {
        Import-Module AWSPowerShell -ErrorAction SilentlyContinue
    }
    if (-not (Get-Command Read-S3Object -ErrorAction SilentlyContinue)) {
        throw 'AWS Tools for PowerShell is not available on this image builder. Install it, or copy the installer in another way.'
    }

    Write-Step "Staging application from $ApplicationS3Uri."
    $fileName = $ApplicationS3Uri.Split('/')[-1]
    $local = Join-Path $staging $fileName

    $uri = [Uri]$ApplicationS3Uri
    Read-S3Object -BucketName $uri.Host -Key $uri.AbsolutePath.TrimStart('/') -File $local | Out-Null

    Write-Step "Installing $fileName."
    if ($fileName -match '\.msi$') {
        $proc = Start-Process msiexec.exe -ArgumentList "/i `"$local`" $ApplicationArguments" -Wait -PassThru
    }
    else {
        $proc = Start-Process -FilePath $local -ArgumentList $ApplicationArguments -Wait -PassThru
    }
    if ($proc.ExitCode -notin @(0, 3010)) { throw "Application installer exited with $($proc.ExitCode)." }
}

Write-Step @'
Image preparation complete. Next, in the image builder session:
  1. Launch Image Assistant.
  2. Add each application users should see (for the RemoteApp-style fleet, add
     only the single application you want to publish).
  3. Switch to the Template User, launch each application once so default
     settings are captured, then switch back to the Administrator.
  4. Run the optimization step, name the image, and create it.
  5. Put the resulting image name into terraform.tfvars as
     appstream_app_image_name / appstream_desktop_image_name.
'@
