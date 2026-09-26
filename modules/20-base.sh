# shellcheck shell=bash
# modules/20-base.sh — git, fonts and the command-line tools (A8-9, D, E).

NERD_FONT_DIR="/usr/local/share/fonts/nerd-fonts"

base_setup() {
  log_step "Git, fonts and command-line tools"
  local pkgs=()
  on GIT && pkgs+=(git)
  on BASICS && pkgs+=(curl wget tree htop openssl unzip xz-utils)
  on JQ && pkgs+=(jq)
  on SEVENZIP && pkgs+=(7zip)
  on MC && pkgs+=(mc)
  on CASCADIA && pkgs+=(fonts-cascadia-code)
  on GH && pkgs+=(gh)
  (( ${#pkgs[@]} )) && apt_install "${pkgs[@]}"
  on GIT && apt_upgrade_pkgs git
  on GH && apt_upgrade_pkgs gh

  if on GIT_LFS; then
    bin_install GIT_LFS git-lfs
    run git lfs install --system --skip-repo >/dev/null
  fi
  on LAZYGIT && bin_install LAZYGIT lazygit
  on DELTA && deb_install DELTA git-delta
  on YQ && bin_install YQ yq
  on RIPGREP && deb_install RIPGREP ripgrep
  on FD && deb_install FD fd
  on FZF && bin_install FZF fzf
  on BAT && deb_install BAT bat
  on NERD_FONTS && nerd_fonts_install
  return 0
}

nerd_fonts_install() {
  local f key file changed=0
  for f in CascadiaCode CascadiaMono FiraCode JetBrainsMono; do
    key="NERDFONT_${f^^}"
    if [[ "$(cat "$NERD_FONT_DIR/$f/.version" 2>/dev/null)" == "$(ver "${key}_VERSION")" ]]; then continue; fi
    file="$(fetch "$key")"
    run rm -rf "$NERD_FONT_DIR/$f"
    run install -d -m 0755 "$NERD_FONT_DIR/$f"
    run tar -xf "$file" -C "$NERD_FONT_DIR/$f" --wildcards '*.ttf' '*.otf' 2>/dev/null || run tar -xf "$file" -C "$NERD_FONT_DIR/$f"
    [[ "$DRY_RUN" == 1 ]] || ver "${key}_VERSION" >"$NERD_FONT_DIR/$f/.version"
    changed=1
  done
  if (( changed )); then run fc-cache -f >/dev/null; log_ok "Nerd Fonts installed"; else log_ok "Nerd Fonts up to date"; fi
}
