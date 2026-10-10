# shellcheck shell=bash
# modules/80-containers.sh — Kubernetes and CI/CD command-line tools (H48-58),
# pinned upstream builds in ~/.local/bin, and Podman Desktop (H83) from Flathub.
# Docker (engine or CLI only, never Docker Desktop) is a system package
# (modules/05-system.sh).

containers_setup() {
  log_step "Kubernetes, CI/CD"
  on KUBECTL && bin_install KUBECTL kubectl
  on HELM && bin_install HELM helm
  on KIND && bin_install KIND kind
  on K9S && bin_install K9S k9s
  if on KUBECTX; then bin_install KUBECTX kubectx; bin_install KUBENS kubens; fi
  on STERN && bin_install STERN stern
  on KREW && krew_setup
  on CMCTL && bin_install CMCTL cmctl
  on ARGOCD && bin_install ARGOCD argocd
  on TKN && bin_install TKN tkn
  if on ARGO; then bin_install ARGO argo; bin_install ARGO_ROLLOUTS kubectl-argo-rollouts; fi
  on PODMAN_DESKTOP && podman_desktop_install
  return 0
}

# podman_desktop_install — Podman Desktop from Flathub into the user's own
# Flatpak installation; the system part brings the flatpak package. It reads
# the local Docker through its socket and changes nothing there, as long as
# its Podman setup is skipped and Settings > Docker Compatibility stays off:
# that setting binds Podman to Docker's socket path.
podman_desktop_install() {
  local app=io.podman_desktop.PodmanDesktop v
  if ! command -v flatpak >/dev/null; then log_warn "Podman Desktop needs flatpak: sudo ./setup.sh system"; return 0; fi
  as_user flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  if v="$(user_out flatpak info --user "$app" 2>/dev/null | sed -n 's/^ *Version: //p')" && [[ -n "$v" ]]; then
    log_ok "Podman Desktop $v (flatpak update --user updates it)"; return 0
  fi
  as_user flatpak install --user --noninteractive flathub "$app"
  log_ok "Podman Desktop installed: in the menu after the next login"
}

krew_setup() {
  local file dir
  if [[ -x "$TARGET_HOME/.krew/bin/kubectl-krew" ]]; then log_ok "krew already installed"; return 0; fi
  file="$(fetch KREW)"
  dir="$(mktemp -d)"
  run tar -xf "$file" -C "$dir"
  as_user "$dir/krew-linux_amd64" install krew >/dev/null
  rm -rf "$dir"
  log_ok "krew installed (~/.krew)"
}
