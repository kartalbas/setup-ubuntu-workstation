# shellcheck shell=bash
# modules/10-repos.sh — vendor apt repositories (system part), added only for
# enabled tools that come as system packages. Each signing key must carry the
# fingerprint below (verified 2026-09-26 by checking the repository's InRelease
# signature with that key).

FPR_GITCORE="F911AB184317630C59970973E363C90F8F1B6217"    # Launchpad PPA git-core
FPR_DOCKER="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"     # Docker Release (CE deb)
FPR_GOOGLE="EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796"     # Google Linux Packages Signing
FPR_MICROSOFT="BC528686B50D79E339D3721CEB3E94ADBE1229CF"  # Microsoft (Release signing)

repos_setup() {
  log_step "Vendor repositories"
  apt_install ca-certificates curl gnupg
  on GIT && apt_repo git-core "https://ppa.launchpadcontent.net/git-core/ppa/ubuntu" resolute main \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$FPR_GITCORE" "$FPR_GITCORE"
  { on DOCKER_CLI || on DOCKER_ENGINE; } && apt_repo docker "https://download.docker.com/linux/ubuntu" resolute stable \
    "https://download.docker.com/linux/ubuntu/gpg" "$FPR_DOCKER"
  # Chrome, Edge and VS Code register and maintain their own apt source (with
  # the key they ship). Only their first install goes through a bootstrap
  # source with a verified key; system_setup then hands over to theirs.
  on CHROME && bootstrap_repo google-chrome-stable google-chrome "https://dl.google.com/linux/chrome-stable/deb/" stable main \
    "https://dl.google.com/linux/linux_signing_key.pub" "$FPR_GOOGLE"
  on EDGE && bootstrap_repo microsoft-edge-stable microsoft-edge "https://packages.microsoft.com/repos/edge-stable" stable main \
    "https://packages.microsoft.com/keys/microsoft.asc" "$FPR_MICROSOFT"
  on VSCODE && bootstrap_repo code vscode "https://packages.microsoft.com/repos/code" stable main \
    "https://packages.microsoft.com/keys/microsoft.asc" "$FPR_MICROSOFT"
  apt_update
  log_ok "Repositories ready"
}

# bootstrap_repo PKG NAME URIS SUITES COMPONENTS KEY_URL FPR — a temporary
# source for PKG's first install. Once PKG is in, its own source NAME.sources
# takes over (vendor_handover) and a leftover bootstrap source goes.
bootstrap_repo() {
  local pkg="$1" name="$2"; shift 2
  if pkg_installed "$pkg"; then bootstrap_drop "$name"
  else apt_repo "bootstrap-$name" "$@"; fi
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
# missing (VS Code skips it while another source points at its repository),
# the package's maintainer script writes it: Chrome and Edge add it again when
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
  log_ok "$pkg keeps its own apt source ($name.sources)"
}
