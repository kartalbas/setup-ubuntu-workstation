# shellcheck shell=bash
# modules/50-apps.sh — browsers, editors and IDEs (B10-15, 66-67).

apps_setup() {
  log_step "Browsers, editors, IDEs"
  local pkgs=()
  on CHROME && pkgs+=(google-chrome-stable)
  on EDGE && pkgs+=(microsoft-edge-stable)
  if on VSCODE; then
    # Let the package register (and keep up to date) its own apt source.
    echo "code code/add-microsoft-repo boolean true" | run debconf-set-selections
    pkgs+=(code)
  fi
  on NEOVIM && pkgs+=(vim)
  (( ${#pkgs[@]} )) && apt_install "${pkgs[@]}"
  # Hand over before apt reads its sources again: a bootstrap source next to
  # the vendor's one for the same repository would be a Signed-By conflict.
  on CHROME && vendor_handover google-chrome-stable google-chrome
  on EDGE && vendor_handover microsoft-edge-stable microsoft-edge
  on VSCODE && vendor_handover code vscode
  (( ${#pkgs[@]} )) && apt_upgrade_pkgs "${pkgs[@]}"
  if on CHROMIUM; then
    if snap list chromium >/dev/null 2>&1; then log_ok "Chromium (snap) already installed"
    else run snap install chromium; fi
  fi
  on ANTIGRAVITY && antigravity_ide_install
  on NEOVIM && tar_app_install NEOVIM nvim "bin/nvim"
  on JETBRAINS_TOOLBOX && tar_app_install JETBRAINS_TOOLBOX jetbrains-toolbox "bin/jetbrains-toolbox"
  on BCOMPARE && deb_install BCOMPARE bcompare
  return 0
}

# antigravity_ide_install — Antigravity IDE 2.x: Google ships it for Linux as a
# tarball only (the apt repository stays on the old 1.x line). In /opt, with
# `antigravity-ide` on the PATH, a menu entry and the handler for its
# antigravity-ide:// links (browser sign-in).
antigravity_ide_install() {
  local dir; dir="/opt/antigravity-ide-$(ver ANTIGRAVITY_VERSION)"
  tar_app_install ANTIGRAVITY antigravity-ide "bin/antigravity-ide"
  [[ "$DRY_RUN" == 1 ]] && return 0
  # Electron's sandbox helper has to be root-owned and setuid.
  chown root:root "$dir/chrome-sandbox"; chmod 4755 "$dir/chrome-sandbox"
  atomic_write /usr/local/share/icons/hicolor/512x512/apps/antigravity-ide.png 0644 \
    <"$dir/resources/app/resources/linux/code.png"
  render antigravity-ide.desktop | atomic_write /usr/local/share/applications/antigravity-ide.desktop 0644
  render antigravity-ide-url-handler.desktop \
    | atomic_write /usr/local/share/applications/antigravity-ide-url-handler.desktop 0644
  if (( CHANGED )); then run update-desktop-database -q /usr/local/share/applications; fi
  return 0
}

# tar_app_install KEY NAME BINARY — unpack a pinned tarball to /opt/NAME-VERSION
# and link its BINARY (path inside the archive, below its top directory) to
# /usr/local/bin/NAME. Older versions are removed.
tar_app_install() {
  local key="$1" name="$2" bin="$3" want dir file
  want="$(ver "${key}_VERSION")"; dir="/opt/$name-$want"
  if [[ -x "$dir/$bin" && "$(readlink /usr/local/bin/"$name")" == "$dir/$bin" ]]; then
    # Unpacked earlier with the archive's owners (before --no-same-owner).
    if [[ -n "$(find "$dir" ! -user root -print -quit)" ]]; then run chown -R root:root "$dir"; fi
    log_ok "$name $want already installed"; return 0
  fi
  file="$(fetch "$key")"
  run rm -rf "$dir"; run install -d -m 0755 "$dir"
  run tar -xf "$file" -C "$dir" --strip-components=1 --no-same-owner
  run ln -sfn "$dir/$bin" "/usr/local/bin/$name"
  local old
  for old in /opt/"$name"-*; do [[ "$old" == "$dir" || ! -d "$old" ]] || run rm -rf "$old"; done
  log_ok "$name $want installed"
}
