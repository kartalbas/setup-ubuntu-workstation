# shellcheck shell=bash
# modules/40-terminal.sh — three terminals set up to behave like Windows
# Terminal: kitty (the default) and Ghostty with PowerShell, Ptyxis (GNOME's
# own) with bash; the optional F12 drop-down (A1-3, 69).

KITTY_DESKTOP="kitty.desktop"
GHOSTTY_DESKTOP="com.mitchellh.ghostty.desktop"
QUAKE_UUID="quake-terminal@diegodario88.github.io"
PTYXIS_PROFILE="c0d4fc4f89701dfeff383ce0c3a6d53b"   # the Bash profile added to Ptyxis

terminal_setup() {
  log_step "Terminal"
  retired_terminals_cleanup
  if on KITTY; then
    kitty_install
    kitty_config
  fi
  if on GHOSTTY; then
    deb_install GHOSTTY ghostty
    ghostty_config
  fi
  on PTYXIS && ptyxis_setup
  default_terminal
  on QUAKE_TERMINAL && quake_terminal_install
  return 0
}

# Terminals earlier versions of this script installed (package | the settings
# file it wrote): removed again where that file shows the script set them up.
RETIRED_TERMINALS=("wezterm-nightly|.config/wezterm/wezterm.lua" "contour|.config/contour/contour.yml")
retired_terminals_cleanup() {
  local entry pkg file f
  for entry in "${RETIRED_TERMINALS[@]}"; do
    pkg="${entry%%|*}" file="$TARGET_HOME/${entry#*|}"
    grep -qs "Managed by setup-ubuntu-workstation" "$file" || continue
    if [[ -n "$(installed_version "$pkg")" ]]; then
      DEBIAN_FRONTEND=noninteractive run apt-get purge --autoremove -y -q "$pkg"
    fi
    run rm -f "$file"
    run rmdir --ignore-fail-on-non-empty "$(dirname "$file")"
    log_ok "Removed $pkg: no longer part of setup-ubuntu-workstation"
  done
  for f in "$CACHE_DIR"/wezterm-nightly-*.deb "$CACHE_DIR"/contour-*.deb; do
    [[ -e "$f" ]] && run rm -f "$f"
  done
  return 0
}

# kitty_install — the official build (pinned, SHA-256) unpacked to
# /opt/kitty-VERSION; kitty and kitten linked to /usr/local/bin, its desktop
# entry and icons to /usr/local/share. The terminfo (xterm-kitty) comes from
# Ubuntu, so programs started through sudo know the terminal as well.
kitty_install() {
  local want dir file old
  want="$(ver KITTY_VERSION)"; dir="/opt/kitty-$want"
  apt_install kitty-terminfo
  if [[ -x "$dir/bin/kitty" && "$(readlink /usr/local/bin/kitty)" == "$dir/bin/kitty" ]]; then
    log_ok "kitty $want already installed"
  else
    file="$(fetch KITTY)"
    run rm -rf "$dir"; run install -d -m 0755 "$dir"
    run tar -xJf "$file" -C "$dir"
    run ln -sfn "$dir/bin/kitty" /usr/local/bin/kitty
    run ln -sfn "$dir/bin/kitten" /usr/local/bin/kitten
    for old in /opt/kitty-*; do [[ "$old" == "$dir" || ! -d "$old" ]] || run rm -rf "$old"; done
    log_ok "kitty $want installed"
  fi
  # Debian's x-terminal-emulator, used by some programs: kitty ahead of the
  # terminals packages register (Ghostty 50, Ptyxis 40).
  if ! update-alternatives --query x-terminal-emulator 2>/dev/null | grep -qx 'Alternative: /usr/local/bin/kitty'; then
    run update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/local/bin/kitty 60
  fi
  [[ "$DRY_RUN" == 1 ]] && return 0
  atomic_write "/usr/local/share/applications/$KITTY_DESKTOP" 0644 <"$dir/share/applications/kitty.desktop"
  atomic_write /usr/local/share/icons/hicolor/256x256/apps/kitty.png 0644 <"$dir/share/icons/hicolor/256x256/apps/kitty.png"
  atomic_write /usr/local/share/icons/hicolor/scalable/apps/kitty.svg 0644 <"$dir/share/icons/hicolor/scalable/apps/kitty.svg"
}

# kitty_config — the managed kitty.conf and its two helpers (profile menu,
# Windows Terminal mouse and resize behaviour); local.conf is the user's own,
# created once and never touched again.
kitty_config() {
  local dir="$TARGET_HOME/.config/kitty" profiles=() p n=0
  on PWSH && profiles+=("PowerShell|pwsh -NoLogo")
  profiles+=("Bash|bash -l")
  KITTY_PROFILES="" KITTY_PROFILE_KEYS=""
  for p in "${profiles[@]}"; do
    n=$((n + 1))
    KITTY_PROFILES+="'$p|Ctrl+Shift+$n' "
    KITTY_PROFILE_KEYS+="$(printf 'map ctrl+shift+%-12s launch --type=tab %s' "$n" "${p#*|}")"$'\n'
  done
  KITTY_PROFILES="${KITTY_PROFILES% }" KITTY_PROFILE_KEYS="${KITTY_PROFILE_KEYS%$'\n'}"
  KITTY_SHELL="."; on PWSH && KITTY_SHELL="pwsh -NoLogo"
  KITTY_CONFIG_DIR="$dir"
  if on VSCODE; then KITTY_EDIT_LOCAL="launch --type=background code $dir/local.conf"
  else KITTY_EDIT_LOCAL="launch --type=tab nano $dir/local.conf"; fi
  render kitty.conf | user_file "$dir/kitty.conf"
  render kitty-windows-terminal.py | user_file "$dir/windows_terminal.py"
  render kitty-profiles.sh | user_file "$dir/profiles.sh" 0755
  [[ -e "$dir/local.conf" ]] || render kitty-local.conf | user_file "$dir/local.conf"
  return 0
}

# ghostty_config — the managed config.ghostty; local.conf is the user's own,
# created once and never touched again.
ghostty_config() {
  local dir="$TARGET_HOME/.config/ghostty"
  GHOSTTY_COMMAND="# command: your login shell"
  on PWSH && GHOSTTY_COMMAND="command = pwsh -NoLogo"
  render ghostty.conf | user_file "$dir/config.ghostty"
  [[ -e "$dir/local.conf" ]] || render ghostty-local.conf | user_file "$dir/local.conf"
  return 0
}

# ptyxis_setup — system-wide defaults, so Ptyxis's own preferences still
# change them. A user who already has Ptyxis profiles gets the Bash profile
# added and made the default once.
ptyxis_setup() {
  local uuids new
  apt_install ptyxis
  PTYXIS_PROFILE_UUID="$PTYXIS_PROFILE"
  render dconf-ptyxis | dconf_defaults 61-setup-ubuntu-workstation-ptyxis
  uuids="$(user_out dconf read /org/gnome/Ptyxis/profile-uuids 2>/dev/null || true)"
  if [[ -n "$uuids" && "$uuids" != *"'$PTYXIS_PROFILE'"* ]]; then
    if [[ "$uuids" == "@as []" ]]; then new="['$PTYXIS_PROFILE']"; else new="${uuids%]}, '$PTYXIS_PROFILE']"; fi
    user_dconf write /org/gnome/Ptyxis/profile-uuids "$new"
    user_dconf write /org/gnome/Ptyxis/default-profile-uuid "'$PTYXIS_PROFILE'"
  fi
  log_ok "Ptyxis (GNOME's terminal) set up, with bash"
}

# default_terminal — what Ctrl+Alt+T and "Open in Terminal" start (freedesktop
# xdg-terminal-exec list, for every user).
default_terminal() {
  local desktop=""
  if on KITTY; then desktop="$KITTY_DESKTOP"
  elif on GHOSTTY; then desktop="$GHOSTTY_DESKTOP"; fi
  [[ -n "$desktop" ]] || return 0
  printf '# Managed by setup-ubuntu-workstation: the default terminal.\n%s\n' "$desktop" \
    | atomic_write /etc/xdg/xdg-terminals.list 0644
}

# quake_terminal_install — GNOME Shell extension, system-wide, pinned; F12
# drops the default terminal down from the top of the screen.
quake_terminal_install() {
  local file dir="/usr/share/gnome-shell/extensions/$QUAKE_UUID" stamp
  stamp="$dir/.setup-ubuntu-workstation-version"
  if [[ "$(cat "$stamp" 2>/dev/null)" != "$(ver QUAKE_TERMINAL_VERSION)" ]]; then
    file="$(fetch QUAKE_TERMINAL)"
    apt_install unzip
    run rm -rf "$dir"
    run install -d -m 0755 "$dir"
    run unzip -q -o "$file" -d "$dir"
    [[ -d "$dir/schemas" ]] && run glib-compile-schemas "$dir/schemas"
    [[ "$DRY_RUN" == 1 ]] || ver QUAKE_TERMINAL_VERSION >"$stamp"
  fi
  # Enabled and pointed at the default terminal for every user (dconf system db).
  QUAKE_APP_ID="$(grep -v '^#' /etc/xdg/xdg-terminals.list 2>/dev/null | head -1)"
  render dconf-quake-terminal | dconf_defaults 60-setup-ubuntu-workstation-quake
  log_ok "Quake Terminal ready on F12 (after the next login)"
}
