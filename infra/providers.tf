provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

# Only used when enable_entra_saml is true. Terraform prunes unconfigured
# providers that no resource depends on, so leaving Entra disabled does not
# require Entra credentials.
#
# Authentication: set ARM_CLIENT_ID / ARM_CLIENT_SECRET (or ARM_CLIENT_CERTIFICATE_PATH)
# as environment variables on the HCP Terraform workspace, for an Entra app
# registration with Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All,
# Group.ReadWrite.All and Policy.ReadWrite.ApplicationConfiguration.
provider "azuread" {
  tenant_id = var.entra_tenant_id
}
