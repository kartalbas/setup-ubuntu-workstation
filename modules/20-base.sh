# shellcheck shell=bash
# modules/20-base.sh — command-line tools and fonts, in the home (A8-9, D, E):
# pinned upstream builds in ~/.local/bin, fonts in ~/.local/share/fonts.

CASCADIA_FONTCONFIG_REL=".config/fontconfig/conf.d/45-setup-ubuntu-workstation-cascadia.conf"

base_setup() {
  log_step "Command-line tools and fonts"
  on GH && bin_install GH gh
  if on GIT_LFS; then
    bin_install GIT_LFS git-lfs
    have git && as_user git lfs install --skip-repo >/dev/null
  fi
  on LAZYGIT && bin_install LAZYGIT lazygit
  on GITLEAKS && bin_install GITLEAKS gitleaks
  on DELTA && bin_install DELTA delta
  on JQ && bin_install JQ jq
  on YQ && bin_install YQ yq
  on RIPGREP && bin_install RIPGREP rg
  on FD && bin_install FD fd
  on FZF && bin_install FZF fzf
  on BAT && bin_install BAT bat
  FONTS_CHANGED=0
  on CASCADIA && cascadia_install
  on NERD_FONTS && nerd_fonts_install
  if (( FONTS_CHANGED )); then run fc-cache -f "$FONT_DIR" >/dev/null; fi
  cascadia_hinting
  return 0
}

# cascadia_install — Cascadia Code and Mono (Windows Terminal's font), the
# variable fonts of Microsoft's release, in ~/.local/share/fonts/cascadia.
cascadia_install() {
  local dir="$FONT_DIR/cascadia" want file
  want="$(ver CASCADIA_VERSION)"
  if [[ "$(cat "$dir/.version" 2>/dev/null)" == "$want" ]]; then log_ok "Cascadia $want already installed"; return 0; fi
  file="$(fetch CASCADIA)"
  run rm -rf "$dir"; run mkdir -p "$dir"
  unzip_to "$file" "$dir" 'ttf/Cascadia*.ttf'
  [[ "$DRY_RUN" == 1 ]] || echo "$want" >"$dir/.version"
  FONTS_CHANGED=1; log_ok "Cascadia $want installed"
}

nerd_fonts_install() {
  local f key file dir n=0
  for f in CascadiaCode CascadiaMono FiraCode JetBrainsMono; do
    key="NERDFONT_${f^^}" dir="$FONT_DIR/nerd-fonts/$f"
    [[ "$(cat "$dir/.version" 2>/dev/null)" == "$(ver "${key}_VERSION")" ]] && continue
    file="$(fetch "$key")"
    run rm -rf "$dir"; run mkdir -p "$dir"
    run tar -xf "$file" -C "$dir" --wildcards '*.ttf' '*.otf' 2>/dev/null || run tar -xf "$file" -C "$dir"
    [[ "$DRY_RUN" == 1 ]] || ver "${key}_VERSION" >"$dir/.version"
    n=$((n + 1))
  done
  if (( n )); then FONTS_CHANGED=1; log_ok "Nerd Fonts installed"; else log_ok "Nerd Fonts up to date"; fi
}

# cascadia_hinting — Cascadia placed by its own hints, as on Windows
# (templates/fontconfig-cascadia.conf); kitty and every program that leaves
# hinting to fontconfig draw it that way. Without CASCADIA the rule goes.
cascadia_hinting() {
  local f="$TARGET_HOME/$CASCADIA_FONTCONFIG_REL"
  if on CASCADIA; then render fontconfig-cascadia.conf | atomic_write "$f" 0644
  elif [[ -f "$f" ]]; then run rm -f "$f"; fi
  return 0
}
