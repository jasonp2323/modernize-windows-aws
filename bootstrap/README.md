# Bootstrap: HCP Terraform → AWS

Run once, locally, by a human with administrative credentials. It creates the
trust that lets HCP Terraform assume a role in this AWS account without any
static access keys, and optionally the VCS-driven workspace itself.

## What it creates

- An IAM OIDC identity provider for `app.terraform.io`.
- An IAM role whose trust policy only accepts tokens whose subject matches
  `organization:<org>:project:<project>:workspace:<ws>:run_phase:<plan|apply>`.
- Either a scoped permissions policy (default) or `AdministratorAccess`
  (`use_administrator_access = true`) attached to that role.
- Optionally (`manage_hcp_workspace = true`) the HCP Terraform workspace, wired
  to this GitHub repository with `infra` as its working directory, plus the
  three environment variables that switch on dynamic credentials.

## Running it

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

export AWS_PROFILE=...             # admin credentials
export TFE_TOKEN=...               # only if manage_hcp_workspace = true

terraform init
terraform apply
```

Take `run_role_arn` from the output and set it on the workspace as
`TFC_AWS_RUN_ROLE_ARN` (along with `TFC_AWS_PROVIDER_AUTH=true`) if you did not
let this configuration manage the workspace.

## About the scoped policy

`iam.tf` grants broad access to the services this stack uses, but restricts IAM
writes to roles, policies, instance profiles and SAML providers whose names
start with `resource_name_prefix`. Keep that prefix equal to `name_prefix` in
`infra/`, or applies will fail with access denied on IAM.

State stays local here on purpose: this is the configuration that makes remote
state possible in the first place. Keep `terraform.tfstate` somewhere safe, or
import the resources later if you lose it - they are cheap to recreate.
