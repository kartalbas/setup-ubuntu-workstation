# shellcheck shell=bash
# modules/80-containers.sh — Kubernetes and CI/CD command-line tools (H48-58),
# pinned upstream builds in ~/.local/bin. Docker (engine or CLI only, never
# Docker Desktop) is a system package (modules/05-system.sh).

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
  return 0
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
