# Operating the environment

## Watching the domain build itself

The domain configuration runs as an SSM State Manager association against the
management server.

```bash
ASSOC=$(terraform output -json automation | jq -r .association_id)
aws ssm describe-association-executions --association-id "$ASSOC" \
  --query 'AssociationExecutions[0].[Status,CreatedTime]' --output text

# Per-instance detail, including the PowerShell output
aws ssm describe-association-execution-targets --association-id "$ASSOC" \
  --execution-id <execution-id>
```

Full transcripts live on the management server at `C:\ProgramData\mwa\logs`.
The association re-runs hourly and everything it does is idempotent, so a
failure caused by ordering (for example, running before the seamless domain
join finished) heals on the next pass.

## Getting onto the servers

Session Manager and Fleet Manager work without opening RDP:

```bash
aws ssm start-session --target <instance-id>
```

For a desktop, use Fleet Manager → Remote Desktop in the console. If you set
`admin_cidrs`, plain RDP works too. Credentials:

```bash
aws secretsmanager get-secret-value --secret-id mwa/ad/admin \
  --query SecretString --output text | jq .
```

## Everyday directory work

On the management server, as `CORP\Admin`:

```powershell
# A user who gets a profile container and a published application
New-ADUser -Name 'jsmith' -SamAccountName 'jsmith' -UserPrincipalName 'jsmith@corp.example.com' `
  -Path 'OU=Users,OU=CORP,DC=corp,DC=example,DC=com' `
  -AccountPassword (Read-Host -AsSecureString) -Enabled $true

Add-ADGroupMember -Identity 'FSLogix-Users'      -Members 'jsmith'
Add-ADGroupMember -Identity 'RemoteApp-Users'    -Members 'jsmith'
Add-ADGroupMember -Identity 'FileShare-Company-RW' -Members 'jsmith'
```

Then add the same person to the matching Entra ID group so they can actually
reach the stack.

## SQL Server Windows Authentication

RDS joins the domain, but the SQL logins are yours to create. Connect once as
the master user (its password is in the RDS-managed secret), then:

```sql
CREATE LOGIN [CORP\SQL-AppAdmins] FROM WINDOWS;
CREATE DATABASE AppDb;
GO
USE AppDb;
CREATE USER [CORP\SQL-AppAdmins] FOR LOGIN [CORP\SQL-AppAdmins];
ALTER ROLE db_owner ADD MEMBER [CORP\SQL-AppAdmins];
```

From a domain-joined application server, verify integrated auth end to end:

```powershell
sqlcmd -S mwa-sql.abcdefg.us-east-1.rds.amazonaws.com -E -Q "SELECT SUSER_SNAME()"
```

## Verifying FSLogix

After a user's first streaming session:

```powershell
# On the management server - a container per user appears on the profile share
Get-ChildItem '\\profiles.corp.example.com\profiles'
```

Inside a session, `C:\ProgramData\FSLogix\Logs\Profile` shows whether the
container attached, and `frx list-redirects` reports the active configuration.
If the profile is local rather than containerised, check in this order:

1. Is the fleet instance in `OU=AppFleet,OU=Streaming,…`? The GPO is linked
   there, not at the domain root.
2. Is the user in `CORP\FSLogix-Users`, and is that group in the image's
   **FSLogix Profile Include List** local group?
3. Can the fleet reach `\\profiles.<domain>\profiles`? The share ACL grants the
   FSLogix group create-folder rights only - that is by design.

## Updating a streaming image

Fleets cannot swap images while running.

```bash
aws appstream stop-fleet --name mwa-app
# update appstream_app_image_name in the workspace variables, apply
aws appstream start-fleet --name mwa-app
```

Turning `enable_image_builders` back on gives you builders again; they start
from the public base image, so for an incremental change start the *existing*
image instead (WorkSpaces Applications console → Images → Launch image builder
from image).

## Scaling

`appstream_app_fleet` / `appstream_desktop_fleet` carry the sizing.
`enable_streaming_autoscaling = true` attaches target tracking on
`AppStreamAverageCapacityUtilization` between `min_capacity` and `max_capacity`.
For predictable office hours, add scheduled scaling on the same scalable target.

## Troubleshooting

| Symptom | Look at |
|---|---|
| Instance never joins the domain | Does it carry the `DomainJoin=true` tag? Is the SSM agent reporting? Does the instance profile have `AmazonSSMDirectoryServiceAccess`? Is the VPC using the DHCP option set that points at the DCs? |
| Domain automation association fails | Transcript in `C:\ProgramData\mwa\logs`. The most common cause is running before the join completed - it retries on the next pass. |
| `New-FSxSmbShare` fails | The delegated admin must be in **AWS Delegated FSx Administrators**. Check that TCP 5985 is open from the management subnet to the file system. |
| Fleet stuck in `STARTING`, then errors | Directory config service account rights on the fleet OU, the OU distinguished name, and DNS. `aws appstream describe-fleets` reports the domain join error verbatim. |
| SAML sign-in returns "not authorized to perform sts:AssumeRoleWithSAML" | The Role claim must be `<role-arn>,<provider-arn>` in that order, and the NameID format must be Persistent. |
| Streaming session opens then immediately closes | Almost always FSLogix failing to attach a container - check the profile share ACL and the container path in the GPO. |

## Teardown

```bash
# fleets first - stacks cannot be deleted while a fleet is associated
aws appstream stop-fleet --name mwa-app
aws appstream stop-fleet --name mwa-desktop
```

Then queue a destroy run. Things worth knowing:

- FSx file systems are created with `skip_final_backup = true` for a lab. Flip
  it if the data matters.
- RDS uses `skip_final_snapshot = true` for the same reason.
- The directory cannot be deleted while FSx, RDS or AppStream still reference
  it; Terraform's dependency graph handles this, but a half-destroyed state can
  leave a stray directory registration - delete the FSx file systems and the
  RDS instance first if you hit it.
- Secrets are retained for `secret_recovery_window_in_days` (7 by default). Set
  it to `0` if you rebuild the lab often and want the names freed immediately.
