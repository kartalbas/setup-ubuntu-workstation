# shellcheck shell=bash
# modules/20-base.sh — git, fonts and the command-line tools (A8-9, D, E).

NERD_FONT_DIR="/usr/local/share/fonts/nerd-fonts"
CASCADIA_FONTCONFIG="/etc/fonts/conf.d/45-setup-ubuntu-workstation-cascadia.conf"

base_setup() {
  log_step "Git, fonts and command-line tools"
  local pkgs=()
  on GIT && pkgs+=(git)
  on BASICS && pkgs+=(curl wget tree htop openssl unzip xz-utils wl-clipboard)
  on BUILD_TOOLS && pkgs+=(build-essential)
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
  on GITLEAKS && bin_install GITLEAKS gitleaks
  on DELTA && deb_install DELTA git-delta
  on YQ && bin_install YQ yq
  on RIPGREP && deb_install RIPGREP ripgrep
  on FD && deb_install FD fd
  on FZF && bin_install FZF fzf
  on BAT && deb_install BAT bat
  on NERD_FONTS && nerd_fonts_install
  cascadia_hinting
  retired_tools_cleanup
  return 0
}

# retired_tools_cleanup — sops and age, which earlier versions installed for
# encrypted settings, are removed again where this script's own traces (its
# version stamp, its download) show that it installed them.
retired_tools_cleanup() {
  local name stamp f
  for name in age age-keygen; do
    stamp="/usr/local/share/setup-ubuntu-workstation/$name.version"
    [[ -f "$stamp" ]] || continue
    run rm -f "/usr/local/bin/$name" "$stamp"
    log_ok "Removed $name: no longer part of setup-ubuntu-workstation"
  done
  if compgen -G "$CACHE_DIR/sops-*.deb" >/dev/null; then
    if [[ -n "$(installed_version sops)" ]]; then
      DEBIAN_FRONTEND=noninteractive run apt-get purge -y -q sops
      log_ok "Removed sops: no longer part of setup-ubuntu-workstation"
    fi
  fi
  for f in "$CACHE_DIR"/sops-*.deb "$CACHE_DIR"/age-*.tar.gz; do
    [[ -e "$f" ]] && run rm -f "$f"
  done
  return 0
}

# cascadia_hinting — Cascadia placed by its own hints, as on Windows
# (templates/fontconfig-cascadia.conf); kitty and every program that leaves
# hinting to fontconfig draw it that way. Without CASCADIA the rule goes.
cascadia_hinting() {
  if on CASCADIA; then
    render fontconfig-cascadia.conf | atomic_write "$CASCADIA_FONTCONFIG" 0644
  elif [[ -f "$CASCADIA_FONTCONFIG" ]]; then
    run rm -f "$CASCADIA_FONTCONFIG"
  fi
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
