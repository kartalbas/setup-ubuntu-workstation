# shellcheck shell=bash
# modules/60-ai.sh — AI coding agents (C16-18, 68, 70, 74), in the home. Claude
# Code, agy and Muse come through their vendors' installers (to ~/.local/bin;
# Claude Code checks its download's SHA-256 and updates itself), Codex and
# OpenCode from pinned GitHub releases.

ai_setup() {
  log_step "AI coding agents"
  on CLAUDE_CODE && claude_code_install
  on CODEX && bin_install CODEX codex codex-x86_64-unknown-linux-musl
  on OPENCODE && bin_install OPENCODE opencode
  if on CLAUDE_LLM; then
    atomic_write "$BIN_DIR/claude-llm" 0755 <"$REPO_ROOT/tools/claude-llm"
    claude_llm_links
  fi
  on AGY && vendor_installer "Antigravity CLI (agy)" "https://antigravity.google/cli/install.sh" agy
  on MUSE && vendor_installer "Muse Code (muse)" "https://dev.meta.ai/install.sh" muse
  return 0
}

# claude_code_install — Anthropic's native installer, CLAUDE_CHANNEL (latest or
# stable): ~/.local/bin/claude, which keeps itself up to date from then on.
claude_code_install() {
  local ch; ch="$(cfg_get CLAUDE_CHANNEL latest)"
  [[ "$ch" == latest || "$ch" == stable ]] || die "CLAUDE_CHANNEL must be latest or stable"
  if [[ -x "$BIN_DIR/claude" ]]; then
    log_ok "Claude Code $(user_out claude --version 2>/dev/null | head -1) (updates itself)"; return 0
  fi
  vendor_installer "Claude Code" "https://claude.ai/install.sh" claude "$ch"
}

# opencode_llms — OpenCode with your own two LLM servers (llm1, llm2): asks
# for each one's base URL and token, reads model and context size from the
# server, writes ~/.config/opencode/opencode.json (0600). The values stay on
# this machine; the repository has the template with placeholders only.
opencode_llms() {
  local n url token name lines=""
  for n in 1 2; do
    read -rp "llm$n base URL (https://…/v1): " url
    read -rsp "llm$n token: " token; echo
    read -rp "llm$n name in OpenCode (e.g. llm$n-mymodel; Enter = llm$n-<model id>): " name
    [[ -n "$url" && -n "$token" ]] || die "llm$n: URL and token are needed"
    [[ "$name" =~ ^[A-Za-z0-9._-]*$ ]] || die "llm$n: the name may only have letters, digits, . _ -"
    lines+="$url $token $name"$'\n'
  done
  printf '%s' "$lines" | python3 "$REPO_ROOT/tools/opencode-llms.py" \
    "$REPO_ROOT/templates/opencode.json" "$TARGET_HOME/.config/opencode/opencode.json"
  log_ok "OpenCode: llm1 and llm2 in ~/.config/opencode/opencode.json (only on this machine)"
  claude_llm_links
}

# claude_llm_links — claude-<name> in ~/.local/bin for every server in
# OpenCode's config (see tools/claude-llm); links to servers that are no
# longer there go.
claude_llm_links() {
  local cfg="$TARGET_HOME/.config/opencode/opencode.json" names name link target="$BIN_DIR/claude-llm"
  local -a list=()
  on CLAUDE_LLM && [[ -x "$target" ]] || return 0
  names="$(python3 -c 'import json, sys; print(" ".join(json.load(open(sys.argv[1])).get("provider", {})))' "$cfg" 2>/dev/null)" || names=""
  read -ra list <<<"$names"
  for link in "$BIN_DIR"/claude-*; do
    [[ -L "$link" && "$(readlink "$link")" == "$target" ]] || continue
    [[ " $names " == *" ${link##*/claude-} "* ]] || run rm -f "$link"
  done
  for name in "${list[@]}"; do
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ && "$name" != llm ]] || continue
    run ln -sfn "$target" "$BIN_DIR/claude-$name"
  done
  if (( ${#list[@]} )); then log_ok "Claude Code on your LLM servers: $(printf 'claude-%s ' "${list[@]}")"; fi
  return 0
}

# vendor_installer LABEL URL BINARY [ARG...] — run the vendor's installer
# (installs or updates BINARY in ~/.local/bin).
vendor_installer() {
  local label="$1" url="$2" bin="$3" script; shift 3
  script="$(mktemp)"
  run curl -fsSL -o "$script" "$url"
  as_user bash "$script" "$@" </dev/null >/dev/null
  rm -f "$script"
  [[ "$DRY_RUN" == 1 || -x "$BIN_DIR/$bin" ]] || die "$label: ~/.local/bin/$bin missing after its installer"
  log_ok "$label installed/updated"
}
