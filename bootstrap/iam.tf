##############################################################################
# Scoped permissions for the run role.
#
# Deliberately service-broad but IAM-narrow: the stack creates instance
# profiles and service roles, so it needs IAM write, but only under a name
# prefix it owns.
##############################################################################

data "aws_iam_policy_document" "scoped" {
  count = var.use_administrator_access ? 0 : 1

  statement {
    sid    = "CoreServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "autoscaling:*",
      "ds:*",
      "fsx:*",
      "rds:*",
      "appstream:*",
      "workspaces:*",
      "ssm:*",
      "secretsmanager:*",
      "kms:*",
      "logs:*",
      "cloudwatch:*",
      "route53resolver:*",
      "route53:*",
      "s3:*",
      "sts:GetCallerIdentity",
      "tag:*",
      "servicequotas:Get*",
      "servicequotas:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IamRead"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*",
      "iam:SimulatePrincipalPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IamManagePrefixedPrincipals"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
      "iam:CreateSAMLProvider",
      "iam:UpdateSAMLProvider",
      "iam:DeleteSAMLProvider",
      "iam:TagSAMLProvider",
      "iam:UntagSAMLProvider",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.resource_name_prefix}-*",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.resource_name_prefix}-*",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.resource_name_prefix}-*",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:saml-provider/${var.resource_name_prefix}-*",
    ]
  }

  statement {
    sid    = "PassPrefixedRoles"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.resource_name_prefix}-*",
    ]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "appstream.amazonaws.com",
        "application-autoscaling.amazonaws.com",
        "ds.amazonaws.com",
        "fsx.amazonaws.com",
        "s3.data-source.lustre.fsx.amazonaws.com",
        "rds.amazonaws.com",
        "ssm.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "autoscaling.amazonaws.com",
        "workspaces.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_policy" "scoped" {
  count = var.use_administrator_access ? 0 : 1

  name        = "${var.project_name}-hcp-run"
  description = "Permissions HCP Terraform needs to build the modern Windows on AWS stack."
  policy      = data.aws_iam_policy_document.scoped[0].json
}
