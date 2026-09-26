# shellcheck shell=bash
# modules/80-containers.sh — Docker (engine or CLI only, never Docker Desktop),
# Kubernetes and CI/CD command-line tools (H46-58).

DOCKER_CONFLICTS=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)

containers_setup() {
  log_step "Containers, Kubernetes, CI/CD"
  if on DOCKER_ENGINE || on DOCKER_CLI; then docker_setup; fi
  local pkgs=()
  on KUBECTL && pkgs+=(kubectl)
  on HELM && pkgs+=(helm)
  # Once: replace Google's kubectl dispatcher by Kubernetes' own kubectl
  # (before upgrading, which would otherwise have to go "down" from 1:586…).
  if on KUBECTL && [[ "$(installed_version kubectl)" == 1:* ]]; then
    apt_update
    DEBIAN_FRONTEND=noninteractive run apt-get install -y -q --allow-downgrades kubectl
  fi
  if (( ${#pkgs[@]} )); then apt_install "${pkgs[@]}"; apt_upgrade_pkgs "${pkgs[@]}"; fi
  on KIND && bin_install KIND kind
  on K9S && deb_install K9S k9s
  if on KUBECTX; then bin_install KUBECTX kubectx; bin_install KUBENS kubens; fi
  on STERN && bin_install STERN stern
  on KREW && krew_setup
  on CMCTL && bin_install CMCTL cmctl
  on ARGOCD && bin_install ARGOCD argocd
  on TKN && deb_install TKN tektoncd-cli
  if on ARGO; then bin_install ARGO argo; bin_install ARGO_ROLLOUTS kubectl-argo-rollouts; fi
  return 0
}

docker_setup() {
  local p remove=() pkgs=(docker-ce-cli docker-buildx-plugin docker-compose-plugin)
  for p in "${DOCKER_CONFLICTS[@]}"; do
    [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == *"ok installed"* ]] && remove+=("$p")
  done
  (( ${#remove[@]} )) && DEBIAN_FRONTEND=noninteractive run apt-get purge -y -q "${remove[@]}"
  on DOCKER_ENGINE && pkgs+=(docker-ce containerd.io)
  apt_install "${pkgs[@]}"
  apt_upgrade_pkgs "${pkgs[@]}"
  if on DOCKER_ENGINE; then
    run systemctl enable --now docker.service containerd.service >/dev/null 2>&1
    [[ " $(id -nG "$TARGET_USER") " == *" docker "* ]] || run usermod -aG docker "$TARGET_USER"
    log_ok "Docker Engine running; $TARGET_USER may use it after the next login"
  else
    log_ok "Docker CLI ready (remote hosts: docker context create NAME --docker host=ssh://USER@HOST)"
  fi
}

krew_setup() {
  local file dir
  if [[ -x "$TARGET_HOME/.krew/bin/kubectl-krew" ]]; then log_ok "krew already installed"; return 0; fi
  file="$(fetch KREW)"; chmod 0644 "$file"
  dir="$(mktemp -d)"; chmod 0755 "$dir"
  run tar -xf "$file" -C "$dir"; chmod -R a+rX "$dir"
  as_user "$dir/krew-linux_amd64" install krew >/dev/null
  rm -rf "$dir"
  log_ok "krew installed (~/.krew)"
}
