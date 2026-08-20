# Modern Windows environment on AWS

A complete, opinionated sample of a modern Windows estate on AWS, built with
Terraform and driven by HCP Terraform's VCS workflow.

Everything that can be automated is: the domain is created, the OU tree,
groups, service accounts and delegation are built out, every server and service
is domain joined without touching a console, SMB shares are created with the
right ACLs, and the FSLogix policy is authored and linked from Terraform.

## What it builds

```
                         Microsoft Entra ID
                     (SAML federation + Entra Connect Sync)
                                  |
   users ---> WorkSpaces Applications (AppStream 2.0)
                 |                        |
        published-app fleet        non-persistent desktop fleet
        (stream_view = APP)        (stream_view = DESKTOP)
                 \                        /
                  \                      /
                   +-- domain joined ---+
                              |
   +--------------------------+---------------------------------+
   |                          |                                 |
AWS Managed              FSx for Windows                  Application tier
Microsoft AD             File Server x2                   Windows Server + IIS
(2 DCs, 2 AZs)     shares  |  FSLogix profiles            internal ALB
                              |                                 |
                              +------- RDS for SQL Server -------+
                                    (Windows Authentication)
```

| Layer | Service | Notes |
|---|---|---|
| Domain controllers | AWS Managed Microsoft AD | Two DCs across two AZs, patched and backed up by AWS. You get a delegated OU, not Domain Admin. |
| File shares | FSx for Windows File Server (`shares`) | `\\files.<domain>\company`, `\\files.<domain>\apps`. |
| Profile containers | FSx for Windows File Server (`profiles`) | Separate file system for FSLogix, so profile I/O and blast radius are isolated from file shares. |
| Application tier | EC2 Windows Server + internal ALB | Domain joined by SSM State Manager, configured by SSM. |
| Database | RDS for SQL Server | Joined to the managed domain for Windows Authentication; master password managed by RDS in Secrets Manager. |
| Published application | WorkSpaces Applications fleet, `stream_view = APP` | One application, RemoteApp style. |
| Virtual desktops | WorkSpaces Applications fleet, `stream_view = DESKTOP` | Non-persistent; user state lives entirely in FSLogix containers. |
| Identity | Microsoft Entra ID | SAML federation into the streaming stacks, Entra Connect Sync from AWS Managed Microsoft AD. |
| Management | EC2 Windows Server | Runs the domain build-out; also where you administer AD, DNS and GPOs. |

Amazon **WorkSpaces Applications** is the current name for AppStream 2.0. The
Terraform resources are still named `aws_appstream_*`.

## Why Entra ID is in here

Domain-joined streaming fleets cannot use the AppStream user pool - users have
to arrive through SAML. So an external IdP is not optional, it is the sign-in
path. Entra ID plays two roles:

1. **SAML IdP** for the streaming stacks, with one enterprise application per
   stack (an application carries a single relay state, and the relay state is
   what selects the stack).
2. **Directory sync target**: Entra Connect Sync runs on a domain-joined EC2
   instance and syncs AWS Managed Microsoft AD into Entra ID, so the identity
   in the SAML assertion and the identity in the Windows session are the same
   person. That is what makes a per-user FSLogix container resolve correctly.

## Repository layout

```
bootstrap/          HCP Terraform -> AWS OIDC trust, run role, optional workspace
infra/              the environment itself (HCP Terraform workspace root)
  modules/
    network/                VPC, four subnet tiers, NAT, VPC endpoints
    directory/              AWS Managed Microsoft AD, DHCP options, secrets
    domain-join/            instance profile + State Manager seamless domain join
    fsx/                    one FSx for Windows File Server file system
    management/             management + Entra Connect servers, domain automation
    app-tier/               Windows application servers, internal ALB
    sql-rds/                RDS for SQL Server with Windows Authentication
    workspaces-applications/ image builders, fleets, stacks
    entra-saml/             Entra enterprise apps, groups, claims, IAM federation
scripts/
  ad/                 PowerShell that builds the domain and stages Entra Connect
  image/              image builder preparation
  ci/                 fmt + validate used by GitHub Actions
.github/workflows/    fmt, validate, PowerShell parse
```

## How it runs

- **HCP Terraform, VCS-driven.** A push to the tracked branch queues a plan; a
  merge queues an apply. Nothing plans or applies from a laptop, and nothing
  applies from GitHub Actions.
- **Dynamic credentials.** The workspace assumes an AWS role via OIDC workload
  identity. There are no AWS access keys anywhere. See `bootstrap/`.
- **GitHub Actions does `fmt` and `validate` only** - a fast correctness gate on
  every branch and pull request, with no cloud credentials.

## Getting started

1. Read [PREREQUISITES.md](PREREQUISITES.md) and work through it. It covers the
   things Terraform cannot do for you: HCP Terraform setup, Entra ID tenant and
   licensing, and building the two streaming images.
2. Run `bootstrap/` once, locally, with admin credentials:

   ```bash
   cd bootstrap
   cp terraform.tfvars.example terraform.tfvars   # edit it
   terraform init && terraform apply
   ```

3. Point `infra/backend.tf` at your HCP Terraform organization and workspace,
   set the workspace variables, and push. HCP Terraform takes it from there.

### The three stages

| Stage | Flip | What happens |
|---|---|---|
| 1 | defaults | Network, directory, FSx, application tier, SQL Server, management automation, Entra Connect server. The domain builds itself over the following ~15 minutes. |
| 2 | `enable_image_builders = true` | Two image builders start. Connect to each, run `Prepare-StreamingImage.ps1`, install your application, and create an image with Image Assistant. |
| 3 | `enable_streaming_fleets = true`, image names set, `enable_entra_saml = true` | Fleets, stacks, Entra enterprise applications, IAM SAML providers and roles. |

Stage 2 exists because image creation is inherently interactive. Everything on
either side of it is Terraform.

## Where the automation lives

The domain build-out is PowerShell (`scripts/ad/Configure-Domain.ps1`) delivered
through S3 and run by SSM State Manager on the management server. SSM runs as
`SYSTEM`, which cannot create OUs or GPOs in a managed directory, so a small
wrapper re-launches the script as the delegated admin via a scheduled task -
`scripts/ad/Invoke-DomainScript.ps1`. Both are idempotent and re-run hourly, so
the domain heals itself and ordering never has to be perfect.

Watch it:

```bash
aws ssm describe-association-executions --association-id "$(terraform output -raw ...)"
```

Transcripts land in `C:\ProgramData\mwa\logs` on the management server.

## Cost

This is not a free-tier sample. The large line items are AWS Managed Microsoft
AD, two Multi-AZ FSx file systems, RDS for SQL Server with an included license,
and any running streaming fleet or image builder. Stop or destroy fleets and
image builders when you are not using them - `enable_image_builders = false`
and `enable_streaming_fleets = false` remove them cleanly.

## Teardown

```bash
# in HCP Terraform: queue a destroy run, or locally with the cloud block:
terraform destroy
```

Order matters in a few places; see [docs/OPERATIONS.md](docs/OPERATIONS.md#teardown).
