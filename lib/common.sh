# shellcheck shell=bash
# lib/common.sh — logging, execution, users, config, downloads and apt
# helpers shared by setup.sh and every module.
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

set -Eeuo pipefail
shopt -s lastpipe            # `render | atomic_write` reports CHANGED back
shopt -u patsub_replacement  # `&` in ${var//pat/repl} stays literal

# ---- logging ---------------------------------------------------------------
if [[ -t 2 ]]; then
  C_RST=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_RED=$'\e[31m'
  C_GRN=$'\e[32m' C_YEL=$'\e[33m' C_BLU=$'\e[34m' C_CYN=$'\e[36m'
else
  C_RST='' C_BOLD='' C_DIM='' C_RED='' C_GRN='' C_YEL='' C_BLU='' C_CYN=''
fi
log_info() { printf '%s•%s %s\n' "$C_BLU" "$C_RST" "$*" >&2; }
log_ok()   { printf '%s✓%s %s\n' "$C_GRN" "$C_RST" "$*" >&2; }
log_warn() { printf '%s!%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
log_err()  { printf '%s✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
log_step() { printf '\n%s━━ %s%s\n' "$C_BOLD$C_CYN" "$*" "$C_RST" >&2; }
die()      { log_err "$*"; exit 1; }
have()     { command -v "$1" >/dev/null 2>&1; }

_on_err() {
  local rc=$? line=${BASH_LINENO[0]} src=${BASH_SOURCE[1]:-?}
  log_err "Failed (exit $rc) at ${src##*/}:$line: ${BASH_COMMAND}"
}
trap _on_err ERR

DRY_RUN="${DRY_RUN:-0}"
# run CMD... — echo the command, then execute it (skipped under --dry-run).
run() {
  printf '%s  ▶ %s%s\n' "$C_DIM" "$*" "$C_RST" >&2
  [[ "$DRY_RUN" == 1 ]] && return 0
  "$@"
}

# ---- the workstation user ----------------------------------------------------
# Commands that change the system (install, update, config set) run as root
# via sudo; their per-user parts go to the account that called sudo. Commands
# for the account itself (login, doctor, opencode, config show) run as that
# account, without sudo. TARGET_USER / TARGET_HOME: that account.
TARGET_USER="" TARGET_HOME=""
require_root_and_user() {
  [[ $EUID -eq 0 ]] || die "This changes the system: sudo ./setup.sh $*"
  TARGET_USER="${SUDO_USER:-}"
  [[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] \
    || die "Run it via sudo from your own account (not as root), so per-user tools land in your home"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -d "$TARGET_HOME" ]] || die "Home of $TARGET_USER not found"
}
require_user() {
  [[ $EUID -ne 0 ]] || die "This is for your own account, run it without sudo: ./setup.sh $*"
  TARGET_USER="$(id -un)" TARGET_HOME="$HOME"
}
USER_PATH_TAIL="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# as_user CMD... — run as the workstation user with its own HOME and PATH
# (directly when setup.sh already runs as that user).
as_user() {
  if (( EUID == 0 )); then
    run sudo -u "$TARGET_USER" -H env "TERM=${TERM:-dumb}" "PATH=$TARGET_HOME/.local/bin:$USER_PATH_TAIL" "$@"
  else
    run env "PATH=$TARGET_HOME/.local/bin:$USER_PATH_TAIL" "$@"
  fi
}
# as_user_sh SCRIPT — a bash snippet as the workstation user (login-like env).
as_user_sh() { as_user bash -c "$1"; }

# ---- config (KEY="value" lines, parsed, never sourced) ------------------------
CONFIG_FILE="${CONFIG_FILE:-/etc/setup-ubuntu-workstation/config.conf}"
declare -gA CFG=() VER=()
_parse_kv_file() { # FILE ARRAY_NAME
  local -n _dst="$2"
  local line k v
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"; v="${line#*=}"
    k="${k//[[:space:]]/}"
    [[ "$k" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    v="${v%%[[:space:]]#*}"          # trailing "# comment"
    v="${v%"${v##*[![:space:]]}"}"   # trailing blanks
    v="${v%\"}"; v="${v#\"}"
    _dst["$k"]="$v"
  done <"$1"
}
cfg_init() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    run install -d -m 0755 "$(dirname "$CONFIG_FILE")"
    run install -m 0644 "$REPO_ROOT/config.example.conf" "$CONFIG_FILE"
    log_ok "Created $CONFIG_FILE (all defaults) — adjust with: sudo ./setup.sh config set KEY VALUE"
    return 0
  fi
  # Keep the file in step with the repository: settings added since it was
  # created are appended with their default and comment, settings the
  # repository no longer has (a tool that was removed) are dropped.
  local line known added=() dropped=()
  known="$(grep -oE '^[A-Z_][A-Z0-9_]*=' "$REPO_ROOT/config.example.conf")"
  while IFS= read -r line; do
    [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)= ]] || continue
    grep -qE "^${BASH_REMATCH[1]}=" "$CONFIG_FILE" || added+=("$line")
  done <"$REPO_ROOT/config.example.conf"
  while IFS= read -r line; do
    [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)= ]] || continue
    grep -qx "${BASH_REMATCH[1]}=" <<<"$known" || dropped+=("${BASH_REMATCH[1]}")
  done <"$CONFIG_FILE"
  (( ${#added[@]} + ${#dropped[@]} )) || return 0
  {
    if (( ${#dropped[@]} )); then grep -vE "^($(IFS='|'; echo "${dropped[*]}"))=" "$CONFIG_FILE"
    else cat "$CONFIG_FILE"; fi
    if (( ${#added[@]} )); then echo; echo "# ---- new settings (defaults) ----"; printf '%s\n' "${added[@]}"; fi
  } | atomic_write "$CONFIG_FILE" 0644
  (( ${#added[@]} )) && log_ok "New settings in $CONFIG_FILE: ${added[*]%%=*}"
  (( ${#dropped[@]} )) && log_ok "Dropped settings no longer used: ${dropped[*]}"
  return 0
}
cfg_load() {
  CFG=()
  _parse_kv_file "$REPO_ROOT/config.example.conf" CFG   # defaults for new keys
  [[ -f "$CONFIG_FILE" ]] && _parse_kv_file "$CONFIG_FILE" CFG
  return 0
}
cfg_get() { printf '%s' "${CFG[$1]:-${2-}}"; }
on()      { [[ "${CFG[$1]:-0}" == 1 ]]; }
cfg_set() {
  local key="$1" val="$2" line
  grep -qE "^${key}=" "$REPO_ROOT/config.example.conf" || die "Unknown config key: $key (see config.example.conf)"
  [[ "$val" != *'"'* && "$val" != *$'\n'* ]] || die "Values must not contain quotes or newlines"
  cfg_init
  line="${key}=\"${val}\""
  if grep -qE "^${key}=" "$CONFIG_FILE"; then
    awk -v k="$key" -v l="$line" 'index($0, k "=") == 1 { sub(/^[^#]*/, l " "); sub(/ +$/, ""); print; next } { print }' "$CONFIG_FILE" \
      | atomic_write "$CONFIG_FILE" 0644
  else
    { cat "$CONFIG_FILE"; echo "$line"; } | atomic_write "$CONFIG_FILE" 0644
  fi
}
# versions.local.conf (next to the config, written by `update`): newer versions
# chosen on this machine. They count as long as they are newer than the
# repository's; once versions.conf has caught up, its own apply again.
VERSIONS_LOCAL="${VERSIONS_LOCAL:-/etc/setup-ubuntu-workstation/versions.local.conf}"
ver_load() {
  VER=(); _parse_kv_file "$REPO_ROOT/versions.conf" VER
  [[ -f "$VERSIONS_LOCAL" ]] || return 0
  local -A loc=(); local k p s
  _parse_kv_file "$VERSIONS_LOCAL" loc
  for k in "${!loc[@]}"; do
    [[ "$k" =~ ^(.+)_(VERSION|MINOR)$ ]] || continue
    p="${BASH_REMATCH[1]}"
    dpkg --compare-versions "${loc[$k]}" gt "${VER[$k]:-0}" 2>/dev/null || continue
    for s in VERSION MINOR URL SHA256 SHA512; do
      [[ -n "${loc[${p}_$s]:-}" ]] && VER[${p}_$s]="${loc[${p}_$s]}"
    done
  done
  return 0
}
ver() { [[ -n "${VER[$1]:-}" ]] || die "versions.conf has no $1"; printf '%s' "${VER[$1]}"; }

# ---- files -------------------------------------------------------------------
CHANGED=0
# atomic_write PATH [MODE] [OWNER] — stdin to PATH via a temp file; CHANGED=1
# when the content (or mode) differs.
atomic_write() {
  local path="$1" mode="${2:-0644}" owner="${3:-}" tmp
  CHANGED=0
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  ▶ write %s%s\n' "$C_DIM" "$path" "$C_RST" >&2; cat >/dev/null; return 0
  fi
  mkdir -p "$(dirname "$path")"
  tmp="$(mktemp "$(dirname "$path")/.tmp.XXXXXX")"
  cat >"$tmp"; chmod "$mode" "$tmp"
  [[ -n "$owner" ]] && chown "$owner" "$tmp"
  if [[ -f "$path" ]] && cmp -s "$tmp" "$path" && [[ "$(stat -c %a "$path")" == "${mode#0}" ]]; then
    rm -f "$tmp"; return 0
  fi
  mv -f "$tmp" "$path"; CHANGED=1
  log_ok "Wrote $path"
}
# render TEMPLATE — @KEY@ placeholders from shell variables of the same name.
render() {
  local out key
  out="$(<"$REPO_ROOT/templates/$1")"
  while [[ "$out" =~ @([A-Z_][A-Z0-9_]*)@ ]]; do
    key="${BASH_REMATCH[1]}"
    [[ -v "$key" ]] || die "Template $1: no value for @$key@"
    out="${out//@"$key"@/${!key}}"
  done
  printf '%s\n' "$out"
}
# user_file PATH [MODE] — write stdin to a file in the user's home, owned by them.
user_file() { atomic_write "$1" "${2:-0644}" "$TARGET_USER:$(id -gn "$TARGET_USER")"; }
# managed_block FILE NAME — replace (or append) the block between markers in
# FILE with stdin; the rest of the file is left alone.
managed_block() {
  local file="$1" name="$2" body begin end
  body="$(cat)"; begin="# >>> $name >>>"; end="# <<< $name <<<"
  { if [[ -f "$file" ]]; then
      awk -v b="$begin" -v e="$end" '$0 == b {skip=1} !skip {print} $0 == e {skip=0}' "$file"
    fi
    printf '%s\n%s\n%s\n' "$begin" "$body" "$end"; } | user_file "$file"
}

# ---- downloads -----------------------------------------------------------------
CACHE_DIR="/var/cache/setup-ubuntu-workstation"
# fetch KEY — download KEY_URL into the cache and check KEY_SHA256 (or
# KEY_SHA512); prints the local path.
fetch() {
  local key="$1" url file sum algo=256
  url="$(ver "${key}_URL")"
  if [[ -n "${VER[${key}_SHA512]:-}" ]]; then algo=512; sum="${VER[${key}_SHA512]}"; else sum="$(ver "${key}_SHA256")"; fi
  file="$CACHE_DIR/${key,,}-$(ver "${key}_VERSION")-$(basename "${url%%\?*}")"
  install -d -m 0755 "$CACHE_DIR"
  if [[ ! -f "$file" ]] || ! echo "$sum  $file" | "sha${algo}sum" -c --quiet - >/dev/null 2>&1; then
    run curl -fL --retry 3 --silent --show-error -o "$file.part" "$url" >&2
    echo "$sum  $file.part" | "sha${algo}sum" -c --quiet - >/dev/null 2>&1 \
      || { rm -f "$file.part"; die "Checksum mismatch for $url — refusing to install it"; }
    mv -f "$file.part" "$file"
  fi
  printf '%s' "$file"
}
# installed_version PKG — dpkg version of an installed package (empty if none).
installed_version() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true; }

# ---- apt -----------------------------------------------------------------------
APT_UPDATED=0
MANAGED_MARK="Managed by setup-ubuntu-workstation"   # first line of our apt sources
apt_update() { if (( ! APT_UPDATED )); then run apt-get update -q; APT_UPDATED=1; fi; }
apt_install() { # PKG... — install what is missing (Ubuntu archive or added repos)
  local missing=() p
  for p in "$@"; do
    [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == *"ok installed"* ]] || missing+=("$p")
  done
  (( ${#missing[@]} )) || return 0
  apt_update
  DEBIAN_FRONTEND=noninteractive run apt-get install -y -q "${missing[@]}"
}
apt_upgrade_pkgs() { # PKG... — keep packages from vendor repos at their newest
  apt_update
  DEBIAN_FRONTEND=noninteractive run apt-get install -y -q --only-upgrade "$@" >/dev/null
}
# apt_repo NAME URIS SUITES COMPONENTS KEY_URL FINGERPRINT — add a signed
# vendor repository (deb822); the key must carry the expected fingerprint.
apt_repo() {
  local name="$1" uris="$2" suites="$3" comps="$4" key_url="$5" fpr="$6"
  local keyring="/etc/apt/keyrings/$name.gpg" tmp fprs
  if [[ ! -s "$keyring" ]] || ! gpg --show-keys --with-colons "$keyring" 2>/dev/null | grep -q ":$fpr:"; then
    tmp="$(mktemp)"
    run curl -fsSL -o "$tmp" "$key_url"
    fprs="$(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '/^fpr/{print $10}')"
    grep -qx "$fpr" <<<"$fprs" || { rm -f "$tmp"; die "$name: signing key fingerprint is not $fpr"; }
    run install -d -m 0755 /etc/apt/keyrings
    if grep -q 'BEGIN PGP' "$tmp"; then gpg --dearmor <"$tmp" | atomic_write "$keyring" 0644
    else atomic_write "$keyring" 0644 <"$tmp"; fi
    rm -f "$tmp"
  fi
  { echo "# $MANAGED_MARK"
    echo "Types: deb"
    echo "URIs: $uris"
    echo "Suites: $suites"
    [[ -n "$comps" ]] && echo "Components: $comps"
    echo "Architectures: amd64"
    echo "Signed-By: $keyring"; } | atomic_write "/etc/apt/sources.list.d/$name.sources" 0644
  if (( CHANGED )); then APT_UPDATED=0; fi
}
# deb_install KEY PKG — install a pinned .deb (skipped when that version is in).
deb_install() {
  local key="$1" pkg="$2" file want
  want="$(ver "${key}_VERSION")"
  if [[ "$(installed_version "$pkg")" == "$want"* ]]; then log_ok "$pkg $want already installed"; return 0; fi
  file="$(fetch "$key")"
  apt_update
  DEBIAN_FRONTEND=noninteractive run apt-get install -y -q "$file"
}
# bin_install KEY NAME [MEMBER] — a pinned binary (plain, .gz or inside a
# tarball) to /usr/local/bin/NAME, versioned by a stamp next to it.
bin_install() {
  local key="$1" name="$2" member="${3:-}" file want stamp dir
  want="$(ver "${key}_VERSION")"; stamp="/usr/local/share/setup-ubuntu-workstation/$name.version"
  if [[ -x "/usr/local/bin/$name" && "$(cat "$stamp" 2>/dev/null)" == "$want" ]]; then
    log_ok "$name $want already installed"; return 0
  fi
  file="$(fetch "$key")"
  [[ "$DRY_RUN" == 1 ]] && return 0
  case "$file" in
    *.tar.gz|*.tgz|*.tar.xz)
      dir="$(mktemp -d)"; tar -xf "$file" -C "$dir"
      local src; src="$(find "$dir" -type f -name "${member:-$name}" | head -1)"
      [[ -n "$src" ]] || die "$name: ${member:-$name} not found in $(basename "$file")"
      install -m 0755 "$src" "/usr/local/bin/$name"; rm -rf "$dir" ;;
    *.gz) gunzip -c "$file" >"/usr/local/bin/$name"; chmod 0755 "/usr/local/bin/$name" ;;
    *)    install -m 0755 "$file" "/usr/local/bin/$name" ;;
  esac
  install -d -m 0755 "$(dirname "$stamp")"; echo "$want" >"$stamp"
  log_ok "$name $want installed"
}

# dconf_defaults NAME — stdin as system-wide dconf defaults
# (/etc/dconf/db/local.d/NAME): every user starts with these values and can
# still change them.
dconf_defaults() {
  local changed
  atomic_write "/etc/dconf/db/local.d/$1" 0644; changed=$CHANGED
  if [[ ! -f /etc/dconf/profile/user ]]; then
    printf 'user-db:user\nsystem-db:local\n' | atomic_write /etc/dconf/profile/user 0644; changed=1
  fi
  grep -qx 'system-db:local' /etc/dconf/profile/user \
    || log_warn "/etc/dconf/profile/user has no system-db:local: these defaults are not read"
  if (( changed )) || [[ ! -f /etc/dconf/db/local ]]; then run dconf update; fi
  return 0
}
# user_dconf ARGS... — dconf as the workstation user; writes go through the
# user's session bus, or a private one when the user is not logged in.
user_dconf() {
  local bus; bus="/run/user/$(id -u "$TARGET_USER")/bus"
  if (( EUID != 0 )); then
    run dconf "$@"
  elif [[ -S "$bus" ]]; then
    run sudo -u "$TARGET_USER" -H env "DBUS_SESSION_BUS_ADDRESS=unix:path=$bus" dconf "$@"
  else
    run sudo -u "$TARGET_USER" -H dbus-run-session -- dconf "$@"
  fi
}

# user_out CMD... — run as the workstation user without logging (for reads).
user_out() {
  if (( EUID == 0 )); then
    sudo -u "$TARGET_USER" -H env "TERM=${TERM:-dumb}" "PATH=$TARGET_HOME/.local/bin:$USER_PATH_TAIL" "$@"
  else
    env "PATH=$TARGET_HOME/.local/bin:$USER_PATH_TAIL" "$@"
  fi
}
# user_gui_env — environment that lets a user command reach the user's
# desktop session (browser windows for the logins).
user_gui_env() {
  local uid run sock
  uid="$(id -u "$TARGET_USER")"; run="/run/user/$uid"
  printf 'XDG_RUNTIME_DIR=%s\n' "$run"
  [[ -S "$run/bus" ]] && printf 'DBUS_SESSION_BUS_ADDRESS=unix:path=%s/bus\n' "$run"
  sock="$(find "$run" -maxdepth 1 -name 'wayland-[0-9]*' -type s 2>/dev/null | sort | head -1)"
  [[ -n "$sock" ]] && printf 'WAYLAND_DISPLAY=%s\n' "$(basename "$sock")"
  return 0
}
