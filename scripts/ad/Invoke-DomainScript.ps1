<#
.SYNOPSIS
    Runs a domain configuration script under real domain credentials.

.DESCRIPTION
    SSM runs commands as NT AUTHORITY\SYSTEM. That context can join a machine to
    the domain, but it cannot create OUs, GPOs or users in AWS Managed Microsoft
    AD, and the Group Policy cmdlets have no -Credential parameter to work
    around it. Passing credentials over PowerShell remoting hits the Kerberos
    double hop.

    So this wrapper pulls the delegated admin credentials from Secrets Manager
    and runs the target script as a scheduled task under that account, which
    produces a real logon token with domain rights. It waits for the task,
    echoes the transcript to SSM output, and exits non-zero if the script did.

.NOTES
    Invoked by the SSM document created in infra/modules/management.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$ConfigB64,
    [Parameter(Mandatory = $true)][string]$SecretId,
    [Parameter(Mandatory = $true)][string]$Region,
    [Parameter(Mandatory = $false)][string]$TaskName = 'mwa-domain-config',
    [Parameter(Mandatory = $false)][int]$TimeoutMinutes = 60
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step { param([string]$Message) Write-Host "[$(Get-Date -Format o)] $Message" }

# State Manager can reach this instance before the seamless domain join has
# finished. Wait rather than fail the association.
$joinDeadline = (Get-Date).AddMinutes(30)
while (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain -and (Get-Date) -lt $joinDeadline) {
    Write-Step 'Waiting for the domain join to complete.'
    Start-Sleep -Seconds 30
}
if (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
    throw 'This instance is not domain joined yet. Check the AWS-JoinDirectoryServiceDomain association.'
}

Import-Module AWSPowerShell.NetCore -ErrorAction SilentlyContinue
if (-not (Get-Command Get-SECSecretValue -ErrorAction SilentlyContinue)) {
    Import-Module AWSPowerShell -ErrorAction SilentlyContinue
}
if (-not (Get-Command Get-SECSecretValue -ErrorAction SilentlyContinue)) {
    Write-Step 'AWS Tools for PowerShell not found, installing AWS.Tools.SecretsManager.'
    Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null
    Install-Module -Name AWS.Tools.SecretsManager -Force -Scope AllUsers -AllowClobber
    Import-Module AWS.Tools.SecretsManager
}

Write-Step "Reading credentials from $SecretId."
$secret = (Get-SECSecretValue -SecretId $SecretId -Region $Region).SecretString | ConvertFrom-Json
$runAsUser = $secret.domain_username
$runAsPassword = $secret.password

$logDir = 'C:\ProgramData\mwa\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $logDir "$TaskName-$stamp.log"
$exitCodePath = Join-Path $logDir "$TaskName-$stamp.exit"

# The task launches PowerShell, transcribes everything, and records an exit code
# we can read back from here.
$inner = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force | Out-Null
try {
    & '$ScriptPath' -ConfigB64 '$ConfigB64'
    '0' | Set-Content -Path '$exitCodePath'
} catch {
    Write-Host "FAILED: `$(`$_ | Out-String)"
    '1' | Set-Content -Path '$exitCodePath'
} finally {
    Stop-Transcript | Out-Null
}
"@

$innerPath = Join-Path 'C:\ProgramData\mwa' "$TaskName-$stamp.ps1"
Set-Content -Path $innerPath -Value $inner -Encoding UTF8

Write-Step "Registering scheduled task $TaskName to run as $runAsUser."
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$innerPath`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes $TimeoutMinutes)

Register-ScheduledTask -TaskName $TaskName -Action $action -Settings $settings `
    -User $runAsUser -Password $runAsPassword -RunLevel Highest | Out-Null

try {
    Start-ScheduledTask -TaskName $TaskName
    Write-Step 'Task started, waiting for completion.'

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        Start-Sleep -Seconds 10
        $state = (Get-ScheduledTask -TaskName $TaskName).State
    } while ($state -eq 'Running' -and (Get-Date) -lt $deadline)

    if ($state -eq 'Running') {
        throw "Task $TaskName did not finish within $TimeoutMinutes minutes."
    }
}
finally {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -Path $innerPath -Force -ErrorAction SilentlyContinue
}

if (Test-Path $logPath) {
    Write-Step "----- begin $ScriptPath transcript -----"
    Get-Content -Path $logPath | Write-Host
    Write-Step "----- end transcript -----"
}

$code = if (Test-Path $exitCodePath) { (Get-Content -Path $exitCodePath -Raw).Trim() } else { '1' }
if ($code -ne '0') {
    throw "$ScriptPath reported failure. See $logPath on the management server."
}

Write-Step 'Completed successfully.'
