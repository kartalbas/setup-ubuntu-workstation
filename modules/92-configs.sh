# shellcheck shell=bash
# modules/92-configs.sh — your own settings from your own (private) config
# repository: CONFIGS_REPO=OWNER/NAME, cloned to ~/repos/<owner>/<name>, folder
# setup-ubuntu-workstation/ in it; hosts/<hostname>/ holds a machine's own
# copy of a file. The files are kept as they are, tokens included, so the
# repository must be private. `./setup.sh install` puts them in place first,
# config.conf included (it becomes this machine's config); ssh/ holds your SSH
# keys (and ssh config) for ~/.ssh; nemo/ Nemo's settings, action menu and
# bookmarks.
#   ./setup.sh configs         pull the repository, put your files in place
#   ./setup.sh configs save    copy your files back, commit, push

# path in the repository | path in your home | mode
CONFIGS_FILES=(
  "kitty/local.conf|.config/kitty/local.conf|0644"
  "ghostty/local.conf|.config/ghostty/local.conf|0644"
  "powershell/profile.local.ps1|.config/powershell/profile.local.ps1|0644"
  "opencode/opencode.json|.config/opencode/opencode.json|0600"
  "nemo/actions-tree.json|.config/nemo/actions-tree.json|0644"
  "nemo/bookmarks|.config/gtk-3.0/bookmarks|0644"
)
# GNOME settings: path in the repository | dconf folder | keys left out
# (section/key; a window's size and place belong to each screen)
CONFIGS_DCONF=(
  "nemo/settings.ini|/org/nemo/|window-state/geometry window-state/maximized window-state/sidebar-width window-state/sidebar-bookmark-breakpoint"
)

# configs_dir — where the config repository is (or would be) cloned.
configs_dir() {
  local repo; repo="$(cfg_get CONFIGS_REPO)"
  [[ "$repo" == */* ]] || return 1
  printf '%s/repos/%s/%s' "$TARGET_HOME" "$(tr '[:upper:]' '[:lower:]' <<<"${repo%%/*}")" "${repo#*/}"
}
# configs_source DIR PATH — the machine's own copy of PATH if there is one.
configs_source() {
  local sub="$1/setup-ubuntu-workstation" host; host="$(hostname -s)"
  if [[ -f "$sub/hosts/$host/$2" ]]; then printf '%s' "$sub/hosts/$host/$2"; else printf '%s' "$sub/$2"; fi
}

# configs_early — at the start of install: your files from the config
# repository, config.conf first; without a GitHub login (a new machine) it
# only warns and the install goes on with the config there is.
configs_early() {
  [[ "$(cfg_get CONFIGS_REPO)" == */* ]] || return 0
  configs_run apply soft || true
  cfg_load
}

# configs_ssh apply|save DIR — your SSH keys. apply: every file of ssh/ in the
# repository (a machine's own copy in hosts/<hostname>/ssh/ wins) to ~/.ssh,
# private ones 0600, *.pub 0644. A file already in ~/.ssh that differs stays
# as it is, so a key is never overwritten. save: id_* and config back, never
# authorized_keys or known_hosts (they belong to each machine).
configs_ssh() {
  local mode="$1" dir="$2" sub="$2/setup-ubuntu-workstation" host f name src dst perm
  local -A names=()
  host="$(hostname -s)"
  case "$mode" in
    apply)
      for f in "$sub/ssh"/* "$sub/hosts/$host/ssh"/*; do [[ -f "$f" ]] && names["${f##*/}"]=1; done
      (( ${#names[@]} )) || return 0
      install -d -m 0700 "$TARGET_HOME/.ssh"
      while read -r name; do
        src="$(configs_source "$dir" "ssh/$name")" dst="$TARGET_HOME/.ssh/$name"
        perm=0600; [[ "$name" == *.pub ]] && perm=0644
        if [[ -f "$dst" ]] && ! cmp -s "$src" "$dst"; then
          log_warn "~/.ssh/$name differs from the repository's: left as it is (move it away to take the repository's)"
          continue
        fi
        [[ -f "$dst" ]] || install -m "$perm" "$src" "$dst"
        chmod "$perm" "$dst"
        log_ok "~/.ssh/$name"
      done < <(printf '%s\n' "${!names[@]}" | sort) ;;
    save)
      for dst in "$TARGET_HOME/.ssh"/id_* "$TARGET_HOME/.ssh/config"; do
        [[ -f "$dst" ]] || continue
        name="${dst##*/}"; f="$(configs_source "$dir" "ssh/$name")"
        perm=0600; [[ "$name" == *.pub ]] && perm=0644
        mkdir -p "$(dirname "$f")"; cmp -s "$dst" "$f" || install -m "$perm" "$dst" "$f"
      done ;;
  esac
  return 0
}

# configs_dconf_dump FOLDER SKIP — your own settings in the dconf FOLDER (not
# the system's defaults) as a keyfile, without the keys in SKIP.
configs_dconf_dump() {
  local profile; profile="$(mktemp)"; printf 'user-db:user\n' >"$profile"
  DCONF_PROFILE="$profile" dconf dump "$1" 2>/dev/null | awk -v skip=" $2 " '
    /^\[.*\]$/ { sec = substr($0, 2, length($0) - 2); head = $0; next }
    /^$/ { next }
    { key = $0; sub(/=.*/, "", key)
      if (index(skip, " " sec "/" key " ")) next
      if (head != "") { if (n++) print ""; print head; head = "" }
      print }'
  rm -f "$profile"
}

configs_run() { # [apply|save] [soft]
  local mode="${1:-apply}" soft="${2:-}" repo dir entry src dst perm f host skip out
  repo="$(cfg_get CONFIGS_REPO)"
  [[ "$repo" == */* ]] || die "No config repository set: ./setup.sh config set CONFIGS_REPO OWNER/NAME"
  dir="$(configs_dir)" host="$(hostname -s)"
  log_step "Your settings: $repo"
  if [[ ! -d "$dir/.git" ]] && ! run git clone -q "https://github.com/$repo.git" "$dir"; then
    [[ -n "$soft" ]] || die "Could not clone $repo (signed in to GitHub? ./setup.sh login)"
    log_warn "Could not clone $repo yet (sign in to GitHub: ./setup.sh login), then: ./setup.sh install"
    return 1
  fi
  git -C "$dir" pull -q --ff-only 2>/dev/null || log_warn "$repo not updated (offline or local changes) — using it as it is"
  case "$mode" in
    apply)
      for entry in "config.conf|$CONFIG_FILE|0644" "${CONFIGS_FILES[@]}"; do
        IFS='|' read -r src dst perm <<<"$entry"; [[ "$dst" == /* ]] || dst="$TARGET_HOME/$dst"
        f="$(configs_source "$dir" "$src")"; [[ -f "$f" ]] || continue
        mkdir -p "$(dirname "$dst")"
        cmp -s "$f" "$dst" || install -m "$perm" "$f" "$dst"
        log_ok "${dst/#$TARGET_HOME/\~}"
      done
      for entry in "${CONFIGS_DCONF[@]}"; do
        IFS='|' read -r src dst skip <<<"$entry"
        f="$(configs_source "$dir" "$src")"; [[ -f "$f" ]] || continue
        user_dconf load "$dst" <"$f"
        log_ok "GNOME settings $dst"
      done
      configs_ssh apply "$dir"
      claude_llm_links ;;
    save)
      for entry in "${CONFIGS_FILES[@]}" "config.conf|$CONFIG_FILE|0644"; do
        IFS='|' read -r src dst perm <<<"$entry"; [[ "$dst" == /* ]] || dst="$TARGET_HOME/$dst"
        [[ -f "$dst" ]] || continue
        f="$(configs_source "$dir" "$src")"; mkdir -p "$(dirname "$f")"
        cmp -s "$dst" "$f" || install -m "$perm" "$dst" "$f"
      done
      for entry in "${CONFIGS_DCONF[@]}"; do
        IFS='|' read -r src dst skip <<<"$entry"
        out="$(configs_dconf_dump "$dst" "$skip")"; [[ -n "$out" ]] || continue
        f="$(configs_source "$dir" "$src")"; mkdir -p "$(dirname "$f")"
        printf '%s\n' "$out" | atomic_write "$f"
      done
      configs_ssh save "$dir"
      git -C "$dir" add -A
      if git -C "$dir" diff --cached --quiet; then log_ok "Nothing changed"
      else
        git -C "$dir" diff --cached --stat
        run git -C "$dir" commit -q -m "setup-ubuntu-workstation settings from $host"
        run git -C "$dir" push -q && log_ok "Saved to $repo"
      fi ;;
    *) die "configs [save]" ;;
  esac
}
