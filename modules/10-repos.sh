# shellcheck shell=bash
# modules/10-repos.sh — vendor apt repositories, added only for enabled tools.
# Each signing key must carry the fingerprint below (verified 2026-09-26 by
# checking the repository's InRelease signature with that key).

FPR_GITCORE="F911AB184317630C59970973E363C90F8F1B6217"    # Launchpad PPA git-core
FPR_GH="2C6106201985B60E6C7AC87323F3D4EA75716059"         # GitHub CLI
FPR_DOCKER="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"     # Docker Release (CE deb)
FPR_K8S="DE15B14486CD377B9E876E1A234654DA9A296436"        # isv:kubernetes OBS Project
FPR_HELM="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"       # Helm (Buildkite packages)
FPR_GOOGLE="EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796"     # Google Linux Packages Signing
FPR_MICROSOFT="BC528686B50D79E339D3721CEB3E94ADBE1229CF"  # Microsoft (Release signing)
FPR_CLAUDE="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"     # Anthropic Claude Code Release Signing
FPR_GOOGLE_AR="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"  # Google Artifact Registry signer
FPR_HASHICORP="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"  # HashiCorp Package Signing

repos_setup() {
  log_step "Vendor repositories"
  apt_install ca-certificates curl gnupg
  on GIT && apt_repo git-core "https://ppa.launchpadcontent.net/git-core/ppa/ubuntu" resolute main \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$FPR_GITCORE" "$FPR_GITCORE"
  on GH && apt_repo github-cli "https://cli.github.com/packages" stable main \
    "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$FPR_GH"
  { on DOCKER_CLI || on DOCKER_ENGINE; } && apt_repo docker "https://download.docker.com/linux/ubuntu" resolute stable \
    "https://download.docker.com/linux/ubuntu/gpg" "$FPR_DOCKER"
  if on KUBECTL; then
    local k8s
    k8s="https://pkgs.k8s.io/core:/stable:/v$(ver KUBECTL_MINOR)/deb/"
    apt_repo kubernetes "$k8s" "/" "" "${k8s}Release.key" "$FPR_K8S"
    # Google's cloud-sdk repository has a "kubectl" as well (a gcloud dispatcher
    # of an older kubectl) whose version epoch (1:586…) would win otherwise.
    printf '%s\n' "# Managed by setup-ubuntu-workstation: kubectl from Kubernetes' own repository." \
      "Package: kubectl" "Pin: origin pkgs.k8s.io" "Pin-Priority: 1001" \
      | atomic_write /etc/apt/preferences.d/setup-ubuntu-workstation-kubectl 0644
  fi
  on HELM && apt_repo helm "https://packages.buildkite.com/helm-linux/helm-debian/any/" any main \
    "https://packages.buildkite.com/helm-linux/helm-debian/gpgkey" "$FPR_HELM"
  # Chrome, Edge and VS Code register and maintain their own apt source (with
  # the key they ship). Only their first install goes through a bootstrap
  # source with a verified key; apps_setup then hands over to theirs.
  on CHROME && bootstrap_repo google-chrome-stable google-chrome "https://dl.google.com/linux/chrome-stable/deb/" stable main \
    "https://dl.google.com/linux/linux_signing_key.pub" "$FPR_GOOGLE"
  on EDGE && bootstrap_repo microsoft-edge-stable microsoft-edge "https://packages.microsoft.com/repos/edge-stable" stable main \
    "https://packages.microsoft.com/keys/microsoft.asc" "$FPR_MICROSOFT"
  on VSCODE && bootstrap_repo code vscode "https://packages.microsoft.com/repos/code" stable main \
    "https://packages.microsoft.com/keys/microsoft.asc" "$FPR_MICROSOFT"
  on AZURE_CLI && apt_repo azure-cli "https://packages.microsoft.com/repos/azure-cli/" resolute main \
    "https://packages.microsoft.com/keys/microsoft.asc" "$FPR_MICROSOFT"
  if on CLAUDE_CODE; then
    local ch; ch="$(cfg_get CLAUDE_CHANNEL latest)"
    [[ "$ch" == latest || "$ch" == stable ]] || die "CLAUDE_CHANNEL must be latest or stable"
    apt_repo claude-code "https://downloads.claude.ai/claude-code/apt/$ch" "$ch" main \
      "https://downloads.claude.ai/keys/claude-code.asc" "$FPR_CLAUDE"
  fi
  on ANTIGRAVITY && apt_repo antigravity "https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/" antigravity-debian main \
    "https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg" "$FPR_GOOGLE_AR"
  on GCLOUD && apt_repo google-cloud-sdk "https://packages.cloud.google.com/apt" cloud-sdk main \
    "https://packages.cloud.google.com/apt/doc/apt-key.gpg" "$FPR_GOOGLE_AR"
  { on TERRAFORM || on VAULT; } && apt_repo hashicorp "https://apt.releases.hashicorp.com" resolute main \
    "https://apt.releases.hashicorp.com/gpg" "$FPR_HASHICORP"
  legacy_repos_cleanup
  apt_update
  log_ok "Repositories ready"
}

# bootstrap_repo PKG NAME URIS SUITES COMPONENTS KEY_URL FPR — a temporary
# source for PKG's first install. Once PKG is in, its own source NAME.sources
# takes over (vendor_handover) and a leftover bootstrap source goes.
bootstrap_repo() {
  local pkg="$1" name="$2"; shift 2
  if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null)" == *"ok installed"* ]]; then
    bootstrap_drop "$name"
  else
    apt_repo "bootstrap-$name" "$@"
  fi
}
bootstrap_drop() {
  local f
  for f in "/etc/apt/sources.list.d/bootstrap-$1.sources" "/etc/apt/keyrings/bootstrap-$1.gpg"; do
    [[ -e "$f" ]] && { run rm -f "$f"; APT_UPDATED=0; }
  done
  return 0
}

# vendor_handover PKG NAME — PKG is installed: drop the bootstrap source and
# make sure PKG's own /etc/apt/sources.list.d/NAME.sources is there. When it is
# missing (VS Code skips it while another source points at its repository) or
# still one this script wrote under that name, the package's maintainer script
# writes it: Chrome and Edge rewrite an existing file or add it again when
# repo_add_once is set in /etc/default/NAME, VS Code when debconf allows it.
vendor_handover() {
  local pkg="$1" name="$2" own="/etc/apt/sources.list.d/$2.sources" defaults="/etc/default/$2"
  bootstrap_drop "$name"
  if [[ ! -f "$own" ]] || grep -qs "$MANAGED_MARK" "$own"; then
    if [[ ! -f "$own" && -f "$defaults" ]]; then
      run sed -i '/^[[:space:]]*repo_add_once=/d' "$defaults"
      echo 'repo_add_once="true"' | run tee -a "$defaults" >/dev/null
    fi
    DEBIAN_FRONTEND=noninteractive run dpkg-reconfigure -f noninteractive "$pkg"
    APT_UPDATED=0
  fi
  if [[ ! -f "$own" ]] || grep -qs "$MANAGED_MARK" "$own"; then
    die "$pkg did not register its own apt source ($own)"
  fi
  # The key this script used for that source before the handover.
  if [[ -f "/etc/apt/keyrings/$name.gpg" ]] && ! grep -rqs "keyrings/$name.gpg" /etc/apt/sources.list.d; then
    run rm -f "/etc/apt/keyrings/$name.gpg"
  fi
  log_ok "$pkg keeps its own apt source ($name.sources)"
}

# Repositories this script added under earlier names: drop the leftovers.
LEGACY_REPOS=(microsoft-vscode)
legacy_repos_cleanup() {
  local n
  for n in "${LEGACY_REPOS[@]}"; do
    if grep -qs "$MANAGED_MARK" "/etc/apt/sources.list.d/$n.sources"; then
      run rm -f "/etc/apt/sources.list.d/$n.sources"; APT_UPDATED=0
    fi
    if [[ -f "/etc/apt/keyrings/$n.gpg" ]] && ! grep -rqs "keyrings/$n.gpg" /etc/apt/sources.list.d; then
      run rm -f "/etc/apt/keyrings/$n.gpg"
    fi
  done
  return 0
}
