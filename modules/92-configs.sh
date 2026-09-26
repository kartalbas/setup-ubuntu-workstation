# shellcheck shell=bash
# modules/92-configs.sh — your own settings from your own (private) config
# repository: CONFIGS_REPO=OWNER/NAME, cloned to ~/repos/<owner>/<name>, folder
# setup-ubuntu-workstation/ in it; hosts/<hostname>/ holds a machine's own
# copy of a file. The files are kept as they are, tokens included, so the
# repository must be private. config.conf becomes this machine's config with
# the next `sudo ./setup.sh install`.
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
      claude_llm_links
      log_info "config.conf is used by the next: sudo ./setup.sh install" ;;
    save)
      for entry in "${CONFIGS_FILES[@]}" "config.conf|$CONFIG_FILE|0644"; do
        IFS='|' read -r src dst perm <<<"$entry"; [[ "$dst" == /* ]] || dst="$TARGET_HOME/$dst"
        [[ -f "$dst" ]] || continue
        f="$(configs_source "$dir" "$src")"; mkdir -p "$(dirname "$f")"
        cmp -s "$dst" "$f" || install -m "$perm" "$dst" "$f"
      done
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
