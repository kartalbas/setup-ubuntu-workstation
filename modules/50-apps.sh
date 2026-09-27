# shellcheck shell=bash
# modules/50-apps.sh — IDEs, the Files app, Nemo and the dock, in the home
# (B11-15, 72-73, 75). Chrome, Edge, VS Code, Chromium and Beyond Compare are
# system packages (modules/05-system.sh).

apps_setup() {
  log_step "IDEs, Files app, dock"
  on ANTIGRAVITY && antigravity_ide_install
  on ANTIGRAVITY_HUB && antigravity_hub_install
  on NEOVIM && tar_app_install NEOVIM nvim bin/nvim
  on JETBRAINS_TOOLBOX && jetbrains_toolbox_install
  on FILES_OPEN_IN && files_open_in
  on NEMO && nemo_setup
  dock_setup
  return 0
}

# antigravity_ide_install — Antigravity IDE 2.x: Google ships it for Linux as a
# tarball only. In ~/.local/opt, `antigravity-ide` in ~/.local/bin, a menu
# entry and the handler for its antigravity-ide:// links (browser sign-in).
# Chromium's sandbox works through the AppArmor profile of the system part.
antigravity_ide_install() {
  local dir; dir="$OPT_DIR/antigravity-ide-$(ver ANTIGRAVITY_VERSION)"
  tar_app_install ANTIGRAVITY antigravity-ide bin/antigravity-ide
  [[ "$DRY_RUN" == 1 ]] && return 0
  atomic_write "$ICONS_DIR/512x512/apps/antigravity-ide.png" <"$dir/resources/app/resources/linux/code.png"
  ANTIGRAVITY_IDE_BIN="$BIN_DIR/antigravity-ide"
  render antigravity-ide.desktop | atomic_write "$APPS_DIR/antigravity-ide.desktop"
  render antigravity-ide-url-handler.desktop | atomic_write "$APPS_DIR/antigravity-ide-url-handler.desktop"
  desktop_db
}

# antigravity_hub_install — Antigravity 2.0, Google's agent manager next to the
# IDE, also a tarball only: in ~/.local/opt/antigravity-hub-VERSION (not
# antigravity-*, which would take the IDE's folders for old versions of it),
# `antigravity-hub` in ~/.local/bin, a menu entry that takes its antigravity://
# links.
antigravity_hub_install() {
  local dir; dir="$OPT_DIR/antigravity-hub-$(ver ANTIGRAVITY_HUB_VERSION)"
  tar_app_install ANTIGRAVITY_HUB antigravity-hub antigravity
  [[ "$DRY_RUN" == 1 ]] && return 0
  python3 "$REPO_ROOT/tools/asar-file.py" "$dir/resources/app.asar" icon.png \
    | atomic_write "$ICONS_DIR/512x512/apps/antigravity-hub.png"
  ANTIGRAVITY_HUB_BIN="$BIN_DIR/antigravity-hub"
  render antigravity-hub.desktop | atomic_write "$APPS_DIR/antigravity-hub.desktop"
  desktop_db
}

# jetbrains_toolbox_install — JetBrains Toolbox manages itself and the IDEs in
# the user's home: unpacked to ~/.local/share/JetBrains/Toolbox as JetBrains'
# instructions say, and from then on it updates itself. It writes its own menu
# entry on its first start; until then the one from here.
TOOLBOX_REL=".local/share/JetBrains/Toolbox"
jetbrains_toolbox_install() {
  local dir="$TARGET_HOME/$TOOLBOX_REL" file
  if [[ -x "$dir/bin/jetbrains-toolbox" ]]; then
    log_ok "JetBrains Toolbox already installed (it updates itself)"
  else
    file="$(fetch JETBRAINS_TOOLBOX)"
    run mkdir -p "$dir"; run tar -xzf "$file" -C "$dir" --strip-components=1
    log_ok "JetBrains Toolbox $(ver JETBRAINS_TOOLBOX_VERSION) installed in ~/$TOOLBOX_REL"
  fi
  TOOLBOX_DIR="$dir"
  [[ -e "$APPS_DIR/jetbrains-toolbox.desktop" ]] \
    || render jetbrains-toolbox.desktop | atomic_write "$APPS_DIR/jetbrains-toolbox.desktop"
  return 0
}

# files_open_in — "Open in kitty / Ghostty / Terminal (Ptyxis) / VS Code /
# Antigravity IDE" in the Files app, through a nautilus-python extension in
# ~/.local/share (python3-nautilus: system part). The Files app loads it when
# it next starts.
files_open_in() {
  render nautilus-open-in.py \
    | atomic_write "$TARGET_HOME/.local/share/nautilus-python/extensions/setup-ubuntu-workstation-open-in.py"
  if (( CHANGED )); then log_info "Files app: the new entries appear once it restarts (close its windows, or log out and in)"; fi
  return 0
}

# nemo_setup — Nemo as the file manager, like Windows Explorer: the folder tree
# on the left, the details list on the right (templates/dconf-nemo), Ctrl+Tab
# between tabs, "Open in …" and "Copy as path" on right-click, folders open in
# it. Nautilus stays: GNOME uses it for the desktop icons and file dialogs.
nemo_setup() {
  local key=/org/cinnamon/desktop/applications/terminal
  case "$(default_terminal_id)" in
    kitty)   NEMO_TERMINAL="$BIN_DIR/kitty" NEMO_TERMINAL_ARG="-e" ;;
    ghostty) NEMO_TERMINAL="ghostty" NEMO_TERMINAL_ARG="-e" ;;
    ptyxis)  NEMO_TERMINAL="ptyxis" NEMO_TERMINAL_ARG="--" ;;
    *)       NEMO_TERMINAL="x-terminal-emulator" NEMO_TERMINAL_ARG="-e" ;;
  esac
  render dconf-nemo | dconf_user_defaults
  # Nemo's terminal follows DEFAULT_TERMINAL while it is one this setup chose.
  case "$(dconf_user_set "$key/exec")" in
    "'$BIN_DIR/kitty'"|"'ghostty'"|"'ptyxis'"|"'x-terminal-emulator'")
      if [[ "$(dconf_user_set "$key/exec")" != "'$NEMO_TERMINAL'" ]]; then
        user_dconf write "$key/exec" "'$NEMO_TERMINAL'"; user_dconf write "$key/exec-arg" "'$NEMO_TERMINAL_ARG'"
      fi ;;
  esac
  NEMO_WANT=" "
  nemo_open_in
  nemo_copy_path
  nemo_actions_prune
  nemo_accels
  run xdg-mime default nemo.desktop inode/directory
  return 0
}

# "Open in …" as Nemo actions: label | program | command (%F = the folder or
# file, quoted by Nemo) | also on a single file (editors). @BIN@ = ~/.local/bin.
NEMO_OPEN_IN=(
  "kitty|@BIN@/kitty|@BIN@/kitty --directory %F|0"
  "Ghostty|ghostty|ghostty --gtk-single-instance=false --working-directory=%F|0"
  "Terminal (Ptyxis)|ptyxis|ptyxis --new-window --working-directory=%F|0"
  "VS Code|code|code %F|1"
  "Antigravity IDE|@BIN@/antigravity-ide|@BIN@/antigravity-ide %F|1"
)
NEMO_ACTIONS_REL=".local/share/nemo/actions"
nemo_open_in() {
  local dir="$TARGET_HOME/$NEMO_ACTIONS_REL" entry label program command files kind sel ext exec f
  for entry in "${NEMO_OPEN_IN[@]}"; do
    entry="${entry//@BIN@/$BIN_DIR}"
    IFS='|' read -r label program command files <<<"$entry"
    for kind in folder background file; do
      case "$kind" in
        folder)     sel=s; ext='dir;'; exec="$command" ;;
        background) sel=none; ext='any;'; exec="${command//%F/%P}" ;;
        file)       [[ "$files" == 1 ]] || continue; sel=s; ext='nodirs;'; exec="$command" ;;
      esac
      f="$dir/setup-ubuntu-workstation-${program##*/}-$kind.nemo_action"; NEMO_WANT+="$f "
      printf '[Nemo Action]\n# %s\nName=Open in %s\nComment=Open it in %s\nExec=%s\nQuote=double\nSelection=%s\nExtensions=%s\nDependencies=%s;\n' \
        "$MANAGED_MARK" "$label" "$label" "$exec" "$sel" "$ext" "$program" | atomic_write "$f"
    done
  done
  return 0
}

# nemo_copy_path — "Copy as path" on right-click and Ctrl+Shift+C: the full
# path of every selected item to the clipboard, one per line, without quotes
# (templates/nemo-copy-path.sh, wl-copy). The shortcut goes into Nemo's action
# layout (~/.config/nemo/actions-tree.json) unless the action is there already.
NEMO_COPY_PATH="setup-ubuntu-workstation-copy-path"
nemo_copy_path() {
  local dir="$TARGET_HOME/$NEMO_ACTIONS_REL" f added
  render nemo-copy-path.sh | atomic_write "$dir/$NEMO_COPY_PATH.sh" 0755
  f="$dir/$NEMO_COPY_PATH.nemo_action"; NEMO_WANT+="$f "
  printf '[Nemo Action]\n# %s\nName=Copy as path\nComment=Copy the full path of the selection, one per line\nExec=<%s.sh %%F>\nSelection=notnone\nExtensions=any;\nDependencies=wl-copy;\n' \
    "$MANAGED_MARK" "$NEMO_COPY_PATH" | atomic_write "$f"
  [[ "$DRY_RUN" == 1 ]] && return 0
  if added="$(python3 "$REPO_ROOT/tools/nemo-action-accel.py" "$TARGET_HOME/.config/nemo/actions-tree.json" \
       "$NEMO_COPY_PATH.nemo_action" "<Primary><Shift>c")"; then
    [[ -z "$added" ]] || log_ok "Nemo: Copy as path on Ctrl+Shift+C (it takes effect when Nemo starts again)"
  else
    log_warn "Nemo: ~/.config/nemo/actions-tree.json cannot be read — no shortcut for Copy as path"
  fi
  return 0
}

# nemo_actions_prune — actions this setup wrote earlier and no longer writes.
nemo_actions_prune() {
  local f
  for f in "$TARGET_HOME/$NEMO_ACTIONS_REL"/setup-ubuntu-workstation-*.nemo_action; do
    [[ -e "$f" && "$NEMO_WANT" != *" $f "* ]] && run rm -f "$f"
  done
  return 0
}

# Explorer's keys where Nemo's differ and can be changed: Ctrl+Tab and
# Ctrl+Shift+Tab switch tabs. (Backspace goes up and F3 opens the extra pane:
# both are fixed in Nemo; Alt+Left goes back, Ctrl+F searches.)
NEMO_ACCELS=(
  "<Actions>/ShellActions/TabsNext|<Primary>Tab"
  "<Actions>/ShellActions/TabsPrevious|<Primary><Shift>Tab"
)
nemo_accels() {
  local file="$TARGET_HOME/.gnome2/accels/nemo" entry path key tmp
  tmp="$(mktemp)"; [[ -f "$file" ]] && cat "$file" >"$tmp"
  for entry in "${NEMO_ACCELS[@]}"; do
    path="${entry%%|*}" key="${entry#*|}"
    grep -vF "\"$path\"" "$tmp" >"$tmp.new" || true   # nothing left is fine
    mv "$tmp.new" "$tmp"
    printf '(gtk_accel_path "%s" "%s")\n' "$path" "$key" >>"$tmp"
  done
  atomic_write "$file" <"$tmp"; rm -f "$tmp"
}

# dock_setup — the dock's favourites: DOCK from the config (desktop entry ids
# separated by spaces), where the user has not arranged the dock on this
# machine yet. Without DOCK, Nemo takes the Files app's place in it.
dock_setup() {
  local dock id list="" favs from="'org.gnome.Nautilus.desktop'" to="'nemo.desktop'"
  dock="$(cfg_get DOCK)"
  if [[ -n "$dock" ]]; then
    if [[ -n "$(dconf_user_set /org/gnome/shell/favorite-apps)" ]]; then
      log_ok "Dock: arranged on this machine already, left as it is"; return 0
    fi
    for id in $dock; do list+="${list:+, }'$id'"; done
    user_dconf write /org/gnome/shell/favorite-apps "[$list]"
    log_ok "Dock: $dock"
  elif on NEMO; then
    favs="$(dconf read /org/gnome/shell/favorite-apps 2>/dev/null)" || return 0
    [[ "$favs" == *"$from"* && "$favs" != *"$to"* ]] || return 0
    user_dconf write /org/gnome/shell/favorite-apps "${favs//"$from"/"$to"}"
  fi
  return 0
}

# dock_current — the dock's favourites now, as DOCK takes them (for configs save).
dock_current() {
  dconf read /org/gnome/shell/favorite-apps 2>/dev/null | tr -d "[],'" | xargs
}
