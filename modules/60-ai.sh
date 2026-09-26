# shellcheck shell=bash
# modules/60-ai.sh — AI coding agents (C16-18, 68, 70). Claude Code comes from
# its signed apt repository, Codex and OpenCode from pinned GitHub releases;
# agy and Muse ship only vendor installers (to ~/.local/bin, which also update
# them) — both run as the workstation user.

ai_setup() {
  log_step "AI coding agents"
  if on CLAUDE_CODE; then
    apt_install claude-code bubblewrap socat ripgrep libnotify-bin
    apt_upgrade_pkgs claude-code
    claude_sandbox_apparmor
  fi
  on CODEX && bin_install CODEX codex codex-x86_64-unknown-linux-musl
  on OPENCODE && bin_install OPENCODE opencode
  on AGY && vendor_installer "Antigravity CLI (agy)" "https://antigravity.google/cli/install.sh" agy
  on MUSE && vendor_installer "Muse Code (muse)" "https://dev.meta.ai/install.sh" muse
  return 0
}

# Ubuntu 24.04+ keeps unprivileged programs from creating user namespaces;
# Claude Code's sandbox (bubblewrap) needs them. Profile from the Claude Code
# docs (Sandboxing, "Ubuntu 24.04 and later").
claude_sandbox_apparmor() {
  [[ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)" == 1 ]] || return 0
  render apparmor-bwrap | atomic_write /etc/apparmor.d/bwrap 0644
  if (( CHANGED )); then run systemctl reload apparmor; fi
  return 0
}

# vendor_installer LABEL URL BINARY — run the vendor's installer as the user
# (installs or updates BINARY in ~/.local/bin).
vendor_installer() {
  local label="$1" url="$2" bin="$3" script
  script="$(mktemp)"
  run curl -fsSL -o "$script" "$url"
  chmod 0644 "$script"
  as_user bash "$script" </dev/null >/dev/null
  rm -f "$script"
  [[ "$DRY_RUN" == 1 || -x "$TARGET_HOME/.local/bin/$bin" ]] || die "$label: $TARGET_HOME/.local/bin/$bin missing after its installer"
  log_ok "$label installed/updated"
}
