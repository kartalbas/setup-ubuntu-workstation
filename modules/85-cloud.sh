# shellcheck shell=bash
# modules/85-cloud.sh — cloud CLIs (I59-63), in the home: Azure CLI as a uv
# tool, Google's gcloud tarball, HashiCorp's and mkcert's release binaries.

cloud_setup() {
  log_step "Cloud"
  on AZURE_CLI && azure_cli_install
  on GCLOUD && gcloud_install
  on TERRAFORM && bin_install TERRAFORM terraform
  on VAULT && bin_install VAULT vault
  on MKCERT && bin_install MKCERT mkcert
  return 0
}

# azure_cli_install — Microsoft's azure-cli package, pinned, as a uv tool:
# `az` in ~/.local/bin, its own Python environment.
azure_cli_install() {
  local want; want="$(ver AZURE_CLI_VERSION)"
  bin_install UV uv
  if [[ "$(user_out az version --query '"azure-cli"' -o tsv 2>/dev/null)" == "$want" ]]; then
    log_ok "Azure CLI $want already installed"; return 0
  fi
  as_user uv tool install --force --python "$(ver AZURE_CLI_PYTHON)" "azure-cli==$want" >/dev/null
  log_ok "Azure CLI $want installed (uv tool)"
}

# gcloud_install — Google's tarball in ~/.local/opt, gcloud, gsutil and bq in
# ~/.local/bin; its own update check is off (update pins the next version).
gcloud_install() {
  tar_app_install GCLOUD gcloud bin/gcloud gsutil=bin/gsutil bq=bin/bq
  [[ "$DRY_RUN" == 1 ]] && return 0
  [[ "$(user_out gcloud config get component_manager/disable_update_check 2>/dev/null)" == True ]] \
    || as_user gcloud config set component_manager/disable_update_check true --quiet >/dev/null 2>&1 || true
}
