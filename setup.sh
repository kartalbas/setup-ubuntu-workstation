#!/usr/bin/env bash
# setup-ubuntu-workstation — Ubuntu 26.04 desktop as a developer workstation:
# a Windows-Terminal-like terminal with PowerShell, browsers, IDEs, AI coding
# agents, Git, languages, Docker, Kubernetes and cloud CLIs. Newest versions,
# every download checked. Your own account runs it; only the part that needs
# root goes through sudo:
#
#   sudo ./setup.sh system       Ubuntu packages, browsers, Docker (once, and after config changes)
#   ./setup.sh install           everything else, in your home (then log out and in once)
#
# Config: ~/.config/setup-ubuntu-workstation/config.conf (created from
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
${C_BOLD}setup-ubuntu-workstation${C_RST} — Ubuntu 26.04 developer workstation

${C_BOLD}USAGE${C_RST}
  sudo ./setup.sh system       (the part that needs root)
  ./setup.sh COMMAND           (everything else: your account, no sudo)

${C_BOLD}COMMANDS${C_RST}
  system               As root: Ubuntu packages, Chrome, Edge, VS Code, Chromium,
                       Ghostty, Beyond Compare, Docker (and you in its group),
                       Antigravity's sandbox profile
  install              Everything else, into your home (~/.local): terminals,
                       shells, tools, languages, CLIs, fonts, settings
                       (idempotent: re-run it any time, e.g. after a git pull)
  update [--all|--list]
                       Every tool with its installed and newest version;
                       update all that is newer (Enter) or a selection
  login                Sign-ins: gh, Claude Code, Codex, agy, Muse, OpenCode
  doctor               Check that every enabled tool is there, with versions
  opencode             OpenCode with your own two LLM servers (URL + token)
  configs [save]       Your settings from your own config repository, or back into it
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
  if [[ "$verb" == system ]]; then require_system; else require_user "$verb"; fi
  cfg_load; ver_load
  case "$verb" in
    system)   system_all ;;
    install)  install_all ;;
    update)   update_run "$@" ;;
    login)    logins_run ;;
    doctor)   doctor ;;
    opencode) opencode_llms ;;
    configs)  configs_run "$@" ;;
    config)
      case "${1:-}" in
        show) grep -vE '^[[:space:]]*(#|$)' "$([[ -f "$CONFIG_FILE" ]] && echo "$CONFIG_FILE" || echo "$REPO_ROOT/config.example.conf")" ;;
        set)  (( $# == 3 )) || die "config set KEY VALUE"; cfg_set "$2" "$3" ;;
        *) die "config: show | set KEY VALUE" ;;
      esac ;;
    *) usage; die "Unknown command: $verb" ;;
  esac
}

os_check() {
  [[ "$(. /etc/os-release; echo "$ID $VERSION_ID")" == "ubuntu 26.04" ]] \
    || log_warn "Made for Ubuntu 26.04 — this is $(. /etc/os-release; echo "$PRETTY_NAME")"
}

# system_all — as root: what only root can do (modules/05-system.sh).
system_all() {
  os_check
  [[ -f "$CONFIG_FILE" ]] || log_info "No $CONFIG_FILE yet: the defaults of config.example.conf apply (./setup.sh config set KEY VALUE)"
  log_step "setup-ubuntu-workstation: the system part, for $TARGET_USER"
  repos_setup         # 10-repos:  vendor apt repositories (one apt update)
  system_setup        # 05-system: packages, browsers, Docker, AppArmor
  log_step "Done"
  log_ok "System part ready. Now, as yourself: ./setup.sh install"
}

# install_all — everything else, as the user, into the home.
install_all() {
  os_check
  configs_early       # 92-configs:    your config repository's files, config.conf first
  cfg_init; cfg_load
  log_step "setup-ubuntu-workstation for $TARGET_USER"
  system_check        # 05-system:     what the system part provides is there
  base_setup          # 20-base:       command-line tools, fonts
  shell_setup         # 30-shell:      pwsh, profile, starship, zoxide, bash integration
  terminal_setup      # 40-terminal:   kitty, Ghostty, Ptyxis, drop-down, default terminal
  apps_setup          # 50-apps:       IDEs, Files app, Nemo, dock
  ai_setup            # 60-ai:         Claude Code, Codex, OpenCode, agy, Muse
  languages_setup     # 70-languages:  Node (nvm), Python (uv), Go, Java, Flutter, ...
  databases_setup     # 75-databases:  mongosh
  containers_setup    # 80-containers: Kubernetes and CI/CD CLIs
  cloud_setup         # 85-cloud:      Azure, gcloud, terraform, vault, mkcert
  git_identity        # 90-git:        git user name / e-mail, gh as git's helper
  log_step "Done"
  log_ok "Installed. Log out and in once (fonts, menu entries, dock, groups)."
  if on LOGINS; then
    if [[ -t 0 && -t 1 ]]; then logins_run
    else log_info "No terminal attached: run the logins later with: ./setup.sh login"; fi
  fi
}

main "$@"
