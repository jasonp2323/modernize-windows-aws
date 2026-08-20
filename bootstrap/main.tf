##############################################################################
# HCP Terraform -> AWS OIDC trust
#
# HCP Terraform presents a signed OIDC token to AWS STS on every plan/apply.
# No static access keys ever exist for the infra stack.
##############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  oidc_issuer_host = var.hcp_terraform_hostname
  oidc_issuer_url  = "https://${var.hcp_terraform_hostname}"

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.hcp[0].arn : var.existing_oidc_provider_arn

  # organization:<org>:project:<project>:workspace:<ws>:run_phase:<phase>
  allowed_subjects = flatten([
    for ws in var.hcp_workspace_names : [
      for phase in var.hcp_run_phases :
      "organization:${var.hcp_organization}:project:${var.hcp_project}:workspace:${ws}:run_phase:${phase}"
    ]
  ])

  run_role_name = "${var.project_name}-hcp-run"
}

resource "aws_iam_openid_connect_provider" "hcp" {
  count = var.create_oidc_provider ? 1 : 0

  url             = local.oidc_issuer_url
  client_id_list  = [var.hcp_aws_audience]
  thumbprint_list = var.oidc_thumbprint_list

  tags = {
    Name = "${var.project_name}-hcp-terraform"
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "HcpTerraformWorkloadIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = [var.hcp_aws_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_issuer_host}:sub"
      values   = local.allowed_subjects
    }
  }
}

resource "aws_iam_role" "run" {
  name                 = local.run_role_name
  description          = "Assumed by HCP Terraform runs for the modern Windows on AWS stack."
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600

  tags = {
    Name = local.run_role_name
  }
}

resource "aws_iam_role_policy_attachment" "admin" {
  count = var.use_administrator_access ? 1 : 0

  role       = aws_iam_role.run.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "scoped" {
  count = var.use_administrator_access ? 0 : 1

  role       = aws_iam_role.run.name
  policy_arn = aws_iam_policy.scoped[0].arn
}
