# shellcheck shell=bash
# modules/85-cloud.sh — cloud and infrastructure CLIs (I59-63).

cloud_setup() {
  log_step "Cloud CLIs"
  local pkgs=()
  on AZURE_CLI && pkgs+=(azure-cli)
  on GCLOUD && pkgs+=(google-cloud-cli)
  on TERRAFORM && pkgs+=(terraform)
  on VAULT && pkgs+=(vault)
  if (( ${#pkgs[@]} )); then apt_install "${pkgs[@]}"; apt_upgrade_pkgs "${pkgs[@]}"; fi
  if on MKCERT; then
    apt_install libnss3-tools     # lets mkcert -install trust its CA in Chrome/Firefox
    bin_install MKCERT mkcert
  fi
  return 0
}
