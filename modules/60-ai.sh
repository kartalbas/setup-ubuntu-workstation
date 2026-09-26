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

# opencode_llms — OpenCode with your own two LLM servers (llm1, llm2): asks
# for each one's base URL and token, reads model and context size from the
# server, writes ~/.config/opencode/opencode.json (0600). The values stay on
# this machine; the repository has the template with placeholders only.
opencode_llms() {
  local n url token lines=""
  for n in 1 2; do
    read -rp "llm$n base URL (https://…/v1): " url
    read -rsp "llm$n token: " token; echo
    [[ -n "$url" && -n "$token" ]] || die "llm$n: URL and token are needed"
    lines+="$url $token"$'\n'
  done
  printf '%s' "$lines" | python3 "$REPO_ROOT/tools/opencode-llms.py" \
    "$REPO_ROOT/templates/opencode.json" "$TARGET_HOME/.config/opencode/opencode.json"
  log_ok "OpenCode: llm1 and llm2 in ~/.config/opencode/opencode.json (only on this machine)"
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
