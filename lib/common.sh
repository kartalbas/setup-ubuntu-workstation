# shellcheck shell=bash
# lib/common.sh — logging, execution, users, config, downloads, installs into
# the home and apt helpers shared by setup.sh and every module.
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
# Everything but `system` runs as the workstation user, without sudo, and
# installs into that user's home. `sudo ./setup.sh system` does the few things
# only root can (Ubuntu packages, Docker, an AppArmor profile); it reads the
# user's config and writes nothing into the home. TARGET_USER / TARGET_HOME:
# that account.
TARGET_USER="" TARGET_HOME=""
require_system() {
  [[ $EUID -eq 0 ]] || die "This part needs root: sudo ./setup.sh system"
  TARGET_USER="${SUDO_USER:-}"
  [[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] \
    || die "Run it via sudo from your own account (not as root): sudo ./setup.sh system"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -d "$TARGET_HOME" ]] || die "Home of $TARGET_USER not found"
  CACHE_DIR="/var/cache/setup-ubuntu-workstation"   # the system's downloads (.deb)
  set_paths
}
require_user() {
  [[ $EUID -ne 0 ]] || die "This runs as your own account, without sudo: ./setup.sh $* (only 'system' needs sudo)"
  TARGET_USER="$(id -un)" TARGET_HOME="$HOME"
  set_paths
}
# Where this setup keeps its files — all in the user's home: config, pinned
# versions chosen with `update`, downloads, version stamps, programs.
CONFIG_FILE="${CONFIG_FILE:-}" VERSIONS_LOCAL="${VERSIONS_LOCAL:-}" CACHE_DIR="${CACHE_DIR:-}"
STATE_DIR="" BIN_DIR="" OPT_DIR="" APPS_DIR="" ICONS_DIR="" FONT_DIR=""
set_paths() {
  [[ -n "$CONFIG_FILE" ]] || CONFIG_FILE="$TARGET_HOME/.config/setup-ubuntu-workstation/config.conf"
  [[ -n "$VERSIONS_LOCAL" ]] || VERSIONS_LOCAL="$(dirname "$CONFIG_FILE")/versions.local.conf"
  [[ -n "$CACHE_DIR" ]] || CACHE_DIR="$TARGET_HOME/.cache/setup-ubuntu-workstation"
  STATE_DIR="$TARGET_HOME/.local/share/setup-ubuntu-workstation"
  BIN_DIR="$TARGET_HOME/.local/bin" OPT_DIR="$TARGET_HOME/.local/opt"
  APPS_DIR="$TARGET_HOME/.local/share/applications" ICONS_DIR="$TARGET_HOME/.local/share/icons/hicolor"
  FONT_DIR="$TARGET_HOME/.local/share/fonts"
}
USER_PATH_TAIL="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# as_user CMD... — run as the workstation user with ~/.local/bin first on the
# PATH (under `system`: through sudo, with the user's own HOME).
as_user() {
  if (( EUID == 0 )); then
    run sudo -u "$TARGET_USER" -H env "TERM=${TERM:-dumb}" "PATH=$TARGET_HOME/.local/bin:$USER_PATH_TAIL" "$@"
  else
    run env "PATH=$TARGET_HOME/.local/bin:$USER_PATH_TAIL" "$@"
  fi
}
# as_user_sh SCRIPT — a bash snippet as the workstation user.
as_user_sh() { as_user bash -c "$1"; }
# user_out CMD... — like as_user, without logging (for reads).
user_out() {
  if (( EUID == 0 )); then
    sudo -u "$TARGET_USER" -H env "TERM=${TERM:-dumb}" "PATH=$TARGET_HOME/.local/bin:$USER_PATH_TAIL" "$@"
  else
    env "PATH=$TARGET_HOME/.local/bin:$USER_PATH_TAIL" "$@"
  fi
}

# ---- config (KEY="value" lines, parsed, never sourced) ------------------------
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
    run mkdir -p "$(dirname "$CONFIG_FILE")"
    run install -m 0644 "$REPO_ROOT/config.example.conf" "$CONFIG_FILE"
    log_ok "Created $CONFIG_FILE (all defaults) — adjust with: ./setup.sh config set KEY VALUE"
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
ver_load() {
  VER=(); _parse_kv_file "$REPO_ROOT/versions.conf" VER
  [[ -n "$VERSIONS_LOCAL" && -f "$VERSIONS_LOCAL" ]] || return 0
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
# atomic_write PATH [MODE] — stdin to PATH via a temp file; CHANGED=1 when the
# content (or mode) differs. Missing directories are created by whoever runs
# it: the user for files in the home, root only under `system`.
atomic_write() {
  local path="$1" mode="${2:-0644}" tmp
  CHANGED=0
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  ▶ write %s%s\n' "$C_DIM" "$path" "$C_RST" >&2; cat >/dev/null; return 0
  fi
  mkdir -p "$(dirname "$path")"
  tmp="$(mktemp "$(dirname "$path")/.tmp.XXXXXX")"
  cat >"$tmp"; chmod "$mode" "$tmp"
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
# managed_block FILE NAME — replace (or append) the block between markers in
# FILE with stdin; the rest of the file is left alone.
managed_block() {
  local file="$1" name="$2" body begin end
  body="$(cat)"; begin="# >>> $name >>>"; end="# <<< $name <<<"
  { if [[ -f "$file" ]]; then
      awk -v b="$begin" -v e="$end" '$0 == b {skip=1} !skip {print} $0 == e {skip=0}' "$file"
    fi
    printf '%s\n%s\n%s\n' "$begin" "$body" "$end"; } | atomic_write "$file"
}

# ---- downloads -----------------------------------------------------------------
# fetch KEY — download KEY_URL into the cache and check KEY_SHA256 (or
# KEY_SHA512); prints the local path.
fetch() {
  local key="$1" url file sum algo=256
  url="$(ver "${key}_URL")"
  if [[ -n "${VER[${key}_SHA512]:-}" ]]; then algo=512; sum="${VER[${key}_SHA512]}"; else sum="$(ver "${key}_SHA256")"; fi
  file="$CACHE_DIR/${key,,}-$(ver "${key}_VERSION")-$(basename "${url%%\?*}")"
  if [[ "$DRY_RUN" == 1 ]]; then
    [[ -f "$file" ]] || printf '%s  ▶ download %s%s\n' "$C_DIM" "$url" "$C_RST" >&2
    printf '%s' "$file"; return 0
  fi
  mkdir -p "$CACHE_DIR"
  if [[ ! -f "$file" ]] || ! echo "$sum  $file" | "sha${algo}sum" -c --quiet - >/dev/null 2>&1; then
    run curl -fL --retry 3 --silent --show-error -o "$file.part" "$url" >&2
    echo "$sum  $file.part" | "sha${algo}sum" -c --quiet - >/dev/null 2>&1 \
      || { rm -f "$file.part"; die "Checksum mismatch for $url — refusing to install it"; }
    mv -f "$file.part" "$file"
  fi
  printf '%s' "$file"
}
# unzip_to ZIP DIR [GLOB] — the members of ZIP (matching GLOB) into DIR, with
# Python's zipfile (no unzip package needed).
unzip_to() {
  run python3 - "$1" "$2" "${3:-*}" <<'PY'
import fnmatch, os, sys, zipfile
src, dst, pat = sys.argv[1:]
with zipfile.ZipFile(src) as z:
    for m in z.infolist():
        if m.is_dir() or not fnmatch.fnmatch(m.filename, pat):
            continue
        out = os.path.join(dst, os.path.basename(m.filename) if pat != "*" else m.filename)
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        with z.open(m) as f, open(out, "wb") as o:
            o.write(f.read())
        mode = m.external_attr >> 16
        if mode & 0o111:
            os.chmod(out, 0o755)
PY
}

# ---- programs in the home --------------------------------------------------------
# bin_install KEY NAME [MEMBER] — a pinned program (a plain binary, .gz, or
# the file MEMBER inside a tarball or .zip) to ~/.local/bin/NAME, versioned by
# a stamp in ~/.local/share/setup-ubuntu-workstation.
bin_install() {
  local key="$1" name="$2" member="${3:-$2}" file want stamp dir src
  want="$(ver "${key}_VERSION")"; stamp="$STATE_DIR/$name.version"
  if [[ -x "$BIN_DIR/$name" && ! -L "$BIN_DIR/$name" && "$(cat "$stamp" 2>/dev/null)" == "$want" ]]; then
    log_ok "$name $want already installed"; return 0
  fi
  file="$(fetch "$key")"
  [[ "$DRY_RUN" == 1 ]] && return 0
  mkdir -p "$BIN_DIR" "$STATE_DIR"
  case "$file" in
    *.tar.gz|*.tgz|*.tar.xz|*.zip)
      dir="$(mktemp -d)"
      if [[ "$file" == *.zip ]]; then unzip_to "$file" "$dir" >/dev/null 2>&1; else tar -xf "$file" -C "$dir"; fi
      src="$(find "$dir" -type f -name "$member" | head -1)"
      [[ -n "$src" ]] || { rm -rf "$dir"; die "$name: $member not found in $(basename "$file")"; }
      rm -f "$BIN_DIR/$name"; install -m 0755 "$src" "$BIN_DIR/$name"; rm -rf "$dir" ;;
    *.gz) rm -f "$BIN_DIR/$name"; gunzip -c "$file" >"$BIN_DIR/$name"; chmod 0755 "$BIN_DIR/$name" ;;
    *)    rm -f "$BIN_DIR/$name"; install -m 0755 "$file" "$BIN_DIR/$name" ;;
  esac
  echo "$want" >"$stamp"
  log_ok "$name $want installed (~/.local/bin/$name)"
}
# tar_app_install [--flat] KEY NAME BINARY [LINK=PATH...] — a pinned archive
# unpacked to ~/.local/opt/NAME-VERSION (its top directory dropped, unless
# --flat: the archive has none); BINARY (a path inside it) linked as
# ~/.local/bin/NAME, each LINK=PATH as ~/.local/bin/LINK. Older versions go.
tar_app_install() {
  local strip=1 key name bin want dir file old l
  [[ "$1" == --flat ]] && { strip=0; shift; }
  key="$1" name="$2" bin="$3"; shift 3
  want="$(ver "${key}_VERSION")"; dir="$OPT_DIR/$name-$want"
  if [[ -x "$dir/$bin" ]]; then
    log_ok "$name $want already installed"
  else
    file="$(fetch "$key")"
    run rm -rf "$dir"; run mkdir -p "$dir"
    if [[ "$file" == *.zip ]]; then unzip_to "$file" "$dir"
    else run tar -xf "$file" -C "$dir" --strip-components="$strip" --no-same-owner; fi
    [[ "$DRY_RUN" == 1 ]] || chmod +x "$dir/$bin"
    log_ok "$name $want installed (~/.local/opt/$name-$want)"
  fi
  run mkdir -p "$BIN_DIR"
  run ln -sfn "$dir/$bin" "$BIN_DIR/$name"
  for l in "$@"; do run ln -sfn "$dir/${l#*=}" "$BIN_DIR/${l%%=*}"; done
  for old in "$OPT_DIR/$name"-*; do [[ "$old" == "$dir" || ! -d "$old" ]] || run rm -rf "$old"; done
  return 0
}
# installed_version PKG — dpkg version of an installed package (empty if none).
installed_version() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true; }
# pkg_installed PKG — the Ubuntu package is installed.
pkg_installed() { [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == *"ok installed"* ]]; }

# ---- GNOME settings ------------------------------------------------------------
# user_dconf ARGS... — dconf as the workstation user, through the desktop
# session's bus (or a private one when the user is not logged in).
user_dconf() {
  local bus; bus="/run/user/$(id -u "$TARGET_USER")/bus"
  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then run dconf "$@"
  elif [[ -S "$bus" ]]; then run env "DBUS_SESSION_BUS_ADDRESS=unix:path=$bus" dconf "$@"
  else run dbus-run-session -- dconf "$@"; fi
}
# dconf_user_set KEY — the value the user has set for KEY (empty: none; the
# system's and the schema's defaults do not count).
dconf_user_set() {
  local profile out; profile="$(mktemp)"; printf 'user-db:user\n' >"$profile"
  out="$(DCONF_PROFILE="$profile" dconf read "$1" 2>/dev/null || true)"
  rm -f "$profile"; printf '%s' "$out"
}
# dconf_user_defaults — stdin (a dconf keyfile: [path] sections, key=value
# lines) as the user's settings where the user has none of their own yet: a
# value set in an app's preferences, or before, stays.
dconf_user_defaults() {
  local line path="" key val n=0
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ "$line" =~ ^\[(.+)\]$ ]]; then path="/${BASH_REMATCH[1]}/"; continue; fi
    [[ "$line" == *=* && -n "$path" ]] || continue
    key="${line%%=*}" val="${line#*=}"
    [[ -z "$(dconf_user_set "$path$key")" ]] || continue
    user_dconf write "$path$key" "$val"; n=$((n + 1))
  done
  if (( n )); then log_ok "GNOME settings: $n set (the ones you had not set yourself)"; fi
  return 0
}
# desktop_db — the menu learns new entries in ~/.local/share/applications.
desktop_db() { have update-desktop-database && run update-desktop-database -q "$APPS_DIR"; return 0; }

# ---- apt (only under `sudo ./setup.sh system`) -----------------------------------
APT_UPDATED=0
MANAGED_MARK="Managed by setup-ubuntu-workstation"   # first line of what this setup writes
apt_update() { if (( ! APT_UPDATED )); then run apt-get update -qq; APT_UPDATED=1; fi; }
apt_install() { # PKG... — install what is missing (Ubuntu archive or added repos)
  local missing=() p
  for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
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

# user_gui_env — environment that lets a user command reach the user's
# desktop session (browser windows for the logins, run over ssh).
user_gui_env() {
  local uid run sock
  uid="$(id -u "$TARGET_USER")"; run="/run/user/$uid"
  printf 'XDG_RUNTIME_DIR=%s\n' "$run"
  [[ -S "$run/bus" ]] && printf 'DBUS_SESSION_BUS_ADDRESS=unix:path=%s/bus\n' "$run"
  # (find cannot enter the document portal's mount there)
  sock="$(find "$run" -maxdepth 1 -name 'wayland-[0-9]*' -type s 2>/dev/null | sort | head -1 || true)"
  [[ -n "$sock" ]] && printf 'WAYLAND_DISPLAY=%s\n' "$(basename "$sock")"
  return 0
}
