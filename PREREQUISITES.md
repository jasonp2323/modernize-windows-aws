# What you need to do ahead of time

Terraform builds the environment; a handful of things have to exist first, and
two things (image creation and the Entra Connect wizard) are interactive by
nature. This is the full list, in the order you will need it.

---

## 1. Decisions to make first

| Decision | Default here | Notes |
|---|---|---|
| Region | `us-east-1` | Must support AWS Managed Microsoft AD, FSx for Windows File Server, RDS for SQL Server and WorkSpaces Applications. |
| VPC CIDR | `10.20.0.0/16` | Carved into `/24`s: public, app, data, stream - two AZs each. |
| Domain name | `corp.example.com` | Use a subdomain you control. Avoid `.local` and avoid re-using your public zone apex. |
| NetBIOS name | `CORP` | Also the name of the OU AWS delegates to you. |
| Name prefix | `mwa` | Used for every AWS resource name **and** in the bootstrap IAM policy. Keep them in sync. |
| Directory edition | `Standard` | Enterprise only if you need >5 000 objects or multi-Region replication. |

## 2. AWS account

- [ ] An account you can run IAM, Directory Service, FSx, RDS and AppStream in.
- [ ] **Service quotas.** New accounts frequently have low or zero limits on the
      streaming pieces. Request increases before stage 2/3:
      - AppStream image builders (per Region)
      - AppStream fleet instances for the families you plan to use
        (`stream.standard.*`)
      - Elastic IPs (one per NAT gateway) and VPC per-Region limits
- [ ] Decide whether you want an EC2 key pair. It is only used to retrieve local
      Administrator passwords; Fleet Manager and Session Manager cover normal
      access. Set `key_pair_name` if you create one.
- [ ] Check that AWS Managed Microsoft AD, FSx and RDS for SQL Server are all
      available in the AZs your `az_count` will pick.

## 3. HCP Terraform

- [ ] An HCP Terraform organization and a project.
- [ ] A **VCS provider connection** to GitHub (Settings → Providers → VCS
      Providers). Note the OAuth token ID (`ot-…`) if you want `bootstrap/` to
      create the workspace for you.
- [ ] Run `bootstrap/` locally, once, with credentials that can create IAM
      resources:

      ```bash
      cd bootstrap
      cp terraform.tfvars.example terraform.tfvars
      terraform init
      terraform apply
      ```

      It creates the IAM OIDC provider for `app.terraform.io`, the run role
      that only your workspace's plan/apply subjects may assume, and a scoped
      permissions policy. With `manage_hcp_workspace = true` it also creates the
      VCS-driven workspace and sets its credential variables.

- [ ] If you created the workspace by hand instead, set these **environment**
      variables on it (they are printed as a bootstrap output):

      | Variable | Value |
      |---|---|
      | `TFC_AWS_PROVIDER_AUTH` | `true` |
      | `TFC_AWS_RUN_ROLE_ARN` | run role ARN from bootstrap |
      | `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE` | `aws.workload.identity` |

      and set the workspace's **working directory** to `infra`.

- [ ] Edit `infra/backend.tf` so `organization` and `workspaces.name` match.

## 4. GitHub

- [ ] Actions enabled. The workflow needs no secrets: it only runs
      `terraform fmt -check`, `terraform validate` and a PowerShell parse.
- [ ] Protect the branch HCP Terraform tracks, so applies follow review.

## 5. Microsoft Entra ID

- [ ] **A tenant**, and a **verified custom domain** matching the UPN suffix you
      want users to sign in with (`entra_upn_suffix`, for example `example.com`).
      Without it, synced users get `…@<tenant>.onmicrosoft.com`.
- [ ] **Licensing.** Assigning *groups* to an enterprise application requires
      Entra ID P1 or P2. Without P1 you can still use this design, but you must
      assign users to the applications individually. FSLogix additionally
      requires an eligible license (Microsoft 365 E3/E5/A3/A5/F3, Windows
      Enterprise E3/E5, or an RDS CAL) - check your entitlement before relying
      on profile containers.
- [ ] **An app registration for Terraform**, so the `azuread` provider can
      manage the enterprise applications. Grant these Microsoft Graph
      *application* permissions and admin-consent them:
      `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`,
      `Group.ReadWrite.All`, `Policy.ReadWrite.ApplicationConfiguration`.
      Put its credentials on the HCP Terraform workspace as environment
      variables: `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`.
- [ ] **An account with the Hybrid Identity Administrator role** for the Entra
      Connect wizard (step 8 below).

## 6. Licensing and cost acknowledgements

- Windows Server AMIs and RDS `license-included` carry the Microsoft licence in
  the hourly price - nothing to bring.
- WorkSpaces Applications includes the Microsoft RDS SAL in its user fee.
- FSLogix needs the entitlement noted above.
- AWS Managed Microsoft AD, two Multi-AZ FSx file systems and an RDS SQL Server
  Standard Edition instance are the expensive parts of this stack. Nothing here
  is free tier.

---

## 7. Building the streaming images

This is the one part of the environment that cannot be fully automated, and it
is why the deployment has stages.

### 7.1 Find a base image

```bash
aws appstream describe-images --type PUBLIC \
  --query "Images[?starts_with(Name,'AppStream-WinServer')].[Name,Platform]" \
  --output table
```

Pick a current Windows Server 2022 image and set:

```hcl
enable_image_builders     = true
appstream_base_image_name = "AppStream-WinServer2022-XX-XX-XXXX"
```

Apply. Two image builders start, both joined to the domain in the
`Streaming/ImageBuilders` OU.

### 7.2 Prepare each image builder

1. WorkSpaces Applications console → **Image builders** → select → **Connect**,
   and log in as **Administrator**.
2. Open PowerShell as Administrator and run the preparation script (its S3 URI
   is in the `automation.image_prep_script` Terraform output):

   ```powershell
   Read-S3Object -BucketName <automation-bucket> `
     -Key scripts/Prepare-StreamingImage.ps1 -File C:\Prepare-StreamingImage.ps1
   C:\Prepare-StreamingImage.ps1 -FsLogixGroup 'CORP\FSLogix-Users'
   ```

   It installs FSLogix, scopes profile containers to the directory group,
   applies the registry settings that must be baked into the image, and quiets
   the first-logon behaviour that non-persistent hosts do not want.

   To install a line-of-business application from S3 in the same pass:

   ```powershell
   C:\Prepare-StreamingImage.ps1 -FsLogixGroup 'CORP\FSLogix-Users' `
     -ApplicationS3Uri 's3://<bucket>/installers/lob-app.msi' `
     -ApplicationArguments '/qn /norestart'
   ```

3. Install anything else the users need (the desktop image usually gets a
   browser and Office; the published-application image gets only the one app).

### 7.3 Create the image

1. Launch **Image Assistant**.
2. **+ Add App** for each application to publish.
   - Published-application fleet: add exactly one application. That is what
     makes the session look like RemoteApp.
   - Desktop fleet: add the applications you want on the Start menu.
3. **Switch user → Template User**, launch each application once so first-run
   dialogs and default settings are captured, then **Switch user → Administrator**.
4. Continue through **Optimize**, then name the image. Use a name you can put
   in `tfvars` verbatim, for example `mwa-lob-app-2026-01-15`.
5. Repeat for the second image builder.
6. When both images show **Available**, record the names:

   ```hcl
   enable_streaming_fleets      = true
   appstream_app_image_name     = "mwa-lob-app-2026-01-15"
   appstream_desktop_image_name = "mwa-desktop-2026-01-15"
   wait_for_domain_automation   = true
   enable_image_builders        = false   # stop paying for the builders
   ```

The FSLogix GPO is deliberately **not** linked to the image builder OU - you do
not want a profile container mounting while you build an image.

---

## 8. Finishing Entra Connect (interactive)

Terraform deploys the Entra Connect server, creates the AD DS connector account,
installs the Entra Connect Sync package and grants the connector account the
permissions AWS documents for a managed directory. The wizard itself needs a
human:

1. Connect to the Entra Connect instance (Fleet Manager or RDP) as `CORP\Admin`.
2. Launch **Microsoft Entra Connect** → **Customize**.
3. **Use an existing service account** → `CORP\svc-join` (password is in Secrets
   Manager under `<prefix>/ad/svc-join`).
4. User sign-in: **Pass-through Authentication**, or **Do not configure** if the
   applications federate straight to Entra ID.
5. Connect your directories → your forest → **Use existing AD account**.
6. Domain/OU filtering: select only `OU=CORP,DC=corp,DC=example,DC=com`.
7. Finish and let the initial sync run.

Reference:
<https://docs.aws.amazon.com/directoryservice/latest/admin-guide/ms_ad_connect_ms_entra_sync.html>

## 9. Finishing the SAML federation (two clicks)

After `enable_entra_saml = true` applies:

1. In the Entra portal, open each enterprise application → **Single sign-on** →
   **Attributes & Claims**, and confirm the **Name identifier format** is
   **Persistent**. AppStream matches `appstream:userId` against a persistent
   NameID, and Graph does not expose that setting cleanly enough to manage from
   Terraform. Everything else - the Role, RoleSessionName and SessionDuration
   claims - is created by the claims mapping policy.
2. Add users to the Entra groups Terraform created (`… Published Application
   Users`, `… Virtual Desktop Users`) **and** to the matching directory group
   `CORP\FSLogix-Users`, so they get a profile container.

---

## Checklist

```
[ ] Region, CIDR, domain name and name prefix agreed
[ ] AWS quotas raised for AppStream image builders and fleet instances
[ ] HCP Terraform org, project and VCS connection in place
[ ] bootstrap/ applied; run role ARN on the workspace
[ ] infra/backend.tf points at your org and workspace
[ ] Entra tenant, verified domain, Terraform app registration + ARM_* variables
[ ] Stage 1 applied; domain automation reports success
[ ] Stage 2: images built and named
[ ] Stage 3: fleets, stacks and Entra applications applied
[ ] Entra Connect wizard finished
[ ] NameID format confirmed Persistent; users added to the groups
```
