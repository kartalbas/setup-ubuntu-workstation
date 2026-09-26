# shellcheck shell=bash
# modules/90-git.sh — git identity (J64). Credentials never go into a plain
# text file: `gh auth setup-git` (run by the logins) makes gh git's helper.

# git_identity [ask] — user.name and user.email: GIT_USER_NAME / GIT_USER_EMAIL
# from the config when set; else, when there is none yet, the signed-in GitHub
# account with its private noreply address (the real e-mail stays out of
# commits). With "ask" (the logins) that suggestion is confirmed or replaced.
git_identity() {
  on GIT || return 0
  local ask="${1:-}" name email cur_name cur_email suggestion answer env=()
  cur_name="$(user_out git config --global user.name 2>/dev/null || true)"
  cur_email="$(user_out git config --global user.email 2>/dev/null || true)"
  name="$(cfg_get GIT_USER_NAME)" email="$(cfg_get GIT_USER_EMAIL)"
  if [[ -z "$name$email$cur_name$cur_email" ]]; then
    # gh keeps its token in the keyring: reach the user's session for it.
    (( EUID == 0 )) && mapfile -t env < <(user_gui_env)
    suggestion="$(user_out env "${env[@]}" gh api user \
      --jq '"\(.name // .login)|\(.id)+\(.login)@users.noreply.github.com"' 2>/dev/null || true)"
    if [[ "$suggestion" == *"|"* ]]; then name="${suggestion%%|*}" email="${suggestion#*|}"; fi
    if [[ "$ask" == ask && -t 0 ]]; then
      if [[ -n "$name" ]]; then
        read -rp "git identity from GitHub: $name <$email> — use it? [Y/n] " answer
        [[ "${answer:-Y}" =~ ^[Yy] ]] || name="" email=""
      fi
      [[ -n "$name" ]] || read -rp "git user.name: " name
      [[ -n "$email" ]] || read -rp "git user.email: " email
    fi
  fi
  if [[ -n "$name" && "$name" != "$cur_name" ]]; then as_user git config --global user.name "$name"; fi
  if [[ -n "$email" && "$email" != "$cur_email" ]]; then as_user git config --global user.email "$email"; fi
  cur_name="$(user_out git config --global user.name 2>/dev/null || true)"
  if [[ -n "$cur_name" ]]; then
    log_ok "git identity: $cur_name <$(user_out git config --global user.email 2>/dev/null || true)>"
  else
    log_info "git identity not set — ./setup.sh login asks for it (after the GitHub sign-in)"
  fi
}
