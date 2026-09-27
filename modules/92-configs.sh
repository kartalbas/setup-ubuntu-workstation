# shellcheck shell=bash
# modules/92-configs.sh — your own settings from your own (private) config
# repository: CONFIGS_REPO=OWNER/NAME, cloned to ~/repos/<owner>/<name>, folder
# setup-ubuntu-workstation/ in it; hosts/<hostname>/ holds a machine's own
# copy of a file. The files are kept as they are, tokens included, so the
# repository must be private. config.conf becomes this machine's config with
# the next `sudo ./setup.sh install`, which also puts your files in place.
# ssh/ holds your SSH keys (and ssh config) for ~/.ssh.
#   ./setup.sh configs         pull the repository, put your files in place
#   ./setup.sh configs save    copy your files back, commit, push

# path in the repository | path in your home | mode
CONFIGS_FILES=(
  "kitty/local.conf|.config/kitty/local.conf|0644"
  "ghostty/local.conf|.config/ghostty/local.conf|0644"
  "powershell/profile.local.ps1|.config/powershell/profile.local.ps1|0644"
  "opencode/opencode.json|.config/opencode/opencode.json|0600"
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

# configs_system — as root, during install: the repository's config.conf
# becomes this machine's.
configs_system() {
  local dir f; dir="$(configs_dir)" || return 0
  f="$(configs_source "$dir" config.conf)"
  [[ -f "$f" ]] || return 0
  atomic_write "$CONFIG_FILE" 0644 <"$f"
  return 0
}

# configs_user — during install: your files put in place as you
# (./setup.sh configs); without a GitHub login it only warns.
configs_user() {
  [[ "$(cfg_get CONFIGS_REPO)" == */* ]] || return 0
  as_user "$REPO_ROOT/setup.sh" configs \
    || log_warn "Your files from $(cfg_get CONFIGS_REPO) are not in place (signed in to GitHub? ./setup.sh login), then: ./setup.sh configs"
  return 0
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

configs_run() { # [save]
  local mode="${1:-apply}" repo dir entry src dst perm f host
  repo="$(cfg_get CONFIGS_REPO)"
  [[ "$repo" == */* ]] || die "No config repository set: sudo ./setup.sh config set CONFIGS_REPO OWNER/NAME"
  dir="$(configs_dir)" host="$(hostname -s)"
  log_step "Your settings: $repo"
  if [[ ! -d "$dir/.git" ]]; then run git clone -q "https://github.com/$repo.git" "$dir" || die "Could not clone $repo (signed in to GitHub? ./setup.sh login)"; fi
  git -C "$dir" pull -q --ff-only 2>/dev/null || log_warn "$repo not updated (offline or local changes) — using it as it is"
  case "$mode" in
    apply)
      for entry in "${CONFIGS_FILES[@]}"; do
        IFS='|' read -r src dst perm <<<"$entry"
        f="$(configs_source "$dir" "$src")"; [[ -f "$f" ]] || continue
        mkdir -p "$(dirname "$TARGET_HOME/$dst")"
        cmp -s "$f" "$TARGET_HOME/$dst" || install -m "$perm" "$f" "$TARGET_HOME/$dst"
        log_ok "~/$dst"
      done
      configs_ssh apply "$dir"
      claude_llm_links
      log_info "config.conf is used by the next: sudo ./setup.sh install" ;;
    save)
      for entry in "${CONFIGS_FILES[@]}" "config.conf|$CONFIG_FILE|0644"; do
        IFS='|' read -r src dst perm <<<"$entry"; [[ "$dst" == /* ]] || dst="$TARGET_HOME/$dst"
        [[ -f "$dst" ]] || continue
        f="$(configs_source "$dir" "$src")"; mkdir -p "$(dirname "$f")"
        cmp -s "$dst" "$f" || install -m "$perm" "$dst" "$f"
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
