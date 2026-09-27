# shellcheck shell=bash
# modules/97-update.sh — `./setup.sh update [--all|--list]`: every enabled
# tool in the home with the version installed and the newest one available;
# update all that is newer (Enter) or a selection. Newer pinned tools are
# recorded in versions.local.conf, so install keeps them. System packages
# (Chrome, Edge, VS Code, Docker, …) come with `sudo apt upgrade`; Ghostty and
# Beyond Compare, when newer, with `sudo ./setup.sh system`.

# Config key of a pinned tool, where it differs from its name in versions.conf.
declare -gA PIN_KEY=(
  [NERDFONT_CASCADIACODE]=NERD_FONTS [NERDFONT_CASCADIAMONO]=NERD_FONTS
  [NERDFONT_FIRACODE]=NERD_FONTS [NERDFONT_JETBRAINSMONO]=NERD_FONTS
  [NVM]=NODE [UV]=PYTHON [ANDROID_CMDLINE_TOOLS]=FLUTTER [RUSTUP]=RUST
  [KUBENS]=KUBECTX [ARGO_ROLLOUTS]=ARGO [CLIPBOARD_INDICATOR]=CLIPBOARD_HISTORY
)
# _pin_on PIN — the tool behind a pinned entry is enabled.
_pin_on() {
  case "$1" in
    JAVA) on JAVA || on MAVEN || on FLUTTER ;;
    UV)   on PYTHON || on AZURE_CLI ;;
    *)    on "${PIN_KEY[$1]:-$1}" ;;
  esac
}
# How a pinned tool gets its version (the same calls install makes).
declare -gA PIN_APPLY=(
  [KITTY]="kitty_install" [GHOSTTY]="system_note Ghostty" [ANTIGRAVITY]="antigravity_ide_install"
  [ANTIGRAVITY_HUB]="antigravity_hub_install" [PWSH]="tar_app_install --flat PWSH pwsh pwsh"
  [STARSHIP]="bin_install STARSHIP starship" [ZOXIDE]="bin_install ZOXIDE zoxide"
  [QUAKE_TERMINAL]="quake_terminal_install" [CLIPBOARD_INDICATOR]="clipboard_history_install"
  [CASCADIA]="fonts_apply"
  [NERDFONT_CASCADIACODE]="fonts_apply" [NERDFONT_CASCADIAMONO]="fonts_apply"
  [NERDFONT_FIRACODE]="fonts_apply" [NERDFONT_JETBRAINSMONO]="fonts_apply"
  [NEOVIM]="tar_app_install NEOVIM nvim bin/nvim" [JETBRAINS_TOOLBOX]="jetbrains_toolbox_install"
  [BCOMPARE]="system_note 'Beyond Compare'"
  [CODEX]="bin_install CODEX codex codex-x86_64-unknown-linux-musl" [OPENCODE]="bin_install OPENCODE opencode"
  [GH]="bin_install GH gh" [GIT_LFS]="bin_install GIT_LFS git-lfs" [LAZYGIT]="bin_install LAZYGIT lazygit"
  [GITLEAKS]="bin_install GITLEAKS gitleaks" [DELTA]="bin_install DELTA delta"
  [JQ]="bin_install JQ jq" [YQ]="bin_install YQ yq" [RIPGREP]="bin_install RIPGREP rg"
  [FD]="bin_install FD fd" [FZF]="bin_install FZF fzf" [BAT]="bin_install BAT bat"
  [NVM]="node_setup" [UV]="python_setup" [GO]="tar_app_install GO go bin/go gofmt=bin/gofmt"
  [JAVA]="java_setup" [MAVEN]="tar_app_install MAVEN mvn bin/mvn" [DOTNET]="dotnet_setup"
  [FLUTTER]="flutter_setup" [ANDROID_CMDLINE_TOOLS]="flutter_setup" [RUSTUP]="rust_setup"
  [MONGOSH]="tar_app_install MONGOSH mongosh bin/mongosh"
  [KUBECTL]="bin_install KUBECTL kubectl" [HELM]="bin_install HELM helm"
  [KUBECTX]="bin_install KUBECTX kubectx" [KUBENS]="bin_install KUBENS kubens"
  [KIND]="bin_install KIND kind" [K9S]="bin_install K9S k9s" [STERN]="bin_install STERN stern"
  [KREW]="krew_setup" [CMCTL]="bin_install CMCTL cmctl" [ARGOCD]="bin_install ARGOCD argocd"
  [TKN]="bin_install TKN tkn" [ARGO]="bin_install ARGO argo"
  [ARGO_ROLLOUTS]="bin_install ARGO_ROLLOUTS kubectl-argo-rollouts"
  [AZURE_CLI]="azure_cli_install" [GCLOUD]="gcloud_install"
  [TERRAFORM]="bin_install TERRAFORM terraform" [VAULT]="bin_install VAULT vault"
  [MKCERT]="bin_install MKCERT mkcert"
)
# fonts_apply — fonts at their pinned versions, the font cache renewed.
fonts_apply() {
  FONTS_CHANGED=0
  on CASCADIA && cascadia_install
  on NERD_FONTS && nerd_fonts_install
  if (( FONTS_CHANGED )); then run fc-cache -f "$FONT_DIR" >/dev/null; fi
  return 0
}
# system_note LABEL — a system package's newer version is recorded; root installs it.
system_note() { log_info "$1: the newer version is recorded — it comes with: sudo ./setup.sh system"; }

U_LABEL=() U_HAVE=() U_NEW=() U_KIND=() U_ARG=() U_UPD=()
declare -gA NEWV=()
_u_add() { U_LABEL+=("$1"); U_HAVE+=("${2:--}"); U_NEW+=("${3:--}"); U_KIND+=("$4"); U_ARG+=("$5"); U_UPD+=("$6"); }
# _short VERSION — without epoch and Debian revision: 1:2.55.0-0ppa1~… → 2.55.0
_short() { local v="$1"; [[ "$v" =~ ^[0-9]+: ]] && v="${v#*:}"; [[ "$v" == *-* ]] && v="${v%-*}"; printf '%s' "$v"; }
_newer() { [[ -n "$1" && -n "$2" && "$1" != "$2" ]] && dpkg --compare-versions "$1" gt "$2" 2>/dev/null; }
_flag() { if "$@"; then echo 1; else echo 0; fi; }

update_run() { # [--all|--list]
  local mode="${1:-}" answer n a i cmd p pins=() pick=()
  [[ -z "$mode" || "$mode" == --all || "$mode" == --list ]] || die "update [--all|--list]"
  log_step "Updates for $TARGET_USER"
  _updates_pinned
  _updates_other
  _updates_show
  [[ "$mode" == --list ]] && return 0
  (( ${#U_SHOWN[@]} )) || return 0
  if [[ "$mode" == --all ]]; then answer=""
  else
    [[ -t 0 ]] || die "No terminal: ./setup.sh update --all (or --list)"
    read -rp "Update: Enter = all of them, numbers like 2 5-7, q = nothing: " answer
  fi
  [[ "$answer" == q* ]] && return 0
  if [[ -z "$answer" ]]; then
    pick=("${U_SHOWN[@]}")
  else
    for n in ${answer//,/ }; do
      if [[ "$n" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        for (( a = BASH_REMATCH[1]; a <= BASH_REMATCH[2]; a++ )); do pick+=("$a"); done
      elif [[ "$n" =~ ^[0-9]+$ ]]; then pick+=("$n")
      else die "Not a number: $n"; fi
    done
    for i in "${!pick[@]}"; do
      (( pick[i] >= 1 && pick[i] <= ${#U_SHOWN[@]} )) || die "There is no number ${pick[i]}"
      pick[i]="${U_SHOWN[$((pick[i] - 1))]}"
    done
  fi
  for i in "${pick[@]}"; do
    case "${U_KIND[$i]}" in
      pin)    [[ "${U_UPD[$i]}" == 1 ]] && pins+=("${U_ARG[$i]}") ;;
      node)   node_setup ;;
      python) as_user uv python install --default "${U_ARG[$i]}" >/dev/null && log_ok "Python ${U_ARG[$i]}" ;;
      agy)    vendor_installer "Antigravity CLI (agy)" "https://antigravity.google/cli/install.sh" agy ;;
      muse)   vendor_installer "Muse Code (muse)" "https://dev.meta.ai/install.sh" muse ;;
    esac
  done
  if (( ${#pins[@]} )); then
    # URL and checksum of just the chosen tools (the check only had versions).
    local tmp; tmp="$(mktemp)"
    as_user bash "$REPO_ROOT/tools/pin-versions.sh" --only "${pins[@]}" >"$tmp" || die "Could not pin ${pins[*]}"
    NEWV=(); _parse_kv_file "$tmp" NEWV; rm -f "$tmp"
    _updates_record "${pins[@]}"
    ver_load
    local -A applied=()
    for p in "${pins[@]}"; do
      cmd="${PIN_APPLY[$p]}"
      [[ -n "${applied[$cmd]:-}" ]] && continue
      applied[$cmd]=1
      eval "$cmd"
    done
  fi
  log_ok "Update done"
}

# _updates_system — the system packages, as a note: root updates them.
SYSTEM_NOTE=""
_updates_system() {
  local n
  n="$(apt list --upgradable 2>/dev/null | awk 'NR > 1' | wc -l)"
  SYSTEM_NOTE="System packages (Ubuntu, Chrome, Edge, VS Code, Docker, …): $n newer as of the last apt update — sudo apt update && sudo apt upgrade"
}

_updates_pinned() {
  local tmp line p k key label
  tmp="$(mktemp)"
  log_info "Looking up the newest versions (a minute or two)…"
  if ! as_user bash "$REPO_ROOT/tools/pin-versions.sh" --check >"$tmp" 2>"$tmp.err"; then
    log_warn "Newest versions of some pinned tools not found: $(tail -1 "$tmp.err")"
  fi
  NEWV=(); _parse_kv_file "$tmp" NEWV
  rm -f "$tmp" "$tmp.err"
  while IFS= read -r line; do
    [[ "$line" =~ ^([A-Z0-9_]+)_(VERSION|MINOR)= ]] || continue
    p="${BASH_REMATCH[1]}" k="${BASH_REMATCH[1]}_${BASH_REMATCH[2]}"
    _pin_on "$p" || continue
    [[ "$p" == JETBRAINS_TOOLBOX ]] && continue   # updates itself
    label="${p,,}"; label="${label//_/-}"
    _u_add "$label" "${VER[$k]:-}" "${NEWV[$k]:-?}" pin "$p" "$(_flag _newer "${NEWV[$k]:-}" "${VER[$k]:-}")"
  done <"$REPO_ROOT/versions.conf"
}

_updates_other() {
  local have new
  if on CLAUDE_CODE; then
    _u_add "claude" "$(user_out claude --version 2>/dev/null | head -1 | cut -d' ' -f1)" "(updates itself)" claude - 0
  fi
  if on NODE; then
    have="$(user_out bash -c '. "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 && nvm version default' 2>/dev/null)"
    new="$(user_out bash -c '. "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 && nvm version-remote --lts' 2>/dev/null)"
    _u_add "node (newest LTS, nvm)" "${have#v}" "${new#v}" node - "$(_flag _newer "${new#v}" "${have#v}")"
  fi
  if on PYTHON; then
    have="$(user_out python3 --version 2>/dev/null | awk '{print $2}')"
    new="$(user_out uv python list --only-downloads --output-format json 2>/dev/null | python3 -c '
import json, sys
v = [x["version"] for x in json.load(sys.stdin) if x["implementation"] == "cpython"
     and x.get("variant", "default") == "default" and x["version"].replace(".", "").isdigit()]
print(v[0] if v else "")' 2>/dev/null)"
    _u_add "python (uv)" "$have" "$new" python "$new" "$(_flag _newer "$new" "$have")"
  fi
  if on AGY; then
    _u_add "agy" "$(user_out agy --version 2>/dev/null | head -1)" "(its installer)" agy - 0
  fi
  if on MUSE; then
    _u_add "muse" "$(user_out muse --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" "(updates itself)" muse - 0
  fi
}

# _updates_show — only what is newer, numbered 1..n (U_SHOWN maps them back).
U_SHOWN=()
_updates_show() {
  local i w1=4 w2=9 unknown=()
  U_SHOWN=()
  for i in "${!U_LABEL[@]}"; do
    [[ "${U_NEW[$i]}" == "?" ]] && unknown+=("${U_LABEL[$i]}")
    [[ "${U_UPD[$i]}" == 1 ]] || continue
    U_SHOWN+=("$i")
    (( ${#U_LABEL[$i]} > w1 )) && w1=${#U_LABEL[$i]}
    (( ${#U_HAVE[$i]} > w2 )) && w2=${#U_HAVE[$i]}
  done
  (( ${#unknown[@]} )) && log_warn "Newest version unknown: ${unknown[*]}"
  _updates_system; log_info "$SYSTEM_NOTE"
  if (( ${#U_SHOWN[@]} == 0 )); then
    log_ok "Everything is up to date (${#U_LABEL[@]} tools checked)"; return 0
  fi
  printf '\n  %s of %s tools have a newer version:\n\n' "${#U_SHOWN[@]}" "${#U_LABEL[@]}"
  printf '  %3s  %-*s  %-*s  %s\n' '#' "$w1" Tool "$w2" Installed Newest
  for i in "${!U_SHOWN[@]}"; do
    printf '  %3d  %-*s  %-*s  %s\n' $((i + 1)) "$w1" "${U_LABEL[${U_SHOWN[$i]}]}" "$w2" "${U_HAVE[${U_SHOWN[$i]}]}" "${U_NEW[${U_SHOWN[$i]}]}"
  done
  echo
}

# _updates_record PREFIX... — the newest version of these pinned tools into
# versions.local.conf; entries the repository has caught up with are dropped.
_updates_record() {
  local p s k line keep=() rec
  local -A repo=() old=()
  _parse_kv_file "$REPO_ROOT/versions.conf" repo
  [[ -f "$VERSIONS_LOCAL" ]] && _parse_kv_file "$VERSIONS_LOCAL" old
  for p in "$@"; do
    for s in VERSION MINOR URL SHA256 SHA512; do
      k="${p}_$s"; unset "old[$k]"
      [[ -n "${NEWV[$k]:-}" ]] && old[$k]="${NEWV[$k]}"
    done
  done
  for k in "${!old[@]}"; do
    [[ "$k" =~ ^(.+)_(VERSION|MINOR)$ ]] || continue
    dpkg --compare-versions "${old[$k]}" gt "${repo[$k]:-0}" 2>/dev/null || continue
    p="${BASH_REMATCH[1]}"
    for s in VERSION MINOR URL SHA256 SHA512; do
      [[ -n "${old[${p}_$s]:-}" ]] && keep+=("${p}_$s=\"${old[${p}_$s]}\"")
    done
  done
  rec="$(printf '%s\n' "# Managed by setup-ubuntu-workstation update: newer versions than versions.conf," \
    "# chosen on this machine (install keeps them until versions.conf catches up)." "${keep[@]}")"
  printf '%s\n' "$rec" | atomic_write "$VERSIONS_LOCAL" 0644
}
