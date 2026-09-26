# setup-ubuntu-workstation

One clone, one command: Ubuntu 26.04 desktop becomes a developer workstation
with a terminal that behaves like **Windows Terminal**, PowerShell 7, the
browsers, IDEs and AI coding agents, Git, languages, Docker, Kubernetes and
cloud CLIs — newest versions, every download checked (SHA-256 or signed apt
repository with a verified key).

```bash
git clone <this-repo> setup-ubuntu-workstation && cd setup-ubuntu-workstation
sudo ./setup.sh install        # everything in the table below that is "on"
# log out and in once (docker group, fonts, default terminal)
```

At the end it asks, one by one, to sign in to GitHub (`gh`, which also becomes
git's credential helper — no plain-text passwords; git's name and e-mail are
then taken from that account, with GitHub's private noreply address, unless
`GIT_USER_NAME`/`GIT_USER_EMAIL` are set), Claude Code, Codex, agy
and Muse, and for your own LLM servers for OpenCode. Muse 1.4 cannot keep its
login in the keyring on Linux yet
([muse-code-sdk#38](https://github.com/meta-models/muse-code-sdk/issues/38)), so
its file store (`~/.config/muse/auth.json`, 0600) is set for it. Skip any of them and
repeat later with `./setup.sh login`.

Only what changes the system needs sudo (`install`, `config set`); everything
for your own account runs without it:

| Command | |
|---|---|
| `sudo ./setup.sh install` | install and configure everything enabled; re-run it any time (e.g. after a git pull) |
| `sudo ./setup.sh update` | every tool with its installed and newest version; update all that is newer (Enter) or pick numbers (`2 5-7`); `--list` only shows, `--all` asks nothing |
| `sudo ./setup.sh config set KEY 0\|1` | switch a tool on or off |
| `./setup.sh login` | the sign-ins above |
| `./setup.sh doctor` | every enabled tool with its version |
| `./setup.sh opencode` | OpenCode with your own two LLM servers (below) |
| `./setup.sh config show` | the current settings |

Per-user parts (nvm/Node, Python, Flutter, agy, Muse, terminal and shell
settings) go to your home, system parts to the system. Re-running is safe and
brings pinned tools to the versions in `versions.conf`.

**OpenCode with your own LLM servers** (OpenAI-compatible, e.g. llama-server):
`./setup.sh opencode` asks for the base URL, token and a display name of `llm1`
and `llm2`, reads model and context size from each server and writes
`~/.config/opencode/opencode.json` (mode 0600). URLs and tokens stay on your
machine; the repository only has the template with placeholders
(`templates/opencode.json`).

## The terminals

Three terminals, each set up like Windows Terminal as far as it goes; tabs
show the name of the current directory:

- **kitty**, the default (Ctrl+Alt+T, "Open in Terminal"), with **PowerShell 7**
  — Windows Terminal's keys, mouse and tabs (below).
- **Ghostty**, with PowerShell 7, to compare.
- **Terminal** (Ptyxis, Ubuntu's own), with **bash**.

| Keys / mouse | Action |
|---|---|
| Ctrl+C / Ctrl+V | copy when text is selected (else interrupt) / paste; also Ctrl+Shift+C/V, Ctrl+Insert, Shift+Insert |
| right click · Ctrl+click | copy the selection, else paste · open a link |
| tab: double-click · drag · middle click | rename · move (also out into a new window) · close |
| Ctrl+Shift+T, Ctrl+Shift+D, Ctrl+Shift+N | new tab, duplicate tab, new window |
| Ctrl+Shift+1 / 2 · Ctrl+Shift+Space | new PowerShell / Bash tab · profile menu (also SSH hosts) |
| Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+Alt+1..9 | next / previous tab, tab N |
| Alt+Shift+Plus / Minus / D, Ctrl+Shift+W | split right / down / automatic, close pane |
| Alt+Arrows, Alt+Shift+Arrows, Ctrl+Alt+Left | move between panes, move the divider, last pane |
| Ctrl+Shift+P, Ctrl+Shift+F | command palette (every kitty action), search |
| Ctrl+Shift+Up/Down/PgUp/PgDn/Home/End | scroll |
| Ctrl+Plus/Minus/0, Alt+Enter or F11 | zoom, full screen |
| Ctrl+, | edit your own settings (`~/.config/kitty/local.conf`) |

Windows Terminal's defaults as well: Cascadia Mono 12, the Campbell colours,
bar cursor, 120×30, scrollbar, selecting does not copy. Not in kitty: mark mode
(Ctrl+Shift+M), select all (Ctrl+Shift+A), a right-click menu on tabs. The
window runs through XWayland, so GNOME draws its title bar: move, resize, snap
and maximise like any other window.

The pwsh profile adds Windows editing keys, history suggestions as a list, the
starship prompt and Ubuntu's `ll`, `la`, `l`. AI agents (Claude Code, Codex,
…) run their commands in bash whatever the terminal's shell is. The managed
files load one of your own that is never overwritten (`local.conf`,
`profile.local.ps1`).

**Ghostty** is a native GNOME app: GTK tabs you drag around, right click on a
tab → "Change Tab Title…", select all (Ctrl+Shift+A); no renaming by
double-click and no profiles (Ctrl+Shift+Space, Ctrl+Shift+1/2). It has no
official Linux build and comes from the Ubuntu .deb listed on ghostty.org
(community-built, pinned).

**Terminal (Ptyxis)** gets Windows Terminal's font, colours, size, bar cursor
and word selection, Ctrl+V pastes, Ctrl+Tab / Ctrl+Shift+Tab and Ctrl+Alt+1..9
switch tabs; the "+" menu offers its profiles. These are system-wide
defaults: Ptyxis's own preferences still change them. It has no splits and
copies with Ctrl+Shift+C.

WezTerm and Contour, which earlier versions of this repository installed, are
removed again by `install`.

## What gets installed

`on` = default. Change with `sudo ./setup.sh config set KEY 0|1` (the keys and
numbers are in `/etc/setup-ubuntu-workstation/config.conf`), then run install
again. Nothing is removed when switched off.

| Nr | Tool | Source | On |
|---|---|---|---|
| **A** | **Terminal and shell** | | |
| 1 | kitty (default terminal) | GitHub, pinned | ✓ |
| 2 | Ghostty (to compare) | Ubuntu .deb (community), pinned | ✓ |
| 69 | Terminal (Ptyxis) set up like Windows Terminal, with bash | Ubuntu | ✓ |
| 3 | Quake Terminal: drop-down on F12 | GNOME extension, pinned | |
| 4 | PowerShell 7 LTS | GitHub .deb, pinned | ✓ |
| 5 | pwsh profile | this repo | ✓ |
| 6 | starship prompt | GitHub, pinned | ✓ |
| 7 | zoxide | GitHub .deb, pinned | |
| 8 | Cascadia Code / Mono | Ubuntu | ✓ |
| 9 | Nerd Fonts (Caskaydia, FiraCode, JetBrains Mono) | GitHub, pinned | ✓ |
| **B** | **Browsers, editors, IDEs** | | |
| 10 | Google Chrome | Google apt repo | ✓ |
| 66 | Microsoft Edge | Microsoft apt repo | ✓ |
| 67 | Chromium | snap (Canonical) | ✓ |
| 11 | VS Code | Microsoft apt repo | ✓ |
| 12 | Antigravity IDE 2.x (the apt repository only has the old 1.x) | Google tarball, pinned | ✓ |
| 13 | JetBrains Toolbox | JetBrains tarball, pinned | ✓ |
| 14 | Neovim, Vim | GitHub tarball, pinned / Ubuntu | ✓ |
| 15 | Beyond Compare (licence needed) | vendor .deb, pinned | ✓ |
| **C** | **AI coding agents** | | |
| 16 | Claude Code (+ sandbox: bubblewrap, socat, AppArmor profile) | Anthropic apt repo (channel `latest`) | ✓ |
| 17 | Codex CLI | GitHub, pinned | ✓ |
| 18 | Antigravity CLI (agy) | Google installer, ~/.local/bin | ✓ |
| 68 | Muse Code (muse) | Meta installer, ~/.local/bin | ✓ |
| 70 | OpenCode (opencode) | GitHub, pinned | ✓ |
| **D** | **Git and GitHub** | | |
| 19 | git | git-core PPA | ✓ |
| 20 | GitHub CLI | GitHub apt repo | ✓ |
| 21 | git-lfs | GitHub, pinned | ✓ |
| 22 | lazygit | GitHub, pinned | ✓ |
| 23 | delta | GitHub .deb, pinned | |
| **E** | **Command-line tools** | | |
| 24-29 | jq · yq · ripgrep · fd · fzf · bat | Ubuntu / GitHub, pinned | ✓ |
| 30-32 | 7-Zip · Midnight Commander · curl, wget, tree, htop, openssl, unzip | Ubuntu | ✓ |
| **F** | **Languages** | | |
| 33 | Node.js — only via nvm, newest LTS, set as default | nvm, pinned | ✓ |
| 34 | yarn, pnpm | Corepack on the nvm Node | ✓ |
| 35 | Python (newest) | uv, pinned | ✓ |
| 36 | Go | go.dev tarball, pinned | ✓ |
| 37 | Java (OpenJDK LTS) | Ubuntu (pulled in by 38/39) | |
| 38 | Maven | Apache tarball, pinned | |
| 39 | Flutter + Android SDK (newest platform, build-tools) | Google tarballs, pinned; Android CLI | ✓ |
| 40 | Rust | rustup, pinned | |
| 41 | .NET SDK | Ubuntu | |
| **G** | **Database clients** | | |
| 42-45 | psql · mongosh · redis-cli · mysql | Ubuntu / GitHub .deb | ✓ |
| **H** | **Containers and Kubernetes** | | |
| 46 | Docker CLI, buildx, compose | Docker apt repo | ✓ |
| 47 | Docker Engine (no Docker Desktop) | Docker apt repo | ✓ |
| 48 | kubectl | pkgs.k8s.io | ✓ |
| 49 | helm | Helm apt repo | ✓ |
| 50-51 | kind · k9s | GitHub, pinned | |
| 52 | kubectx, kubens | GitHub, pinned | ✓ |
| 53-55 | stern · krew · cmctl | GitHub, pinned | |
| 56 | Argo CD CLI | GitHub, pinned | ✓ |
| 57 | Tekton CLI (tkn) | GitHub .deb, pinned | ✓ |
| 58 | Argo Workflows + Rollouts CLIs | GitHub, pinned | |
| **I** | **Cloud** | | |
| 59-60 | Azure CLI · gcloud | Microsoft / Google apt repos | ✓ |
| 61-62 | terraform · vault | HashiCorp apt repo | ✓ |
| 63 | mkcert | GitHub, pinned | ✓ |
| **J** | **Setup** | | |
| 64 | git identity (`GIT_USER_NAME`/`EMAIL` or asked) | | ✓ |
| 65 | sign-ins: gh (+ git credentials), Claude Code, Codex, agy, Muse | | ✓ |

## Maintenance

- **Newest versions:** `tools/pin-versions.sh > versions.conf.new`, review the
  diff against `versions.conf`, test, commit. Tools from apt repositories
  (Chrome, Edge, VS Code, Claude Code, Docker, …) update with the system;
  agy and Muse update when install runs again.
- **apt sources:** the files marked `# Managed by setup-ubuntu-workstation` in
  `/etc/apt/sources.list.d` belong to this script. Chrome, Edge, VS Code and
  Beyond Compare keep their own source there (`google-chrome`,
  `microsoft-edge`, `vscode`, `scootersoftware`); the first install of the
  first three goes through a temporary `bootstrap-*` source with a verified
  key, which install removes again.
- `tests/run.sh` — shellcheck and unit tests (no root needed).

## Layout

```
setup.sh            entry point: install, login, doctor, config
lib/common.sh       logging, config, downloads + checksums, apt repositories
modules/NN-*.sh     one area each (repos, base, shell, terminal, apps, ai, …)
templates/          files written to the machine (terminal and shell configs)
versions.conf       pinned artifacts (URL + SHA-256), from tools/pin-versions.sh
config.example.conf numbered switches, copied to /etc on the first run
```
