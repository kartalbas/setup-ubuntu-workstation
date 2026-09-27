# shellcheck shell=bash
# modules/70-languages.sh — languages and SDKs (F33-41), in the home.
#   Node.js: only through nvm, only the newest LTS, set as the default.
#   Python:  uv + the newest CPython for the user.
#   Go:      go.dev's tarball in ~/.local/opt, go and gofmt in ~/.local/bin.
#   Java:    Eclipse Temurin (LTS) in ~/.local/opt, JAVA_HOME = ~/.local/opt/jdk;
#            pulled in by Maven and Flutter.
#   .NET:    Microsoft's SDK tarball, DOTNET_ROOT = ~/.local/opt/dotnet.

ANDROID_SDK_REL="Android/Sdk"
FLUTTER_REL=".local/share/flutter"

languages_setup() {
  log_step "Languages and SDKs"
  on NODE && node_setup
  on PYTHON && python_setup
  on GO && tar_app_install GO go bin/go gofmt=bin/gofmt
  if on JAVA || on MAVEN || on FLUTTER; then java_setup; fi
  on MAVEN && tar_app_install MAVEN mvn bin/mvn
  on FLUTTER && flutter_setup
  on RUST && rust_setup
  on DOTNET && dotnet_setup
  return 0
}

# opt_current NAME KEY — ~/.local/opt/NAME, a fixed path to the installed
# NAME-VERSION (for JAVA_HOME, DOTNET_ROOT).
opt_current() { run ln -sfn "$1-$(ver "$2_VERSION")" "$OPT_DIR/$1"; }

# ---- Node.js via nvm -----------------------------------------------------------
node_setup() {
  local script
  if [[ -x /usr/bin/node ]] && dpkg -S /usr/bin/node >/dev/null 2>&1; then
    log_warn "Ubuntu's nodejs package is installed as well ($(dpkg -S /usr/bin/node | cut -d: -f1)); Node should only come from nvm — remove it with: sudo apt purge nodejs"
  fi
  if [[ "$(as_user_sh '. "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 && nvm --version' 2>/dev/null)" != "$(ver NVM_VERSION)" ]]; then
    script="$(fetch NVM)"
    # PROFILE=/dev/null: nvm must not edit ~/.bashrc, our managed block loads it.
    as_user env PROFILE=/dev/null NVM_DIR="$TARGET_HOME/.nvm" bash "$script" >/dev/null
  fi
  as_user_sh '. "$HOME/.nvm/nvm.sh" && nvm install --lts --no-progress >/dev/null && nvm alias default "lts/*" >/dev/null && nvm use default >/dev/null && echo "node $(node --version) (nvm default: lts/*)"' \
    | while read -r l; do log_ok "$l"; done
  if on YARN_PNPM; then
    as_user_sh '. "$HOME/.nvm/nvm.sh" && nvm use default >/dev/null
      command -v corepack >/dev/null || npm install -g --silent corepack
      corepack enable && echo "yarn/pnpm via corepack $(corepack --version)"' \
      | while read -r l; do log_ok "$l"; done
  fi
}

# ---- Python via uv ----------------------------------------------------------------
python_setup() {
  bin_install UV uv
  bin_install UV uvx uvx
  as_user uv python install --default --preview-features python-install-default >/dev/null 2>&1 \
    || as_user uv python install --default >/dev/null
  # Not uv's python3 in ~/.local/bin: programs that embed Python (the Files
  # app's extensions, gvfs) find their home through `python3` on the desktop
  # session's PATH and would then miss the system's modules. `python` stays
  # uv's; the shells call it for python3 too (alias).
  local link="$BIN_DIR/python3"
  if [[ -L "$link" && "$(readlink "$link")" == "$TARGET_HOME/.local/share/uv/"* ]]; then run rm -f "$link"; fi
  log_ok "$(as_user_sh 'python --version 2>/dev/null || true') via uv (\`python\` in ~/.local/bin, \`python3\` in your shells)"
}

# ---- Java (Temurin) -----------------------------------------------------------------
java_setup() {
  tar_app_install JAVA jdk bin/java javac=bin/javac jar=bin/jar keytool=bin/keytool jshell=bin/jshell
  opt_current jdk JAVA
}

# ---- Flutter + Android SDK ------------------------------------------------------------
flutter_setup() {
  local want file tmp sdk="$TARGET_HOME/$ANDROID_SDK_REL" fl="$TARGET_HOME/$FLUTTER_REL"
  want="$(ver FLUTTER_VERSION)"
  # The SDK is a git checkout at its release tag.
  if [[ "$(git -C "$fl" describe --tags --exact-match 2>/dev/null)" != "$want" ]]; then
    file="$(fetch FLUTTER)"
    run rm -rf "$fl"; run mkdir -p "$fl"; run tar -xf "$file" -C "$fl" --strip-components=1
    log_ok "Flutter $want installed ($fl)"
  else
    log_ok "Flutter $want already installed"
  fi
  if [[ "$(cat "$sdk/cmdline-tools/latest/.version" 2>/dev/null)" != "$(ver ANDROID_CMDLINE_TOOLS_VERSION)" ]]; then
    file="$(fetch ANDROID_CMDLINE_TOOLS)"
    tmp="$(mktemp -d)"; unzip_to "$file" "$tmp"
    run rm -rf "$sdk/cmdline-tools/latest"; run mkdir -p "$sdk/cmdline-tools"
    run mv "$tmp/cmdline-tools" "$sdk/cmdline-tools/latest"; rm -rf "$tmp"
    [[ "$DRY_RUN" == 1 ]] || ver ANDROID_CMDLINE_TOOLS_VERSION >"$sdk/cmdline-tools/latest/.version"
  fi
  # Newest stable platform + build tools via the Android CLI (sdkmanager is
  # deprecated since cmdline-tools 23 and lists packages in another format);
  # it accepts the SDK licence itself. Then Flutter is told where the SDK is.
  as_user_sh "set -e; export JAVA_HOME='$OPT_DIR/jdk'; cli='$sdk/cmdline-tools/latest/bin/android'
    list=\$(\"\$cli\" --sdk='$sdk' sdk list --all)
    plat=\$(grep -oE '^ *platforms/android-[0-9]+(\.[0-9]+)? ' <<<\"\$list\" | tr -d ' ' | sort -V | tail -1)
    bt=\$(grep -oE '^ *build-tools/[0-9]+\.[0-9]+\.[0-9]+ ' <<<\"\$list\" | tr -d ' ' | sort -V | tail -1)
    [[ -n \"\$plat\" && -n \"\$bt\" ]] || { echo 'android sdk list: no stable platform/build-tools found' >&2; exit 1; }
    \"\$cli\" --sdk='$sdk' sdk install platform-tools \"\$plat\" \"\$bt\" </dev/null >/dev/null
    '$fl/bin/flutter' --disable-analytics >/dev/null 2>&1 || true
    '$fl/bin/flutter' config --android-sdk '$sdk' --jdk-dir '$OPT_DIR/jdk' >/dev/null
    echo \"Android SDK: platform-tools, \$plat, \$bt\""
  log_ok "Flutter + Android SDK ready"
}

# ---- Rust -------------------------------------------------------------------------------
rust_setup() {
  local file
  if [[ -x "$TARGET_HOME/.cargo/bin/rustup" ]]; then
    as_user "$TARGET_HOME/.cargo/bin/rustup" update stable >/dev/null
    log_ok "Rust updated"; return 0
  fi
  file="$(fetch RUSTUP)"; chmod 0755 "$file"
  as_user "$file" -y --no-modify-path --profile default >/dev/null
  log_ok "Rust installed (rustup)"
}

# ---- .NET ---------------------------------------------------------------------------------
dotnet_setup() {
  tar_app_install --flat DOTNET dotnet dotnet
  opt_current dotnet DOTNET
}
