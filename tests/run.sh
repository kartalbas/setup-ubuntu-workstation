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
if shellcheck -x -s bash setup.sh lib/*.sh modules/*.sh tests/run.sh tools/*.sh templates/*.sh; then ok "clean"; else bad "findings above"; fi

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
atomic_write() { local t; t="$(mktemp)"; cat >"$t"; mv "$t" "$1"; CHANGED=1; }   # no chmod/chown/log
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
TARGET_HOME=/home/u; CFG[PWSH]=1 CFG[VSCODE]=0
# shellcheck disable=SC2329  # called by kitty_config
user_file() { cat >"$tmp/$(basename "$1")"; }
kitty_config
eq "kitty.conf gets the shell" "$(grep -c '^shell  *pwsh -NoLogo$' "$tmp/kitty.conf")" "1"
eq "kitty.conf maps the profiles" "$(grep -cE '^map ctrl\+shift\+(1  *launch --type=tab pwsh -NoLogo|2  *launch --type=tab bash -l)$' "$tmp/kitty.conf")" "2"
grep -q "profiles.sh 'PowerShell|pwsh -NoLogo|Ctrl+Shift+1' 'Bash|bash -l|Ctrl+Shift+2'$" "$tmp/kitty.conf" \
  && ok "kitty.conf passes the profiles to the menu" || bad "profile menu line: $(grep profiles.sh "$tmp/kitty.conf")"
grep -q '^map ctrl+comma  *launch --type=tab nano /home/u/.config/kitty/local.conf$' "$tmp/kitty.conf" \
  && ok "Ctrl+, edits local.conf" || bad "Ctrl+, line: $(grep ctrl+comma "$tmp/kitty.conf")"
python3 -m py_compile "$tmp/windows_terminal.py" && ok "kitty helper compiles" || bad "kitty helper does not compile"
python3 -m py_compile tools/opencode-llms.py && python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); assert set(c["provider"]) == {"llm1", "llm2"}' templates/opencode.json \
  && ok "OpenCode template (llm1, llm2) and helper are valid" || bad "OpenCode template or helper broken"
grep -qiE 'https?://[a-z0-9-]+\.[a-z]|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' <(grep -v 'opencode.ai/config.json' templates/opencode.json) \
  && bad "OpenCode template has a real host" || ok "OpenCode template has placeholders only"
ghostty_config
eq "config.ghostty gets the shell" "$(grep -c '^command = pwsh -NoLogo$' "$tmp/config.ghostty")" "1"
eq "config.ghostty loads local.conf" "$(grep -c '^config-file = ?local.conf$' "$tmp/config.ghostty")" "1"
PTYXIS_PROFILE_UUID=0123abcd
eq "Ptyxis defaults name the Bash profile" "$(render dconf-ptyxis | grep -c "^default-profile-uuid='0123abcd'$\|^label='Bash'$")" "2"
CFG[STARSHIP]=1; bash_block
bash -n "$tmp/.bashrc" && ok "bash block (starship) is valid bash" || bad "bash block (starship) has a syntax error"
eq "tab title: directory name" "$(cd /usr/local && bash -c '. <(grep "^__tab_title" "$1"); __tab_title' _ "$tmp/.bashrc" | od -An -c | tr -s ' ')" " 033 ] 0 ; l o c a l \a"
CFG[STARSHIP]=0; bash_block
bash -n "$tmp/.bashrc" && ok "bash block (no starship) is valid bash" || bad "bash block (no starship) has a syntax error"
# shellcheck disable=SC2016  # PS1 as Ubuntu's ~/.bashrc leaves it, before our block
eq "Ubuntu's user@host title is dropped" "$(bash -c 'PS1="\[\e]0;\u@\h: \w\a\]\u@\h:\w\$ "; eval "$(grep "^PS1=" "$1")"; printf %s "$PS1"' _ "$tmp/.bashrc")" '\u@\h:\w$ '
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
user_file() { atomic_write "$1"; }
printf 'A\n' | managed_block "$f" test; printf 'B\n' | managed_block "$f" test
eq "block replaced, rest kept" "$(tr '\n' '|' <"$f")" "mine 1|mine 2|# >>> test >>>|B|# <<< test <<<|"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
