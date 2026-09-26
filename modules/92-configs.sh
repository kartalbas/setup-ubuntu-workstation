# shellcheck shell=bash
# modules/92-configs.sh — your own settings from your own (private) config
# repository: CONFIGS_REPO=OWNER/NAME, cloned to ~/repos/<owner>/<name>, folder
# setup-ubuntu-workstation/ in it. Files named *.sops.* there are encrypted
# (sops + age) and decrypted on the way; hosts/<hostname>/ holds a machine's
# own copy of a file. config.conf becomes this machine's config with the next
# `sudo ./setup.sh install`.
#   ./setup.sh configs         pull the repository, put your files in place
#   ./setup.sh configs save    copy your files back, encrypt, commit, push

# path in the repository | path in your home
CONFIGS_FILES=(
  "kitty/local.conf|.config/kitty/local.conf"
  "ghostty/local.conf|.config/ghostty/local.conf"
  "powershell/profile.local.ps1|.config/powershell/profile.local.ps1"
  "opencode/opencode.sops.json|.config/opencode/opencode.json"
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
  local mode="${1:-apply}" repo dir entry src dst f plain host
  repo="$(cfg_get CONFIGS_REPO)"
  [[ "$repo" == */* ]] || die "No config repository set: sudo ./setup.sh config set CONFIGS_REPO OWNER/NAME"
  dir="$(configs_dir)" host="$(hostname -s)"
  log_step "Your settings: $repo"
  if [[ ! -d "$dir/.git" ]]; then run git clone -q "https://github.com/$repo.git" "$dir" || die "Could not clone $repo (signed in to GitHub? ./setup.sh login)"; fi
  plain="$(mktemp)"; chmod 0600 "$plain"
  case "$mode" in
    apply)
      git -C "$dir" pull -q --ff-only 2>/dev/null || log_warn "$repo not updated (offline or local changes) — using it as it is"
      for entry in "${CONFIGS_FILES[@]}"; do
        src="${entry%%|*}" dst="$TARGET_HOME/${entry#*|}"
        f="$(configs_source "$dir" "$src")"; [[ -f "$f" ]] || continue
        mkdir -p "$(dirname "$dst")"
        if [[ "$src" == *.sops.* ]]; then
          sops -d "$f" >"$plain" 2>/dev/null || die "Cannot decrypt $src — is the key here? $dir/bin/secrets unlock"
          cmp -s "$plain" "$dst" || install -m 0600 "$plain" "$dst"
        else
          cmp -s "$f" "$dst" || install -m 0644 "$f" "$dst"
        fi
        log_ok "~/${entry#*|}"
      done
      log_info "config.conf is used by the next: sudo ./setup.sh install" ;;
    save)
      for entry in "${CONFIGS_FILES[@]}" "config.conf|$CONFIG_FILE"; do
        src="${entry%%|*}" dst="${entry#*|}"; [[ "$dst" == /* ]] || dst="$TARGET_HOME/$dst"
        [[ -f "$dst" ]] || continue
        f="$(configs_source "$dir" "$src")"; mkdir -p "$(dirname "$f")"
        if [[ "$src" == *.sops.* ]]; then
          # Only re-encrypt when the content changed (every encryption differs).
          if [[ -f "$f" ]] && sops -d "$f" 2>/dev/null | cmp -s - "$dst"; then continue; fi
          sops -e --filename-override "$f" "$dst" >"$plain" || die "Cannot encrypt $src — see $dir/.sops.yaml and bin/secrets"
          cp "$plain" "$f"
        else
          cmp -s "$dst" "$f" || cp "$dst" "$f"
        fi
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
  rm -f "$plain"
}
