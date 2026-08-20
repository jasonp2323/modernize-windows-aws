#!/usr/bin/env bash
#
# Format check and validate every Terraform configuration in the repository.
#
# `terraform validate` needs providers, so each directory is initialised with
# -backend=false. The infra root declares a `cloud` block, which init would
# otherwise want to talk to HCP Terraform about, so the block is moved aside
# for the duration of the check. HCP Terraform remains the only thing that
# plans or applies.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "==> terraform fmt -check -recursive"
terraform fmt -check -recursive

validate_dir() {
  local dir="$1"
  echo
  echo "==> terraform init/validate: ${dir}"
  terraform -chdir="${dir}" init -backend=false -input=false -no-color
  terraform -chdir="${dir}" validate -no-color
}

CLOUD_BLOCK="infra/backend.tf"
DISABLED_BLOCK="infra/backend.tf.ci-disabled"

restore_cloud_block() {
  if [[ -f "${DISABLED_BLOCK}" ]]; then
    mv "${DISABLED_BLOCK}" "${CLOUD_BLOCK}"
  fi
}
trap restore_cloud_block EXIT

if [[ -f "${CLOUD_BLOCK}" ]]; then
  mv "${CLOUD_BLOCK}" "${DISABLED_BLOCK}"
fi

validate_dir infra
validate_dir bootstrap

# Modules are validated through the root configuration above, but validating
# them standalone catches variables that are only ever set by the root.
for module_dir in infra/modules/*/; do
  validate_dir "${module_dir%/}"
done

echo
echo "All configurations formatted and valid."
