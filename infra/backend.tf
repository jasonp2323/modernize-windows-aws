##############################################################################
# HCP Terraform, VCS-driven workflow.
#
# Runs happen in HCP Terraform, not on a laptop and not in GitHub Actions:
# a push to a tracked branch queues a plan, a merge queues an apply. AWS
# credentials come from workload identity (see ../bootstrap), so there are no
# static keys anywhere.
#
# CI strips this file before running `terraform validate` so that validation
# needs no HCP Terraform token - see scripts/ci/validate.sh.
##############################################################################

terraform {
  cloud {
    organization = "REPLACE-WITH-YOUR-HCP-ORG"

    workspaces {
      name = "modernize-windows-aws"
    }
  }
}
