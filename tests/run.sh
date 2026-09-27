#!/usr/bin/env bash
# tests/run.sh — lint + unit tests of the helpers. Needs no root, changes
# nothing on the machine. Requires shellcheck.
# `cond && ok … || bad …` is safe here: ok/bad always succeed.
# shellcheck disable=SC2015
set -uo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  ✗ %s\n' "$1"; }
eq()  { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1: expected [$3], got [$2]"; fi; }

echo "shellcheck"
if ! command -v shellcheck >/dev/null; then bad "shellcheck is not installed (sudo apt install shellcheck)"
elif shellcheck -x -s bash setup.sh lib/*.sh modules/*.sh tests/run.sh tools/*.sh templates/*.sh; then ok "clean"
else bad "findings above"; fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CONFIG_FILE="$tmp/config.conf"
cp config.example.conf "$CONFIG_FILE"
# shellcheck source=lib/common.sh
. lib/common.sh
set +e; trap - ERR
for m in modules/*.sh; do
  # shellcheck source=/dev/null
  . "$m"
done
atomic_write() { local t; mkdir -p "$(dirname "$1")"; t="$(mktemp)"; cat >"$t"; mv "$t" "$1"; CHANGED=1; }   # no chmod/log
cfg_load; ver_load

echo "config"
eq "defaults parse (value before # comment)" "$(cfg_get KITTY)" "1"
eq "string value" "$(cfg_get CLAUDE_CHANNEL)" "latest"
eq "empty string value" "$(cfg_get GIT_USER_NAME)x" "x"
cfg_set KIND 1 >/dev/null 2>&1; cfg_load
eq "cfg_set changes a value" "$(cfg_get KIND)" "1"
grep -q '^KIND="1" *# 50' "$CONFIG_FILE" && ok "cfg_set keeps the comment" || bad "cfg_set lost the comment: $(grep '^KIND=' "$CONFIG_FILE")"
( cfg_set NO_SUCH 1 ) >/dev/null 2>&1 && bad "unknown key accepted" || ok "unknown key rejected"
( grep -v '^GHOSTTY=' "$CONFIG_FILE"; echo 'RETIRED_TOOL="1" # 99 gone' ) >"$tmp/merge.conf"
( CONFIG_FILE="$tmp/merge.conf"; cfg_init ) >/dev/null 2>&1
grep -q '^GHOSTTY=1 *# 2' "$tmp/merge.conf" && ok "config learns new settings" || bad "new setting not appended"
grep -q '^RETIRED_TOOL=' "$tmp/merge.conf" && bad "removed setting kept" || ok "config drops removed settings"
while read -r key; do
  grep -rqE "(on|cfg_get) \"?$key\b" modules setup.sh || bad "config key $key is used nowhere"
done < <(grep -oE '^[A-Z0-9_]+' config.example.conf | grep -vE '^GIT_USER_(NAME|EMAIL)$')   # those two: cfg_get "GIT_USER_${key^^}"
ok "every config key is used"

echo "versions"
while read -r k; do
  p="${k%_URL}"
  [[ -n "${VER[${p}_VERSION]:-}" ]] || bad "$p has no version"
  [[ "${VER[${p}_SHA256]:-}" =~ ^[0-9a-f]{64}$ || "${VER[${p}_SHA512]:-}" =~ ^[0-9a-f]{128}$ ]] \
    || bad "$p has no checksum"
done < <(grep -oE '^[A-Z_]+_URL' versions.conf)
ok "every pinned URL has a version and a checksum"

echo "templates"
TARGET_HOME="$tmp/u"; set_paths; CFG[PWSH]=1 CFG[VSCODE]=0
K="$TARGET_HOME/.config/kitty" PW="$BIN_DIR/pwsh -NoLogo"
kitty_config
eq "kitty.conf gets the shell (by its path)" "$(grep -cxF "shell                       $PW" "$K/kitty.conf")" "1"
eq "kitty.conf maps the profiles" "$(grep -cxE "map ctrl\+shift\+(1  *launch --type=tab ${PW//./\\.}|2  *launch --type=tab bash -l)" "$K/kitty.conf")" "2"
grep -qF "profiles.sh 'PowerShell|$PW|Ctrl+Shift+1' 'Bash|bash -l|Ctrl+Shift+2'" "$K/kitty.conf" \
  && ok "kitty.conf passes the profiles to the menu" || bad "profile menu line: $(grep profiles.sh "$K/kitty.conf")"
grep -qxE "map ctrl\+comma  *launch --type=tab nano $K/local.conf" "$K/kitty.conf" \
  && ok "Ctrl+, edits local.conf" || bad "Ctrl+, line: $(grep ctrl+comma "$K/kitty.conf")"
python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$K/windows_terminal.py" \
  && ok "kitty helper compiles" || bad "kitty helper does not compile"
python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' tools/opencode-llms.py \
  && python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); assert set(c["provider"]) == {"llm1", "llm2"}' templates/opencode.json \
  && ok "OpenCode template (llm1, llm2) and helper are valid" || bad "OpenCode template or helper broken"
grep -qiE 'https?://[a-z0-9-]+\.[a-z]|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' <(grep -v 'opencode.ai/config.json' templates/opencode.json) \
  && bad "OpenCode template has a real host" || ok "OpenCode template has placeholders only"
ghostty_config
eq "config.ghostty gets the shell (by its path)" "$(grep -cxF "command = $PW" "$TARGET_HOME/.config/ghostty/config.ghostty")" "1"
eq "config.ghostty loads local.conf" "$(grep -c '^config-file = ?local.conf$' "$TARGET_HOME/.config/ghostty/config.ghostty")" "1"
PTYXIS_PROFILE_UUID=0123abcd
eq "Ptyxis defaults name the Bash profile" "$(render dconf-ptyxis | grep -c "^default-profile-uuid='0123abcd'$\|^label='Bash'$")" "2"
CFG[STARSHIP]=1; bash_block
bash -n "$TARGET_HOME/.bashrc" && ok "bash block (starship) is valid bash" || bad "bash block (starship) has a syntax error"
eq "tab title: directory name" "$(cd /usr/local && bash -c '. <(grep "^__tab_title" "$1"); __tab_title' _ "$TARGET_HOME/.bashrc" | od -An -c | tr -s ' ')" " 033 ] 0 ; l o c a l \a"
CFG[STARSHIP]=0; bash_block
bash -n "$TARGET_HOME/.bashrc" && ok "bash block (no starship) is valid bash" || bad "bash block (no starship) has a syntax error"
# shellcheck disable=SC2016  # PS1 as Ubuntu's ~/.bashrc leaves it, before our block
eq "Ubuntu's user@host title is dropped" "$(bash -c 'PS1="\[\e]0;\u@\h: \w\a\]\u@\h:\w\$ "; eval "$(grep "^PS1=" "$1")"; printf %s "$PS1"' _ "$TARGET_HOME/.bashrc")" '\u@\h:\w$ '
miss=""
while read -r p; do [[ -n "${PIN_APPLY[$p]:-}" ]] || miss+=" $p"; done < <(grep -oE '^[A-Z0-9_]+_(VERSION|MINOR)=' versions.conf | sed -E 's/_(VERSION|MINOR)=//')
eq "update knows how to apply every pinned tool" "${miss:-none}" "none"
printf 'KITTY_VERSION="999.0"\nKITTY_URL="u"\nKITTY_SHA256="s"\nPWSH_VERSION="0.1"\n' >"$tmp/vl.conf"
( VERSIONS_LOCAL="$tmp/vl.conf"; ver_load; printf '%s %s' "$(ver KITTY_VERSION)" "$(ver PWSH_VERSION)" ) >"$tmp/vl.out"
eq "versions.local.conf: newer wins, older is ignored" "$(cut -d' ' -f1 "$tmp/vl.out") $(grep -c '^PWSH_VERSION="0.1"' versions.conf)" "999.0 0"
python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' templates/nautilus-open-in.py \
  && ok "Files app extension compiles" || bad "Files app extension does not compile"
for t in tools/claude-llm tools/asar-file.py; do
  python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$t" && ok "$t parses" || bad "$t does not parse"
done
X="a&b"; mkdir -p "$tmp/templates"; printf '@X@' >"$tmp/templates/t"
eq "render keeps & literal" "$(REPO_ROOT="$tmp" render t)" "a&b"
( unset KITTY_SHELL; render kitty.conf ) >/dev/null 2>&1 && bad "missing value accepted" || ok "render fails on a missing value"

echo "ssh keys (configs)"
repo="$tmp/cfgrepo" home="$tmp/home"; mkdir -p "$repo/setup-ubuntu-workstation/ssh" "$home"
printf 'KEY\n' >"$repo/setup-ubuntu-workstation/ssh/id_test"; printf 'PUB\n' >"$repo/setup-ubuntu-workstation/ssh/id_test.pub"
( TARGET_HOME="$home"; configs_ssh apply "$repo" ) >/dev/null 2>&1
eq "keys land in ~/.ssh, private 0600, .pub 0644" "$(stat -c %a "$home/.ssh" "$home/.ssh/id_test" "$home/.ssh/id_test.pub" | tr '\n' ' ')" "700 600 644 "
printf 'MINE\n' >"$home/.ssh/id_test"; printf 'NEW\n' >"$repo/setup-ubuntu-workstation/ssh/id_test"
( TARGET_HOME="$home"; configs_ssh apply "$repo" ) >/dev/null 2>&1
eq "a different key in ~/.ssh is never overwritten" "$(cat "$home/.ssh/id_test")" "MINE"
printf 'x\n' >"$home/.ssh/authorized_keys"; printf 'x\n' >"$home/.ssh/known_hosts"; printf 'C\n' >"$home/.ssh/config"
( TARGET_HOME="$home"; configs_ssh save "$repo" ) >/dev/null 2>&1
eq "save brings id_* and config back, not authorized_keys or known_hosts" "$(cd "$repo/setup-ubuntu-workstation/ssh" && printf '%s ' *)" "config id_test id_test.pub "
eq "save takes the machine's key" "$(cat "$repo/setup-ubuntu-workstation/ssh/id_test")" "MINE"

echo "managed block"
f="$tmp/bashrc"; printf 'mine 1\nmine 2\n' >"$f"
printf 'A\n' | managed_block "$f" test; printf 'B\n' | managed_block "$f" test
eq "block replaced, rest kept" "$(tr '\n' '|' <"$f")" "mine 1|mine 2|# >>> test >>>|B|# <<< test <<<|"

echo "home, not the system"
eq "system part: no tool that lives in the home now" \
  "$(system_packages | grep -cxE 'jq|gh|ripgrep|bat|fd|git-delta|zoxide|claude-code|kubectl|helm|terraform|vault|azure-cli|google-cloud-cli|powershell(-lts)?|openjdk-.*|dotnet-sdk-.*|fonts-cascadia-code|bubblewrap|socat')" "0"
grep -nE '(atomic_write|run (rm|mkdir|ln|install|tar|cp|mv)|>) *"?/(usr|opt|etc|var)/' modules/[2-9]*.sh \
  && bad "a home module writes into the system (above)" || ok "home modules write nothing into /usr, /opt, /etc, /var"
# shellcheck disable=SC2329  # stubs for dconf_user_defaults and dock_setup
dconf_user_set() { [[ "$1" == /org/x/kept ]] && echo "'mine'"; return 0; }
# shellcheck disable=SC2329
user_dconf() { echo "$*" >>"$tmp/dconf.log"; }
printf "[org/x]\nkept='a'\nnew='b'\n" | dconf_user_defaults 2>/dev/null
eq "GNOME settings: only what the user has not set is written" "$(cat "$tmp/dconf.log")" "write /org/x/new 'b'"
: >"$tmp/dconf.log"; CFG[DOCK]="a.desktop b.desktop"; dock_setup 2>/dev/null
eq "DOCK becomes the dock's list" "$(cat "$tmp/dconf.log")" "write /org/gnome/shell/favorite-apps ['a.desktop', 'b.desktop']"

CFG[DEFAULT_TERMINAL]=ghostty CFG[KITTY]=1 CFG[GHOSTTY]=1; eq "DEFAULT_TERMINAL picks the terminal" "$(default_terminal_id)" "ghostty"
CFG[GHOSTTY]=0; eq "an off DEFAULT_TERMINAL falls back to the first one on" "$(default_terminal_id)" "kitty"

echo "Nemo: Copy as path"
mkdir -p "$tmp/fakebin"; printf '#!/bin/sh\ncat >"%s/clip"\n' "$tmp" >"$tmp/fakebin/wl-copy"; chmod +x "$tmp/fakebin/wl-copy"
PATH="$tmp/fakebin:$PATH" sh templates/nemo-copy-path.sh "/home/u/My Files/a.txt" "/home/u/b"
eq "paths as they are, one per line, no quotes, no trailing newline" "$(od -An -c "$tmp/clip" | tr -s ' ' | tr -d '\n')" " / h o m e / u / M y F i l e s / a . t x t \n / h o m e / u / b"
L="$tmp/nemo/actions-tree.json" A=setup-ubuntu-workstation-copy-path.nemo_action
python3 tools/nemo-action-accel.py "$L" "$A" "<Primary><Shift>c" >/dev/null
eq "no layout yet: one with the shortcut" "$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["toplevel"]; print(len(t), t[0]["uuid"], t[0]["accelerator"])' "$L")" "1 $A <Primary><Shift>c"
printf '{"toplevel": [{"uuid": "Mine", "type": "submenu", "user-label": "Mine", "children": [{"uuid": "%s", "type": "action", "accelerator": "<Primary>k"}]}, {"uuid": "other.nemo_action", "type": "action"}]}' "$A" >"$L"
python3 tools/nemo-action-accel.py "$L" "$A" "<Primary><Shift>c" >/dev/null
grep -q '<Primary>k' "$L" && ! grep -q 'Shift' "$L" && ok "the user's placement (and shortcut) stays" || bad "the user's layout was changed: $(cat "$L")"
printf '{"toplevel": [{"uuid": "other.nemo_action", "type": "action"}]}' >"$L"
python3 tools/nemo-action-accel.py "$L" "$A" "<Primary><Shift>c" >/dev/null
eq "an existing layout keeps its entries, ours is added" "$(python3 -c 'import json,sys; print(" ".join(i["uuid"] for i in json.load(open(sys.argv[1]))["toplevel"]))' "$L")" "other.nemo_action $A"
printf '{broken' >"$L"
python3 tools/nemo-action-accel.py "$L" "$A" "<Primary><Shift>c" >/dev/null 2>&1 && bad "a broken layout was accepted" || eq "a broken layout is left alone" "$(cat "$L")" "{broken"

echo "Windows keys, clipboard history, New Document"
TARGET_HOME="$tmp/u"; set_paths
: >"$tmp/dconf.log"; windows_keys 2>/dev/null
n=0
for w in "desktop/wm/keybindings/panel-run-dialog ['<Alt>F2', '<Super>r']" "shell/keybindings/toggle-overview ['<Control>Escape']" \
         "desktop/wm/keybindings/switch-windows ['<Alt>Tab']" "desktop/wm/keybindings/switch-applications ['<Super>Tab']"; do
  grep -qxF "write /org/gnome/$w" "$tmp/dconf.log" && n=$((n + 1))
done
eq "Win+R, Ctrl+Esc, Alt+Tab = windows, Win+Tab = applications" "$n" "4"
CK=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings TM="/$TASK_MANAGER_KEY/"
eq "Ctrl+Shift+Esc: a custom shortcut of its own" "$(grep -cE "^write $TM(binding '<Control><Shift>Escape'|name 'Task manager'|command '(resources|gnome-system-monitor)')$" "$tmp/dconf.log")" "3"
eq "no custom shortcuts yet: the list gets ours" "$(grep "^write $CK " "$tmp/dconf.log")" "write $CK ['$TM']"
# shellcheck disable=SC2329
dconf_user_set() { [[ "$1" == "$CK" ]] && echo "['/mine/custom0/']"; return 0; }
: >"$tmp/dconf.log"; windows_keys 2>/dev/null
eq "your custom shortcuts stay, ours joins them" "$(grep "^write $CK " "$tmp/dconf.log")" "write $CK ['/mine/custom0/', '$TM']"
# shellcheck disable=SC2329
dconf_user_set() { [[ "$1" == "$CK" ]] && echo "['$TM']"; return 0; }
: >"$tmp/dconf.log"; windows_keys 2>/dev/null
eq "already in the list: not written again" "$(grep -c "^write $CK " "$tmp/dconf.log")" "0"
# shellcheck disable=SC2329
dconf_user_set() { return 0; }
printf '#!/bin/sh\ncase "$2" in */enabled-extensions) echo "$FAKE_ON" ;; */disabled-extensions) echo "$FAKE_OFF" ;; esac\n' >"$tmp/fakebin/dconf"
chmod +x "$tmp/fakebin/dconf"
ext="$TARGET_HOME/.local/share/gnome-shell/extensions/$CLIPBOARD_UUID"; mkdir -p "$ext"
ver CLIPBOARD_INDICATOR_VERSION >"$ext/.setup-ubuntu-workstation-version"   # installed: no download
: >"$tmp/dconf.log"; PATH="$tmp/fakebin:$PATH" FAKE_ON="['a@b']" FAKE_OFF="" clipboard_history_install 2>/dev/null
eq "the extension joins the enabled ones" "$(grep '^write /org/gnome/shell/enabled-extensions' "$tmp/dconf.log")" "write /org/gnome/shell/enabled-extensions ['a@b', '$CLIPBOARD_UUID']"
eq "Win+V opens the history, notifications keep Win+M" "$(grep -cxE "write /org/gnome/shell/(extensions/clipboard-indicator/toggle-menu \['<Super>v'\]|keybindings/toggle-message-tray \['<Super>m'\])" "$tmp/dconf.log")" "2"
eq "its Ctrl+F8…F12 shortcuts are off" "$(grep -cE "clipboard-indicator/(clear-history|prev-entry|next-entry|private-mode-binding) @as \[\]$" "$tmp/dconf.log")" "4"
: >"$tmp/dconf.log"; PATH="$tmp/fakebin:$PATH" FAKE_ON="['a@b']" FAKE_OFF="['$CLIPBOARD_UUID']" clipboard_history_install 2>/dev/null
eq "switched off in the Extensions app: stays off, nothing set" "$(wc -l <"$tmp/dconf.log")" "0"
printf '#!/bin/sh\necho "$FAKE_TPL"\n' >"$tmp/fakebin/xdg-user-dir"; chmod +x "$tmp/fakebin/xdg-user-dir"
mkdir -p "$tmp/tpl"; printf 'mine\n' >"$tmp/tpl/Markdown.md"
PATH="$tmp/fakebin:$PATH" FAKE_TPL="$tmp/tpl" new_documents 2>/dev/null
eq "New Document: the missing template is added, yours stays" "$(cd "$tmp/tpl" && printf '%s|' * && wc -c <'Text file.txt' && cat Markdown.md)" "Markdown.md|Text file.txt|0
mine"
PATH="$tmp/fakebin:$PATH" FAKE_TPL="$TARGET_HOME" new_documents 2>/dev/null
n=0; for f in "${NEW_DOCUMENTS_FILES[@]}"; do [[ -e "$TARGET_HOME/$f" ]] && n=$((n + 1)); done
eq "no templates folder (XDG_TEMPLATES_DIR = home): nothing written" "$n" "0"

echo "Nemo settings (configs)"
printf '#!/bin/sh\ngrep -qx user-db:user "$DCONF_PROFILE" || exit 1\ncat "%s/dump"\n' "$tmp" >"$tmp/fakebin/dconf"
printf '[list-view]\ndefault-column-order=[1]\n\n[preferences]\nsize-prefixes=%s\n\n[window-state]\ngeometry=%s\nmaximized=false\nside-pane-view=%s\nsidebar-width=328\n\n[x]\ngeometry=1\n\n[y]\nsidebar-width=1\n' \
  "'base-2'" "'1090x959+26+23'" "'tree'" >"$tmp/dump"
eq "only your own settings, without the window's size and place" \
  "$(PATH="$tmp/fakebin:$PATH" configs_dconf_dump /org/nemo/ "window-state/geometry window-state/maximized window-state/sidebar-width y/sidebar-width" | tr '\n' '|')" \
  "[list-view]|default-column-order=[1]||[preferences]|size-prefixes='base-2'||[window-state]|side-pane-view='tree'||[x]|geometry=1|"
rm -f "$tmp/fakebin/dconf"

echo "pwsh prompt"
if P="$(command -v pwsh || command -v "$HOME/.local/bin/pwsh")"; then
  r="$tmp/prompt-repo"; git init -q -b main "$r"
  git -C "$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  render pwsh-profile.ps1 >"$tmp/profile.ps1"
  prompt_in() { (cd "$1" && "$P" -NoLogo -NoProfile -Command ". '$tmp/profile.ps1'; Prompt | Out-Null" 2>&1) | sed 's/\x1b\[[0-9;]*m//g'; }
  [[ "$(prompt_in "$r")" != *untracked* ]] && ok "a clean repo shows no untracked files (git's header lines do not count)" \
    || bad "clean repo prompt: $(prompt_in "$r")"
  touch "$r/new-file"
  [[ "$(prompt_in "$r")" == *"untracked:1"* ]] && ok "one new file shows as untracked:1" || bad "prompt with one new file: $(prompt_in "$r")"
else
  echo "  - skipped: no pwsh here"
fi

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
