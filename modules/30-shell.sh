# shellcheck shell=bash
# modules/30-shell.sh — PowerShell 7, its profile, starship, zoxide and the
# bash integration (A4-7), in the home. Per-user files carry a managed block
# and load a *.local file of the user's own, which is never touched.

shell_setup() {
  log_step "Shell: PowerShell, prompt"
  on PWSH && tar_app_install --flat PWSH pwsh pwsh
  on STARSHIP && bin_install STARSHIP starship
  on ZOXIDE && bin_install ZOXIDE zoxide
  if on PWSH && on PWSH_PROFILE; then
    # A block in profile.ps1, so lines other tools add there (e.g. ai-core's
    # PATH) stay.
    local prof="$TARGET_HOME/.config/powershell/profile.ps1"
    render pwsh-profile.ps1 | managed_block "$prof" setup-ubuntu-workstation
    [[ -f "$TARGET_HOME/.config/powershell/profile.local.ps1" ]] \
      || printf '# Your own PowerShell settings (kept by setup-ubuntu-workstation).\n' \
         | atomic_write "$TARGET_HOME/.config/powershell/profile.local.ps1"
  fi
  bash_block
  return 0
}

# bash_block — the tools' shell integration in ~/.bashrc (one managed block).
bash_block() {
  {
    echo "# Managed by setup-ubuntu-workstation — edit outside this block."
    # The programs this setup installs (~/.local/bin; Ubuntu's ~/.profile adds
    # it only when it existed at login) and Go's installed tools.
    echo 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
    on GO && echo 'case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) export PATH="$HOME/go/bin:$PATH" ;; esac'
    if on JAVA || on MAVEN || on FLUTTER; then echo '[ -d "$HOME/.local/opt/jdk" ] && export JAVA_HOME="$HOME/.local/opt/jdk"'; fi
    on DOTNET && echo '[ -d "$HOME/.local/opt/dotnet" ] && export DOTNET_ROOT="$HOME/.local/opt/dotnet"'
    if on NODE; then
      echo 'export NVM_DIR="$HOME/.nvm"'
      echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
      echo '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'
    fi
    if on FLUTTER; then
      echo 'export ANDROID_HOME="$HOME/Android/Sdk"'
      echo 'export PATH="$HOME/.local/share/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"'
    fi
    on RUST && echo '[ -s "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
    on KREW && echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"'
    on JETBRAINS_TOOLBOX && echo '[ -d "$HOME/.local/share/JetBrains/Toolbox/scripts" ] && export PATH="$HOME/.local/share/JetBrains/Toolbox/scripts:$PATH"'
    on ZOXIDE && echo 'command -v zoxide >/dev/null && eval "$(zoxide init bash)"'
    # uv's Python for python3 in the shell; the desktop keeps the system's.
    on PYTHON && echo '[ -x "$HOME/.local/bin/python" ] && alias python3=python'
    # Muse 1.4 cannot store its login in the keyring on Linux yet
    # (github.com/meta-models/muse-code-sdk/issues/38): use its file store.
    on MUSE && echo 'export TBH_CREDENTIAL_BACKEND=file'
    # Tab title: the name of the current directory, set at every prompt.
    printf '%s\n' '__tab_title() { local d="${PWD##*/}"; printf "\e]0;%s\a" "${d:-/}"; }'
    if on STARSHIP; then
      echo 'starship_precmd_user_func=__tab_title'
      echo 'command -v starship >/dev/null && eval "$(starship init bash)"'
    else
      printf '%s\n' "PS1=\${PS1#'\\[\\e]0;'*'\\a\\]'}   # without Ubuntu's user@host: dir title"
      echo 'PROMPT_COMMAND="__tab_title${PROMPT_COMMAND:+; $PROMPT_COMMAND}"'
    fi
  } | managed_block "$TARGET_HOME/.bashrc" setup-ubuntu-workstation
}
