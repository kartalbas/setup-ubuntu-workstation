# shellcheck shell=bash
# modules/05-system.sh — the part that needs root, `sudo ./setup.sh system`:
# Ubuntu packages, what only comes as a system package (Chrome, Edge, VS Code,
# Chromium, Ghostty, Beyond Compare), Docker with the user in its group, the
# AppArmor profile that lets Antigravity (in the home) use Chromium's sandbox,
# and a swap file. It reads the user's config and writes nothing into the home.
# `./setup.sh install` checks that this part is there (system_check).

ANTIGRAVITY_APPARMOR="/etc/apparmor.d/setup-ubuntu-workstation-antigravity"
SWAP_FILE="/swap.img"   # the name Ubuntu's installer gives its swap file
DOCKER_CONFLICTS=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)

# system_packages — the apt packages the config asks for.
system_packages() {
  local p=()
  on GIT && p+=(git)
  on BASICS && p+=(curl wget tree htop openssl unzip xz-utils wl-clipboard)
  on BUILD_TOOLS && p+=(build-essential)
  on SEVENZIP && p+=(7zip)
  on MC && p+=(mc)
  on KITTY && p+=(kitty-terminfo)          # sudo'd programs know the terminal
  on PTYXIS && p+=(ptyxis)
  on NEMO && p+=(nemo)
  on FILES_OPEN_IN && p+=(python3-nautilus)
  on NEOVIM && p+=(vim)
  on CLAUDE_CODE && p+=(libnotify-bin)     # notify-send, for hooks
  on PSQL && p+=(postgresql-client)
  on REDIS_CLI && p+=(redis-tools)
  on MYSQL_CLIENT && p+=(mysql-client)
  on MKCERT && p+=(libnss3-tools)          # mkcert -install trusts its CA in Chrome/Firefox
  on CHROME && p+=(google-chrome-stable)
  on EDGE && p+=(microsoft-edge-stable)
  on VSCODE && p+=(code)
  if on DOCKER_CLI || on DOCKER_ENGINE; then p+=(docker-ce-cli docker-buildx-plugin docker-compose-plugin); fi
  on DOCKER_ENGINE && p+=(docker-ce containerd.io)
  (( ${#p[@]} )) && printf '%s\n' "${p[@]}" | awk '!seen[$0]++'
  return 0
}

system_setup() {
  log_step "Packages, browsers, Docker"
  local pkgs=() vendor=() p
  mapfile -t pkgs < <(system_packages)
  # VS Code registers (and keeps up to date) its own apt source.
  on VSCODE && { echo "code code/add-microsoft-repo boolean true" | run debconf-set-selections; }
  if on DOCKER_CLI || on DOCKER_ENGINE; then docker_conflicts; fi
  (( ${#pkgs[@]} )) && apt_install "${pkgs[@]}"
  # Hand over before apt reads its sources again: a bootstrap source next to
  # the vendor's own for the same repository would be a Signed-By conflict.
  on CHROME && vendor_handover google-chrome-stable google-chrome
  on EDGE && vendor_handover microsoft-edge-stable microsoft-edge
  on VSCODE && vendor_handover code vscode
  # Packages from vendor repositories: kept at their newest.
  for p in git google-chrome-stable microsoft-edge-stable code docker-ce-cli docker-buildx-plugin \
           docker-compose-plugin docker-ce containerd.io; do
    [[ " ${pkgs[*]} " == *" $p "* ]] && vendor+=("$p")
  done
  (( ${#vendor[@]} )) && apt_upgrade_pkgs "${vendor[@]}"
  if on CHROMIUM; then
    if snap list chromium >/dev/null 2>&1; then log_ok "Chromium (snap, updates itself) already installed"
    else run snap install chromium; fi
  fi
  on GHOSTTY && deb_install GHOSTTY ghostty
  on BCOMPARE && deb_install BCOMPARE bcompare
  on DOCKER_ENGINE && docker_engine
  antigravity_apparmor
  log_ok "System packages ready"
}

docker_conflicts() {
  local p remove=()
  for p in "${DOCKER_CONFLICTS[@]}"; do pkg_installed "$p" && remove+=("$p"); done
  (( ${#remove[@]} )) && DEBIAN_FRONTEND=noninteractive run apt-get purge -y -q "${remove[@]}"
  return 0
}

# docker_engine — the service running, the user in the docker group: docker
# works without sudo (after the next login).
docker_engine() {
  run systemctl enable --now docker.service containerd.service >/dev/null 2>&1
  if [[ " $(id -nG "$TARGET_USER") " == *" docker "* ]]; then log_ok "Docker Engine running, $TARGET_USER in group docker"
  else run usermod -aG docker "$TARGET_USER"; log_ok "Docker Engine running; $TARGET_USER may use it after the next login"; fi
}

# antigravity_apparmor — Ubuntu lets a program create user namespaces (which
# Chromium's sandbox needs) only when an AppArmor profile says so; Ubuntu ships
# such profiles for VS Code and Chrome, this one does the same for Antigravity
# in ~/.local/opt. It allows that and nothing else is confined.
antigravity_apparmor() {
  if on ANTIGRAVITY || on ANTIGRAVITY_HUB; then
    render apparmor-antigravity | atomic_write "$ANTIGRAVITY_APPARMOR" 0644
    if (( CHANGED )); then run apparmor_parser -r "$ANTIGRAVITY_APPARMOR"; fi
    log_ok "Antigravity may use Chromium's sandbox ($ANTIGRAVITY_APPARMOR)"
  elif [[ -f "$ANTIGRAVITY_APPARMOR" ]]; then
    run apparmor_parser -R "$ANTIGRAVITY_APPARMOR" || true
    run rm -f "$ANTIGRAVITY_APPARMOR"
  fi
  return 0
}

# swap_gb — SWAP_GB from the config, checked: a whole number of GB (0 = none).
swap_gb() {
  local gb; gb="$(cfg_get SWAP_GB 16)"
  [[ "$gb" =~ ^[0-9]+$ ]] || die "SWAP_GB is a number of GB (0 = no swap file), not: $gb"
  printf '%s' "$((10#$gb))"
}

# swap_setup — a swap file of SWAP_GB when the machine has no swap at all. /tmp
# is in RAM on Ubuntu (tmpfs); without swap a full memory makes the kernel end
# programs (the OOM killer) instead of moving idle pages, /tmp among them, out
# to the disk. A swap that is there, whatever it is, stays as it is.
swap_setup() {
  local gb free
  gb="$(swap_gb)"; (( gb > 0 )) || return 0
  log_step "Swap"
  if [[ -n "$(swapon --show=NAME --noheadings 2>/dev/null)" ]]; then
    log_ok "Swap there already: $(swapon --show=NAME,SIZE --noheadings | xargs)"; return 0
  fi
  if [[ "$(blkid -o value -s TYPE "$SWAP_FILE" 2>/dev/null)" != swap ]]; then
    free="$(df --output=avail -BG / | tail -1 | tr -dc 0-9)"
    if (( free < gb + 10 )); then
      log_warn "Swap: $gb GB do not fit on / ($free GB free) — no swap file (SWAP_GB)"; return 0
    fi
    run rm -f "$SWAP_FILE"
    if [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; then run btrfs filesystem mkswapfile --size "${gb}g" "$SWAP_FILE" >/dev/null
    else run fallocate -l "${gb}G" "$SWAP_FILE"; run chmod 0600 "$SWAP_FILE"; run mkswap "$SWAP_FILE" >/dev/null; fi
  fi
  if ! awk -v f="$SWAP_FILE" '$1 == f {found = 1} END {exit !found}' /etc/fstab; then
    { cat /etc/fstab; [[ -z "$(tail -c1 /etc/fstab)" ]] || echo; printf '%s\tnone\tswap\tsw\t0\t0\n' "$SWAP_FILE"; } \
      | atomic_write /etc/fstab 0644
  fi
  run swapon "$SWAP_FILE"
  log_ok "Swap: $SWAP_FILE, $gb GB (in /etc/fstab: on from every start)"
}

# system_check — during `./setup.sh install`: what the system part provides is
# there. What is missing is named, with the command that brings it; install
# goes on without it.
system_check() {
  local missing=() p
  while read -r p; do [[ -z "$p" ]] || pkg_installed "$p" || missing+=("$p"); done < <(system_packages)
  if on CHROMIUM && ! snap list chromium >/dev/null 2>&1; then missing+=(chromium); fi
  if on GHOSTTY && ! pkg_installed ghostty; then missing+=(ghostty); fi
  if on BCOMPARE && ! pkg_installed bcompare; then missing+=(bcompare); fi
  if { on ANTIGRAVITY || on ANTIGRAVITY_HUB; } && [[ ! -f "$ANTIGRAVITY_APPARMOR" ]]; then missing+=("Antigravity's AppArmor profile"); fi
  if on DOCKER_ENGINE && [[ " $(id -nG "$TARGET_USER") " != *" docker "* ]] \
     && ! getent group docker | grep -qE "[:,]$TARGET_USER(,|$)"; then missing+=("docker group"); fi
  if (( $(swap_gb) > 0 )) && [[ -z "$(swapon --show=NAME --noheadings 2>/dev/null)" ]]; then missing+=("swap (SWAP_GB)"); fi
  if (( ${#missing[@]} )); then
    log_warn "Not there yet from the system part: ${missing[*]}"
    log_warn "Run it once with sudo, then install again: sudo ./setup.sh system"
  else
    log_ok "System part in place"
  fi
  return 0
}
