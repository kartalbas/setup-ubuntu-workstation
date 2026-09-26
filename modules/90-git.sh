# shellcheck shell=bash
# modules/90-git.sh — git identity (J64). Credentials never go into a plain
# text file: `gh auth setup-git` (run by the logins) makes gh git's helper.

git_identity() {
  on GIT || return 0
  local key cfgkey cur val
  for key in name email; do
    cfgkey="GIT_USER_${key^^}"
    val="$(cfg_get "$cfgkey")"
    cur="$(user_out git config --global "user.$key" 2>/dev/null || true)"
    if [[ -z "$val" && -z "$cur" && -t 0 ]]; then
      read -rp "git user.$key: " val
    fi
    if [[ -n "$val" && "$val" != "$cur" ]]; then
      as_user git config --global "user.$key" "$val"
    fi
  done
  cur="$(user_out git config --global user.name 2>/dev/null || true)"
  if [[ -n "$cur" ]]; then log_ok "git identity: $cur <$(user_out git config --global user.email 2>/dev/null || true)>"
  else log_info "git identity not set — set GIT_USER_NAME/GIT_USER_EMAIL or run install in a terminal"; fi
}
