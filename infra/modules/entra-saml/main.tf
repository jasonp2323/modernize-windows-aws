##############################################################################
# Microsoft Entra ID -> WorkSpaces Applications SAML federation
#
# Domain-joined streaming fleets cannot use the AppStream user pool, so users
# have to arrive through SAML. Entra ID is the identity provider; the same
# users are synced into AWS Managed Microsoft AD by Entra Connect, so the SAML
# assertion and the Windows session resolve to the same person - which is what
# makes a per-user FSLogix container work.
#
# One Entra enterprise application per stack, because an application carries a
# single relay state and the relay state is what selects the stack.
##############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Relay state endpoint for the streaming region.
  relay_state_endpoint = "https://appstream2.${data.aws_region.current.region}.aws.amazon.com/saml"

  acs_url = "https://signin.aws.amazon.com/saml"
}

##############################################################################
# Entra ID application registration
##############################################################################

resource "azuread_application" "this" {
  for_each = var.stacks

  display_name     = "${var.display_name_prefix} ${each.value.display_name}"
  sign_in_audience = "AzureADMyOrg"

  # Entra requires a unique identifier URI per application, but AWS expects the
  # audience to be its SAML sign-in endpoint. The documented way to register
  # more than one AWS application in a tenant is to append a fragment, which
  # AWS ignores.
  identifier_uris = ["${local.acs_url}#${var.name_prefix}-${each.key}"]

  web {
    redirect_uris = [local.acs_url]
  }

  feature_tags {
    enterprise = true
  }
}

resource "azuread_service_principal" "this" {
  for_each = var.stacks

  client_id                    = azuread_application.this[each.key].client_id
  app_role_assignment_required = true

  preferred_single_sign_on_mode = "saml"

  saml_single_sign_on {
    relay_state = "${local.relay_state_endpoint}?stack=${each.value.stack_name}&accountId=${data.aws_caller_identity.current.account_id}"
  }

  feature_tags {
    enterprise = true
  }
}

# A token signing certificate is required before Entra will publish federation
# metadata for the application, and before custom claims can be issued.
resource "azuread_service_principal_token_signing_certificate" "this" {
  for_each = var.stacks

  service_principal_id = azuread_service_principal.this[each.key].id
  display_name         = "CN=${var.name_prefix}-${each.key}"
  end_date             = var.signing_certificate_end_date
}

##############################################################################
# Access groups
##############################################################################

resource "azuread_group" "this" {
  for_each = var.stacks

  display_name     = "${var.display_name_prefix} ${each.value.display_name} Users"
  description      = "Entitled to the ${each.value.stack_name} WorkSpaces Applications stack."
  security_enabled = true
  mail_enabled     = false
}

resource "azuread_app_role_assignment" "this" {
  for_each = var.stacks

  # The built-in "Default Access" role.
  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = azuread_group.this[each.key].object_id
  resource_object_id  = azuread_service_principal.this[each.key].object_id
}

##############################################################################
# Claims
#
# AWS expects three claims in the assertion: the role/provider pair, a session
# name, and (optionally) a session duration. Entra emits them through a claims
# mapping policy assigned to the service principal.
#
# Set manage_claims_mapping_policy = false to configure "Attributes & Claims"
# in the Entra portal instead.
##############################################################################

resource "azuread_claims_mapping_policy" "this" {
  for_each = var.manage_claims_mapping_policy ? var.stacks : {}

  display_name = "${var.name_prefix}-${each.key}-aws-claims"

  definition = [
    jsonencode({
      ClaimsMappingPolicy = {
        Version              = 1
        IncludeBasicClaimSet = "true"
        ClaimsSchema = [
          {
            Source        = "user"
            ID            = "userprincipalname"
            SamlClaimType = "https://aws.amazon.com/SAML/Attributes/RoleSessionName"
          },
          {
            Value         = "${aws_iam_role.federated[each.key].arn},${aws_iam_saml_provider.this[each.key].arn}"
            SamlClaimType = "https://aws.amazon.com/SAML/Attributes/Role"
          },
          {
            Value         = tostring(var.session_duration_seconds)
            SamlClaimType = "https://aws.amazon.com/SAML/Attributes/SessionDuration"
          },
        ]
      }
    })
  ]
}

resource "azuread_service_principal_claims_mapping_policy_assignment" "this" {
  for_each = var.manage_claims_mapping_policy ? var.stacks : {}

  claims_mapping_policy_id = azuread_claims_mapping_policy.this[each.key].id
  service_principal_id     = azuread_service_principal.this[each.key].id
}

##############################################################################
# AWS side of the trust
#
# The federation metadata document is public, so Terraform can fetch it and
# create the IAM identity provider without anyone downloading XML by hand.
##############################################################################

data "http" "federation_metadata" {
  for_each = var.stacks

  url = "https://login.microsoftonline.com/${var.tenant_id}/federationmetadata/2007-06/federationmetadata.xml?appid=${azuread_application.this[each.key].client_id}"

  request_headers = {
    Accept = "application/xml"
  }

  depends_on = [azuread_service_principal_token_signing_certificate.this]
}

resource "aws_iam_saml_provider" "this" {
  for_each = var.stacks

  name                   = "${var.name_prefix}-entra-${each.key}"
  saml_metadata_document = data.http.federation_metadata[each.key].response_body

  tags = merge(var.tags, { Name = "${var.name_prefix}-entra-${each.key}" })
}

data "aws_iam_policy_document" "assume_role" {
  for_each = var.stacks

  statement {
    sid     = "EntraFederation"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithSAML"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_saml_provider.this[each.key].arn]
    }

    # StringLike rather than StringEquals because the audience carries the
    # per-application fragment described above.
    condition {
      test     = "StringLike"
      variable = "SAML:aud"
      values   = ["${local.acs_url}*"]
    }
  }
}

resource "aws_iam_role" "federated" {
  for_each = var.stacks

  name                 = "${var.name_prefix}-stream-${each.key}"
  description          = "Assumed by Entra ID users streaming the ${each.value.stack_name} stack."
  assume_role_policy   = data.aws_iam_policy_document.assume_role[each.key].json
  max_session_duration = var.session_duration_seconds

  tags = merge(var.tags, { Name = "${var.name_prefix}-stream-${each.key}" })
}

data "aws_iam_policy_document" "stream" {
  for_each = var.stacks

  statement {
    sid       = "StreamStack"
    effect    = "Allow"
    actions   = ["appstream:Stream"]
    resources = [each.value.stack_arn]

    condition {
      test     = "StringEquals"
      variable = "appstream:userId"
      values   = ["$${saml:sub}"]
    }

    condition {
      test     = "StringEquals"
      variable = "saml:sub_type"
      values   = ["persistent"]
    }
  }
}

resource "aws_iam_role_policy" "stream" {
  for_each = var.stacks

  name   = "stream"
  role   = aws_iam_role.federated[each.key].id
  policy = data.aws_iam_policy_document.stream[each.key].json
}
