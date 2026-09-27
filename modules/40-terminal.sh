# shellcheck shell=bash
# modules/40-terminal.sh — three terminals set up to behave like Windows
# Terminal: kitty (the default, in the home) and Ghostty with PowerShell,
# Ptyxis (GNOME's own) with bash; the optional F12 drop-down (A1-3, 69).
# Ghostty and Ptyxis are system packages (sudo ./setup.sh system); their
# settings and everything of kitty live in the home.

KITTY_DESKTOP="kitty.desktop"
GHOSTTY_DESKTOP="com.mitchellh.ghostty.desktop"
QUAKE_UUID="quake-terminal@diegodario88.github.io"
PTYXIS_PROFILE="c0d4fc4f89701dfeff383ce0c3a6d53b"   # the Bash profile added to Ptyxis

terminal_setup() {
  log_step "Terminal"
  if on KITTY; then
    kitty_install
    kitty_config
  fi
  on GHOSTTY && ghostty_config
  on PTYXIS && ptyxis_setup
  default_terminal
  on QUAKE_TERMINAL && quake_terminal_install
  return 0
}

# pwsh_command — PowerShell for the terminals, by its full path (a terminal
# started from the menu may not have ~/.local/bin on its PATH yet).
pwsh_command() { printf '%s -NoLogo' "$BIN_DIR/pwsh"; }

# kitty_install — the official build (pinned, SHA-256) in
# ~/.local/opt/kitty-VERSION, kitty and kitten in ~/.local/bin, its menu entry
# and icon in ~/.local/share. The terminfo (xterm-kitty) comes from Ubuntu's
# kitty-terminfo (system part), so programs started through sudo know it too.
kitty_install() {
  local dir; dir="$OPT_DIR/kitty-$(ver KITTY_VERSION)"
  tar_app_install --flat KITTY kitty bin/kitty kitten=bin/kitten
  [[ "$DRY_RUN" == 1 ]] && return 0
  sed -E "s#^(Try)?Exec=kitty#\\1Exec=$BIN_DIR/kitty#" "$dir/share/applications/kitty.desktop" \
    | atomic_write "$APPS_DIR/$KITTY_DESKTOP"
  atomic_write "$ICONS_DIR/256x256/apps/kitty.png" <"$dir/share/icons/hicolor/256x256/apps/kitty.png"
  atomic_write "$ICONS_DIR/scalable/apps/kitty.svg" <"$dir/share/icons/hicolor/scalable/apps/kitty.svg"
  desktop_db
}

# kitty_config — the managed kitty.conf and its two helpers (profile menu,
# Windows Terminal mouse and resize behaviour); local.conf is the user's own,
# created once and never touched again.
kitty_config() {
  local dir="$TARGET_HOME/.config/kitty" profiles=() p n=0
  on PWSH && profiles+=("PowerShell|$(pwsh_command)")
  profiles+=("Bash|bash -l")
  KITTY_PROFILES="" KITTY_PROFILE_KEYS=""
  for p in "${profiles[@]}"; do
    n=$((n + 1))
    KITTY_PROFILES+="'$p|Ctrl+Shift+$n' "
    KITTY_PROFILE_KEYS+="$(printf 'map ctrl+shift+%-12s launch --type=tab %s' "$n" "${p#*|}")"$'\n'
  done
  KITTY_PROFILES="${KITTY_PROFILES% }" KITTY_PROFILE_KEYS="${KITTY_PROFILE_KEYS%$'\n'}"
  KITTY_SHELL="."; on PWSH && KITTY_SHELL="$(pwsh_command)"
  KITTY_CONFIG_DIR="$dir"
  if on VSCODE; then KITTY_EDIT_LOCAL="launch --type=background code $dir/local.conf"
  else KITTY_EDIT_LOCAL="launch --type=tab nano $dir/local.conf"; fi
  render kitty.conf | atomic_write "$dir/kitty.conf"
  render kitty-windows-terminal.py | atomic_write "$dir/windows_terminal.py"
  render kitty-profiles.sh | atomic_write "$dir/profiles.sh" 0755
  [[ -e "$dir/local.conf" ]] || render kitty-local.conf | atomic_write "$dir/local.conf"
  return 0
}

# ghostty_config — the managed config.ghostty; local.conf is the user's own,
# created once and never touched again.
ghostty_config() {
  local dir="$TARGET_HOME/.config/ghostty"
  GHOSTTY_COMMAND="# command: your login shell"
  on PWSH && GHOSTTY_COMMAND="command = $(pwsh_command)"
  render ghostty.conf | atomic_write "$dir/config.ghostty"
  [[ -e "$dir/local.conf" ]] || render ghostty-local.conf | atomic_write "$dir/local.conf"
  return 0
}

# ptyxis_setup — Ptyxis's settings where the user has none of their own (what
# is changed in its preferences stays). A user who already has Ptyxis profiles
# gets the Bash profile added and made the default once.
ptyxis_setup() {
  local uuids new
  PTYXIS_PROFILE_UUID="$PTYXIS_PROFILE"
  render dconf-ptyxis | dconf_user_defaults
  uuids="$(dconf_user_set /org/gnome/Ptyxis/profile-uuids)"
  if [[ -n "$uuids" && "$uuids" != *"'$PTYXIS_PROFILE'"* ]]; then
    if [[ "$uuids" == "@as []" ]]; then new="['$PTYXIS_PROFILE']"; else new="${uuids%]}, '$PTYXIS_PROFILE']"; fi
    user_dconf write /org/gnome/Ptyxis/profile-uuids "$new"
    user_dconf write /org/gnome/Ptyxis/default-profile-uuid "'$PTYXIS_PROFILE'"
  fi
  log_ok "Ptyxis (GNOME's terminal) set up, with bash"
}

# default_terminal — what Ctrl+Alt+T and "Open in Terminal" start (the
# freedesktop xdg-terminal-exec list, ~/.config/xdg-terminals.list).
default_terminal() {
  local desktop=""
  if on KITTY; then desktop="$KITTY_DESKTOP"
  elif on GHOSTTY; then desktop="$GHOSTTY_DESKTOP"; fi
  [[ -n "$desktop" ]] || return 0
  printf '# %s: the default terminal.\n%s\n' "$MANAGED_MARK" "$desktop" \
    | atomic_write "$TARGET_HOME/.config/xdg-terminals.list"
}

# quake_terminal_install — GNOME Shell extension in the home, pinned; F12
# drops the default terminal down from the top of the screen.
quake_terminal_install() {
  local file dir="$TARGET_HOME/.local/share/gnome-shell/extensions/$QUAKE_UUID" stamp exts
  stamp="$dir/.setup-ubuntu-workstation-version"
  if [[ "$(cat "$stamp" 2>/dev/null)" != "$(ver QUAKE_TERMINAL_VERSION)" ]]; then
    file="$(fetch QUAKE_TERMINAL)"
    run rm -rf "$dir"; run mkdir -p "$dir"
    unzip_to "$file" "$dir"
    [[ -d "$dir/schemas" ]] && run glib-compile-schemas "$dir/schemas"
    [[ "$DRY_RUN" == 1 ]] || ver QUAKE_TERMINAL_VERSION >"$stamp"
  fi
  QUAKE_APP_ID="$(grep -v '^#' "$TARGET_HOME/.config/xdg-terminals.list" 2>/dev/null | head -1)"
  render dconf-quake-terminal | dconf_user_defaults
  exts="$(dconf read /org/gnome/shell/enabled-extensions 2>/dev/null || true)"
  if [[ "$exts" != *"'$QUAKE_UUID'"* ]]; then
    if [[ -z "$exts" || "$exts" == "@as []" ]]; then exts="['$QUAKE_UUID']"; else exts="${exts%]}, '$QUAKE_UUID']"; fi
    user_dconf write /org/gnome/shell/enabled-extensions "$exts"
  fi
  log_ok "Quake Terminal ready on F12 (after the next login)"
}
