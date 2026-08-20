##############################################################################
# Seamless domain join for EC2
#
# Any Windows instance launched with this instance profile and tagged
#   DomainJoin = <join_tag_value>
# is joined to the domain by SSM State Manager, with no credentials on the
# instance and no user data of your own. New instances pick the association up
# automatically, so scaling the app tier needs no extra plumbing.
##############################################################################

data "aws_partition" "current" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-windows-instance"
  description        = "Domain-joined Windows instances managed by SSM."
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-windows-instance" })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMDirectoryServiceAccess",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])

  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "instance" {
  dynamic "statement" {
    for_each = length(var.readable_secret_arns) > 0 ? [1] : []

    content {
      sid       = "ReadDomainSecrets"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = var.readable_secret_arns
    }
  }

  dynamic "statement" {
    for_each = var.scripts_bucket_arn == null ? [] : [1]

    content {
      sid       = "ReadAutomationScripts"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:ListBucket"]
      resources = [var.scripts_bucket_arn, "${var.scripts_bucket_arn}/*"]
    }
  }

  statement {
    sid    = "SsmAgentSupport"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ds:DescribeDirectories",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "${var.name_prefix}-windows-instance"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-windows-instance"
  role = aws_iam_role.instance.name

  tags = merge(var.tags, { Name = "${var.name_prefix}-windows-instance" })
}

##############################################################################
# State Manager association that performs the join
##############################################################################

resource "aws_ssm_association" "domain_join" {
  name                = "AWS-JoinDirectoryServiceDomain"
  association_name    = "${var.name_prefix}-domain-join"
  max_concurrency     = "50%"
  max_errors          = "25%"
  compliance_severity = "HIGH"

  parameters = {
    directoryId    = var.directory_id
    directoryName  = var.directory_name
    dnsIpAddresses = join(",", var.dns_ip_addresses)
  }

  targets {
    key    = "tag:${var.join_tag_key}"
    values = [var.join_tag_value]
  }
}
