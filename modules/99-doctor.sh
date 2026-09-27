# shellcheck shell=bash
# modules/99-doctor.sh — read-only check: every enabled tool answers, with
# its version, as the workstation user would call it.

_d_ok=0 _d_bad=0
# _tool KEY LABEL COMMAND... — the command's first output line is the version.
_tool() {
  local key="$1" label="$2" out; shift 2
  on "$key" || return 0
  if out="$(user_out bash -lc "$*" 2>&1 | grep -v '^\s*$' | head -1)" && [[ -n "$out" ]]; then
    log_ok "$(printf '%-24s %s' "$label" "$out")"; _d_ok=$((_d_ok + 1))
  else
    log_err "$(printf '%-24s %s' "$label" "missing or not working")"; _d_bad=$((_d_bad + 1))
  fi
}

# _ssh_keys — every private key in your config repository's ssh/ is in
# ~/.ssh, yours alone (0600) and readable as a key.
_ssh_keys() {
  local dir f name dst keys=() bad=()
  dir="$(configs_dir)" || return 0
  for f in "$dir/setup-ubuntu-workstation/ssh"/id_*; do
    [[ -f "$f" && "$f" != *.pub ]] || continue
    name="${f##*/}" dst="$TARGET_HOME/.ssh/${f##*/}"
    if [[ -f "$dst" && "$(stat -c %a "$dst")" == 600 ]] && ssh-keygen -lf "$dst" >/dev/null 2>&1; then
      keys+=("$name ($(ssh-keygen -lf "$dst" | awk '{print $NF, $1}' | tr -d '()'))")
    else bad+=("$name"); fi
  done
  (( ${#keys[@]} + ${#bad[@]} )) || return 0
  if (( ${#bad[@]} )); then
    log_err "$(printf '%-24s %s' "SSH keys" "not in ~/.ssh or not 0600: ${bad[*]} (./setup.sh configs)")"; _d_bad=$((_d_bad + 1))
  else
    log_ok "$(printf '%-24s %s' "SSH keys" "${keys[*]}")"; _d_ok=$((_d_ok + 1))
  fi
}

# _nemo_copy_path — Nemo's "Copy as path": its script, wl-copy, its shortcut.
_nemo_copy_path() {
  on NEMO || return 0
  local dir="$TARGET_HOME/$NEMO_ACTIONS_REL" accel
  accel="$(python3 -c 'import json, sys
def walk(items):
    for i in items:
        if i.get("uuid") == sys.argv[2]: return i.get("accelerator") or "-"
        r = walk(i.get("children") or [])
        if r: return r
print(walk(json.load(open(sys.argv[1])).get("toplevel", [])) or "")' "$TARGET_HOME/.config/nemo/actions-tree.json" "$NEMO_COPY_PATH.nemo_action" 2>/dev/null)"
  if [[ -x "$dir/$NEMO_COPY_PATH.sh" && -f "$dir/$NEMO_COPY_PATH.nemo_action" ]] && have wl-copy; then
    log_ok "$(printf '%-24s %s' "Nemo: Copy as path" "right-click${accel:+, shortcut $accel}")"; _d_ok=$((_d_ok + 1))
  else
    log_err "$(printf '%-24s %s' "Nemo: Copy as path" "missing (./setup.sh install; wl-copy: sudo ./setup.sh system)")"; _d_bad=$((_d_bad + 1))
  fi
}

# _dock — with DOCK in the config: the dock has those entries.
_dock() {
  local want have
  want="$(cfg_get DOCK)"; [[ -n "$want" ]] || return 0
  have="$(dock_current)"
  if [[ "$have" == "$want" ]]; then log_ok "$(printf '%-24s %s' "Dock" "as DOCK says ($(wc -w <<<"$want") entries)")"; _d_ok=$((_d_ok + 1))
  else log_warn "$(printf '%-24s %s' "Dock" "differs from DOCK (yours stays; configs save takes it over)")"; fi
}

doctor() {
  log_step "Doctor ($TARGET_USER)"
  system_check
  _tool KITTY "kitty" kitty --version
  _tool GHOSTTY "Ghostty" ghostty --version
  _tool PTYXIS "Ptyxis" ptyxis --version
  _tool NEMO "Nemo (file manager)" "[ \"\$(xdg-mime query default inode/directory)\" = nemo.desktop ] && dpkg-query -W -f='nemo \${Version}, opens folders' nemo"
  _tool FILES_OPEN_IN "Files app: Open in" "/usr/bin/python3 -W ignore ~/.local/share/nautilus-python/extensions/setup-ubuntu-workstation-open-in.py"
  _tool QUAKE_TERMINAL "Quake Terminal" "cat ~/.local/share/gnome-shell/extensions/$QUAKE_UUID/.setup-ubuntu-workstation-version"
  _tool PWSH "PowerShell" "pwsh -NoLogo -NoProfile -Command '\$PSVersionTable.PSVersion.ToString()'"
  _tool PWSH_PROFILE "pwsh profile" "test -f ~/.config/powershell/profile.ps1 && echo ~/.config/powershell/profile.ps1"
  _tool STARSHIP "starship" starship --version
  _tool ZOXIDE "zoxide" zoxide --version
  _tool CASCADIA "Cascadia fonts" "fc-list | grep -c 'Cascadia Mono' | sed 's/\$/ font files/'"
  _tool CASCADIA "Cascadia hinting" "fc-match -f '%{hintstyle}' 'Cascadia Mono' | grep -qx 3 && echo 'hintfull: its own hints, as on Windows'"
  _tool GHOSTTY "Ghostty hinting" "grep -qx 'freetype-load-flags = no-autohint' ~/.config/ghostty/config.ghostty && echo 'no-autohint: its own hints, as on Windows'"
  _tool PTYXIS "GTK hinting (Ptyxis)" "gsettings get org.gnome.desktop.interface font-rendering | grep -qx \"'manual'\" && gsettings get org.gnome.desktop.interface font-hinting | grep -qx \"'full'\" && echo 'manual, full: its own hints, as on Windows'"
  _tool NERD_FONTS "Nerd Fonts" "fc-list | grep -ci 'Nerd Font' | sed 's/\$/ font files/'"
  _tool CHROME "Google Chrome" google-chrome --version
  _tool EDGE "Microsoft Edge" microsoft-edge --version
  _tool CHROMIUM "Chromium" "snap list chromium | tail -1 | awk '{print \"chromium\", \$2}'"
  _tool VSCODE "VS Code" "code --version | head -1"
  _tool ANTIGRAVITY "Antigravity IDE" "antigravity-ide --version >/dev/null && readlink -f ~/.local/bin/antigravity-ide | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1"
  _tool ANTIGRAVITY_HUB "Antigravity 2.0" "test -x ~/.local/bin/antigravity-hub && readlink -f ~/.local/bin/antigravity-hub | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1"
  _tool JETBRAINS_TOOLBOX "JetBrains Toolbox" "test -x ~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox && cat ~/.local/share/JetBrains/Toolbox/bin/build.txt"
  _tool NEOVIM "Neovim" "nvim --version | head -1"
  _tool BCOMPARE "Beyond Compare" "dpkg-query -W -f='bcompare \${Version}' bcompare"
  _tool CLAUDE_CODE "Claude Code" claude --version
  _tool CODEX "Codex" codex --version
  _tool AGY "agy" agy --version
  _tool MUSE "Muse Code" muse --version
  _tool OPENCODE "OpenCode" opencode --version
  _tool CLAUDE_LLM "Claude on your LLMs" "claude-llm --list | cut -d' ' -f1 | tr '\n' ' '"
  _tool GIT "git" git --version
  _tool GH "gh" "gh --version | head -1"
  _tool GIT_LFS "git-lfs" git lfs version
  _tool LAZYGIT "lazygit" "lazygit --version | cut -c1-80"
  _tool GITLEAKS "gitleaks" "gitleaks version"
  _tool DELTA "delta" delta --version
  _tool BUILD_TOOLS "gcc / make" 'echo "$(gcc --version | head -1) · $(make --version | head -1)"'
  _tool JQ "jq" jq --version
  _tool YQ "yq" yq --version
  _tool RIPGREP "ripgrep" "rg --version | head -1"
  _tool FD "fd" fd --version
  _tool FZF "fzf" fzf --version
  _tool BAT "bat" "bat --version"
  _tool SEVENZIP "7-Zip" "7z | head -2 | tail -1"
  _tool MC "Midnight Commander" "TERM=xterm mc --version | head -1"
  _tool NODE "Node.js (nvm)" '. ~/.nvm/nvm.sh && echo "$(node --version), default $(nvm version default)"'
  _tool YARN_PNPM "yarn / pnpm" '. ~/.nvm/nvm.sh && echo "yarn $(yarn --version) · pnpm $(pnpm --version)"'
  # uv's python3 in ~/.local/bin would hide the system Python from the desktop
  _tool PYTHON "Python (uv)" '[ ! -e ~/.local/bin/python3 ] && echo "$(python --version) · uv $(uv --version | cut -d" " -f2)"'
  _tool GO "Go" go version
  _tool JAVA "Java (Temurin)" "java -version 2>&1 | head -1"
  _tool MAVEN "Maven" "mvn -version | head -1"
  _tool FLUTTER "Flutter" "~/.local/share/flutter/bin/flutter --version 2>/dev/null | head -1"
  _tool RUST "Rust" "~/.cargo/bin/rustc --version"
  _tool DOTNET ".NET" "dotnet --version"
  _tool PSQL "psql" psql --version
  _tool MONGOSH "mongosh" mongosh --version
  _tool REDIS_CLI "redis-cli" redis-cli --version
  _tool MYSQL_CLIENT "mysql" mysql --version
  _tool DOCKER_CLI "docker" "docker --version && docker compose version | head -1 >/dev/null"
  _tool DOCKER_ENGINE "Docker Engine" "docker info --format '{{.ServerVersion}}' >/dev/null && echo 'running, docker works without sudo'"
  _tool KUBECTL "kubectl" "kubectl version --client | head -1"
  _tool HELM "helm" "helm version --short"
  _tool KIND "kind" kind --version
  _tool K9S "k9s" "k9s version --short | head -1"
  _tool KUBECTX "kubectx / kubens" "echo kubectx \$(kubectx --version) · kubens \$(kubens --version)"
  _tool STERN "stern" "stern --version | head -1"
  _tool KREW "krew" "~/.krew/bin/kubectl-krew version | grep GitTag"
  _tool CMCTL "cmctl" "cmctl version --client --short 2>/dev/null || cmctl version --client | head -1"
  _tool ARGOCD "argocd" "argocd version --client --short"
  _tool TKN "tkn" "tkn version | head -1"
  _tool ARGO "argo / rollouts" "echo argo \$(argo version --short 2>/dev/null | head -1) · \$(kubectl-argo-rollouts version --short 2>/dev/null | head -1)"
  _tool AZURE_CLI "Azure CLI" "az version --query '\"azure-cli\"' -o tsv"
  _tool GCLOUD "gcloud" "gcloud --version 2>/dev/null | head -1"
  _tool TERRAFORM "terraform" "terraform version | head -1"
  _tool VAULT "vault" "vault version"
  _tool MKCERT "mkcert" mkcert --version
  _nemo_copy_path
  _dock
  _ssh_keys
  echo >&2
  if (( _d_bad )); then log_warn "$_d_ok ok, $_d_bad missing or failing"; exit 1; fi
  log_ok "All $_d_ok enabled tools answer"
}
