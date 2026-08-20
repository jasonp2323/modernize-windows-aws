terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.68"
    }
  }

  # Bootstrap intentionally uses local state. It is run once, by a human, with
  # elevated credentials, before HCP Terraform can assume any role in this
  # account. Commit the state file to a secure location or re-import as needed.
  #
  # If you would rather keep bootstrap state in HCP Terraform as well, create
  # the workspace by hand in the UI first and then uncomment:
  #
  # cloud {
  #   organization = "your-hcp-org"
  #   workspaces {
  #     name = "modernize-windows-aws-bootstrap"
  #   }
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}

# Only configured when manage_hcp_workspace = true. Reads TFE_TOKEN from the
# environment (or ~/.terraform.d/credentials.tfrc.json after `terraform login`).
provider "tfe" {
  hostname = var.hcp_terraform_hostname
}
