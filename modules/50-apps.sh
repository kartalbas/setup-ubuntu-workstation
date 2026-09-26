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
  on ANTIGRAVITY_HUB && antigravity_hub_install
  on NEOVIM && tar_app_install NEOVIM nvim "bin/nvim"
  on JETBRAINS_TOOLBOX && jetbrains_toolbox_install
  on BCOMPARE && deb_install BCOMPARE bcompare
  on FILES_OPEN_IN && files_open_in
  on NEMO && nemo_setup
  return 0
}

# files_open_in — "Open in kitty / Ghostty / Terminal (Ptyxis) / VS Code /
# Antigravity IDE" in the Files app, through a nautilus-python extension. The
# Files app loads it when it next starts.
files_open_in() {
  apt_install python3-nautilus
  render nautilus-open-in.py | atomic_write /usr/share/nautilus-python/extensions/setup-ubuntu-workstation-open-in.py 0644
  if (( CHANGED )); then log_info "Files app: the new entries appear once it restarts (close its windows, or log out and in)"; fi
  return 0
}

# nemo_setup — Nemo as the file manager, like Windows Explorer: the folder tree
# on the left, the details list on the right (templates/dconf-nemo), Ctrl+Tab
# between tabs, "Open in …" on right-click, folders open in it and it takes
# the Files app's place in the dock. Nautilus stays: GNOME uses it for the
# desktop icons and file dialogs.
nemo_setup() {
  apt_install nemo
  render dconf-nemo | dconf_defaults 62-setup-ubuntu-workstation-nemo
  nemo_open_in
  nemo_accels
  as_user xdg-mime default nemo.desktop inode/directory
  nemo_dock
  return 0
}

# "Open in …" as Nemo actions: label | program | command (%F = the folder or
# file, quoted by Nemo) | also on a single file (editors)
NEMO_OPEN_IN=(
  "kitty|kitty|kitty --directory %F|0"
  "Ghostty|ghostty|ghostty --gtk-single-instance=false --working-directory=%F|0"
  "Terminal (Ptyxis)|ptyxis|ptyxis --new-window --working-directory=%F|0"
  "VS Code|code|code %F|1"
  "Antigravity IDE|antigravity-ide|antigravity-ide %F|1"
)
NEMO_ACTIONS=/usr/share/nemo/actions
nemo_open_in() {
  local entry label program command files kind sel ext exec want=" " f
  for entry in "${NEMO_OPEN_IN[@]}"; do
    IFS='|' read -r label program command files <<<"$entry"
    for kind in folder background file; do
      case "$kind" in
        folder)     sel=s; ext='dir;'; exec="$command" ;;
        background) sel=none; ext='any;'; exec="${command//%F/%P}" ;;
        file)       [[ "$files" == 1 ]] || continue; sel=s; ext='nodirs;'; exec="$command" ;;
      esac
      f="$NEMO_ACTIONS/setup-ubuntu-workstation-$program-$kind.nemo_action"; want+="$f "
      printf '[Nemo Action]\n# %s\nName=Open in %s\nComment=Open it in %s\nExec=%s\nQuote=double\nSelection=%s\nExtensions=%s\nDependencies=%s;\n' \
        "$MANAGED_MARK" "$label" "$label" "$exec" "$sel" "$ext" "$program" | atomic_write "$f" 0644
    done
  done
  for f in "$NEMO_ACTIONS"/setup-ubuntu-workstation-*.nemo_action; do
    [[ -e "$f" && "$want" != *" $f "* ]] && run rm -f "$f"
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
  as_user mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"; [[ -f "$file" ]] && cat "$file" >"$tmp"
  for entry in "${NEMO_ACCELS[@]}"; do
    path="${entry%%|*}" key="${entry#*|}"
    grep -vF "\"$path\"" "$tmp" >"$tmp.new" || true   # nothing left is fine
    mv "$tmp.new" "$tmp"
    printf '(gtk_accel_path "%s" "%s")\n' "$path" "$key" >>"$tmp"
  done
  user_file "$file" <"$tmp"; rm -f "$tmp"
}

# nemo_dock — Nemo instead of the Files app in the dock's favourites.
nemo_dock() {
  local favs from="'org.gnome.Nautilus.desktop'" to="'nemo.desktop'"
  favs="$(as_user gsettings get org.gnome.shell favorite-apps 2>/dev/null)" || return 0
  [[ "$favs" == *"$from"* && "$favs" != *"$to"* ]] || return 0
  user_dconf write /org/gnome/shell/favorite-apps "${favs//"$from"/"$to"}"
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

# antigravity_hub_install — Antigravity 2.0, Google's agent manager next to the
# IDE, also a tarball only: in /opt/antigravity-hub-VERSION (not antigravity-*,
# which would take the IDE's folders for old versions of it), `antigravity-hub`
# on the PATH, a menu entry that also takes its antigravity:// links.
antigravity_hub_install() {
  local dir; dir="/opt/antigravity-hub-$(ver ANTIGRAVITY_HUB_VERSION)"
  tar_app_install ANTIGRAVITY_HUB antigravity-hub antigravity
  [[ "$DRY_RUN" == 1 ]] && return 0
  chown root:root "$dir/chrome-sandbox"; chmod 4755 "$dir/chrome-sandbox"
  python3 "$REPO_ROOT/tools/asar-file.py" "$dir/resources/app.asar" icon.png \
    | atomic_write /usr/local/share/icons/hicolor/512x512/apps/antigravity-hub.png 0644
  render antigravity-hub.desktop | atomic_write /usr/local/share/applications/antigravity-hub.desktop 0644
  if (( CHANGED )); then run update-desktop-database -q /usr/local/share/applications; fi
  return 0
}

# jetbrains_toolbox_install — JetBrains Toolbox manages itself and the IDEs in
# the user's home: unpacked to ~/.local/share/JetBrains/Toolbox as JetBrains'
# instructions say, and from then on it updates itself. It writes its own menu
# entry on its first start; until then the one from here.
TOOLBOX_REL=".local/share/JetBrains/Toolbox"
jetbrains_toolbox_install() {
  local dir="$TARGET_HOME/$TOOLBOX_REL" file old
  # Earlier versions of this script put it in /opt, where it cannot update itself.
  for old in /opt/jetbrains-toolbox-*; do [[ -d "$old" ]] && run rm -rf "$old"; done
  [[ -L /usr/local/bin/jetbrains-toolbox ]] && run rm -f /usr/local/bin/jetbrains-toolbox
  if [[ -x "$dir/bin/jetbrains-toolbox" ]]; then
    log_ok "JetBrains Toolbox already installed (it updates itself)"
  else
    file="$(fetch JETBRAINS_TOOLBOX)"; chmod 0644 "$file"
    as_user_sh "mkdir -p '$dir' && tar -xzf '$file' -C '$dir' --strip-components=1"
    log_ok "JetBrains Toolbox $(ver JETBRAINS_TOOLBOX_VERSION) installed in ~/$TOOLBOX_REL"
  fi
  TOOLBOX_DIR="$dir"
  [[ -e "$TARGET_HOME/.local/share/applications/jetbrains-toolbox.desktop" ]] \
    || render jetbrains-toolbox.desktop | user_file "$TARGET_HOME/.local/share/applications/jetbrains-toolbox.desktop"
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
