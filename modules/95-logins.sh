# shellcheck shell=bash
# modules/95-logins.sh — interactive sign-ins (J65): GitHub, Claude Code,
# Codex, agy, Muse, OpenCode's LLM servers. Each is skipped when already set
# up, can be declined, and can be repeated any time with `./setup.sh login`.

logins_run() {
  [[ -t 0 && -t 1 ]] || die "The logins need an interactive terminal: ./setup.sh login"
  log_step "Sign-ins"
  _login "GitHub (gh)" GH "gh auth status" \
    "gh auth login --hostname github.com --git-protocol https --web && gh auth setup-git"
  _login "Claude Code" CLAUDE_CODE "claude auth status" "claude auth login"
  _login "OpenAI Codex" CODEX "codex login status" "codex login"
  # agy has no login subcommand: it signs in on its first start (browser, or a
  # URL + code over SSH); leave it with /exit afterwards. Neither agy nor muse
  # can report the signed-in state from a script, so they are always offered.
  _login "Antigravity CLI (agy) — sign in, then leave with /exit" AGY "false" "agy"
  _login "Muse Code" MUSE "false" "muse login"
  _login "OpenCode — your own LLM servers" OPENCODE "test -s \"\$HOME/.config/opencode/opencode.json\"" \
    "'$REPO_ROOT/setup.sh' opencode"
  return 0
}

# _login LABEL KEY CHECK LOGIN — CHECK succeeds when signed in already.
_login() {
  local label="$1" key="$2" check="$3" cmd="$4" answer env=()
  on "$key" || return 0
  # As root (at the end of install): as the user, reaching the desktop session.
  if (( EUID == 0 )); then mapfile -t env < <(user_gui_env); env=(sudo -u "$TARGET_USER" -H env "${env[@]}"); fi
  if "${env[@]}" bash -lc "$check" >/dev/null 2>&1; then
    log_ok "$label: already signed in"; return 0
  fi
  read -rp "Sign in to $label now? [Y/n] " answer
  [[ "${answer:-Y}" =~ ^[Yy] ]] || { log_info "$label: skipped"; return 0; }
  "${env[@]}" bash -lc "$cmd" \
    || log_warn "$label: sign-in not completed — repeat with: ./setup.sh login"
}
