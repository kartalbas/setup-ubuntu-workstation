# shellcheck shell=bash
# modules/45-desktop.sh — Windows' desktop habits on GNOME, in the home (A78-80):
# Windows' keys where GNOME's differ (templates/dconf-windows-keys), a
# clipboard history on Win+V, "New Document" on right-click in the file
# managers. Settings are written only where you have not set them yourself.

CLIPBOARD_UUID="clipboard-indicator@tudmotu.com"
# Ctrl+Shift+Esc: a custom shortcut of GNOME's (Settings → Keyboard → Custom Shortcuts)
TASK_MANAGER_KEY="org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/setup-ubuntu-workstation-task-manager"
NEW_DOCUMENTS_FILES=("Text file.txt" "Markdown.md")

desktop_setup() {
  log_step "Desktop: Windows keys, clipboard history, New Document"
  on WINDOWS_KEYS && windows_keys
  on CLIPBOARD_HISTORY && clipboard_history_install
  on NEW_DOCUMENTS && new_documents
  return 0
}

# windows_keys — Win+R runs a command, Ctrl+Esc opens the overview (the Start
# menu's place), Win+Shift+S takes a screenshot, Win+D shows the desktop,
# Alt+Tab switches windows (Win+Tab applications), Win+I opens the settings,
# Ctrl+Shift+Esc the task manager (Resources).
windows_keys() {
  local list key="/$TASK_MANAGER_KEY/"
  windows_keys_file | dconf_user_defaults
  # The custom shortcut joins the list of yours.
  list="$(dconf_user_set /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings)"
  if [[ "$list" != *"'$key'"* ]]; then
    if [[ -z "$list" || "$list" == "@as []" ]]; then list="['$key']"; else list="${list%]}, '$key']"; fi
    user_dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "$list"
  fi
  log_ok "Windows keys: Win+R, Ctrl+Esc, Win+Shift+S, Win+D, Alt+Tab, Win+I, Ctrl+Shift+Esc"
}

# windows_keys_file — templates/dconf-windows-keys, filled in.
windows_keys_file() {
  TASK_MANAGER="resources"; have resources || TASK_MANAGER="gnome-system-monitor"
  render dconf-windows-keys
}

# clipboard_history_install — the GNOME extension Clipboard Indicator, pinned:
# Win+V opens the history (GNOME's notification list keeps Win+M), and the
# entry chosen is pasted where you type, as on Windows: the extension presses
# Shift+Insert, in a terminal Ctrl+Shift+Insert, and both paste the clipboard
# in kitty, Ghostty and Ptyxis. Its own shortcuts on Ctrl+F8…F12 are off:
# they would take those keys from every application. It loads at the next login.
clipboard_history_install() {
  gnome_extension_install CLIPBOARD_INDICATOR "$CLIPBOARD_UUID" || return 0
  dconf_user_defaults <<'KEYS'
[org/gnome/shell/extensions/clipboard-indicator]
toggle-menu=['<Super>v']
paste-on-select=true
clear-history=@as []
prev-entry=@as []
next-entry=@as []
private-mode-binding=@as []

[org/gnome/shell/keybindings]
toggle-message-tray=['<Super>m']
KEYS
  log_ok "Clipboard history on Win+V (after the next login)"
}

# new_documents — right-click → New Document offers a text and a Markdown file
# (templates in your templates folder, ~/Templates); files of yours stay.
new_documents() {
  local dir f new=""
  dir="$(xdg-user-dir TEMPLATES 2>/dev/null)" || dir="$TARGET_HOME/Templates"
  if [[ "${dir%/}" == "$TARGET_HOME" ]]; then
    log_info "New Document: you have no templates folder (XDG_TEMPLATES_DIR is your home) — nothing added"; return 0
  fi
  for f in "${NEW_DOCUMENTS_FILES[@]}"; do
    [[ -e "$dir/$f" ]] && continue
    : | atomic_write "$dir/$f"; new+="${new:+, }$f"
  done
  log_ok "New Document: templates in ${dir/#$TARGET_HOME/\~}${new:+ (new: $new)}"
}
