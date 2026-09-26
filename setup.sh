#!/usr/bin/env bash
# setup-ubuntu-workstation — one command turns Ubuntu 26.04 desktop into a
# developer workstation: a Windows-Terminal-like terminal with PowerShell,
# browsers, IDEs, AI coding agents, Git, languages, Docker, Kubernetes and
# cloud CLIs. Newest versions, every download checked.
#
#   sudo ./setup.sh install        (then log out and in once)
#
# What gets installed: /etc/setup-ubuntu-workstation/config.conf (created from
# config.example.conf); pinned versions: versions.conf.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO_ROOT/lib/common.sh"
for _m in "$REPO_ROOT"/modules/*.sh; do
  # shellcheck source=/dev/null
  . "$_m"
done

usage() {
  cat >&2 <<USAGE
${C_BOLD}setup-ubuntu-workstation${C_RST} — Ubuntu 26.04 developer workstation in one command

${C_BOLD}USAGE${C_RST}
  sudo ./setup.sh install | config set KEY VALUE     (change the system)
  ./setup.sh login | doctor | opencode | config show (your account, no sudo)

${C_BOLD}COMMANDS${C_RST}
  install              Install and configure everything enabled in the config
                       (idempotent: re-run it any time, e.g. after a git pull)
  login                Sign-ins: gh, Claude Code, Codex, agy, Muse, OpenCode
  doctor               Check that every enabled tool is there, with versions
  opencode             OpenCode with your own two LLM servers (URL + token)
  config show | set KEY VALUE
                       Show the config, or change one value (1 = on, 0 = off)
USAGE
}

main() {
  local args=() a
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) args+=("$a") ;;
    esac
  done
  set -- "${args[@]}"
  (( $# )) || { usage; exit 1; }
  local verb="$1"; shift
  case "$verb $*" in
    install*|"config set"*) require_root_and_user "$verb" ;;   # they change the system
    login*|doctor*|opencode*|"config show"*) require_user "$verb" ;;
  esac
  cfg_load; ver_load
  case "$verb" in
    install)  install_all ;;
    login)    logins_run ;;
    doctor)   doctor ;;
    opencode) opencode_llms ;;
    config)
      case "${1:-}" in
        show) grep -vE '^[[:space:]]*(#|$)' "$([[ -f "$CONFIG_FILE" ]] && echo "$CONFIG_FILE" || echo "$REPO_ROOT/config.example.conf")" ;;
        set)  (( $# == 3 )) || die "config set KEY VALUE"; cfg_set "$2" "$3" ;;
        *) die "config: show | set KEY VALUE" ;;
      esac ;;
    *) usage; die "Unknown command: $verb" ;;
  esac
}

install_all() {
  [[ "$(. /etc/os-release; echo "$ID $VERSION_ID")" == "ubuntu 26.04" ]] \
    || log_warn "Made for Ubuntu 26.04 — this is $(. /etc/os-release; echo "$PRETTY_NAME")"
  cfg_init; cfg_load
  log_step "setup-ubuntu-workstation for $TARGET_USER"
  repos_setup         # 10-repos:      vendor apt repositories (one apt update)
  base_setup          # 20-base:       git, fonts, command-line tools
  shell_setup         # 30-shell:      pwsh, profile, starship, bash integration
  terminal_setup      # 40-terminal:   kitty, Ghostty, drop-down, default terminal
  apps_setup          # 50-apps:       browsers, editors, IDEs
  ai_setup            # 60-ai:         Claude Code, Codex, agy, Muse
  languages_setup     # 70-languages:  Node (nvm), Python (uv), Go, Java, Flutter, ...
  databases_setup     # 75-databases:  database clients
  containers_setup    # 80-containers: Docker, Kubernetes, CI/CD CLIs
  cloud_setup         # 85-cloud:      Azure, gcloud, terraform, vault, mkcert
  git_identity        # 90-git:        git user name / e-mail
  log_step "Done"
  log_ok "Installed. Log out and in once (new groups, fonts, default terminal)."
  if on LOGINS; then
    if [[ -t 0 && -t 1 ]]; then logins_run
    else log_info "No terminal attached: run the logins later with: ./setup.sh login"; fi
  fi
}

main "$@"
