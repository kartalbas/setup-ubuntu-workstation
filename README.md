# setup-ubuntu-workstation

Ubuntu 26.04 desktop becomes a developer workstation with a terminal that
behaves like **Windows Terminal**, PowerShell 7, the browsers, IDEs and AI
coding agents, Git, languages, Docker, Kubernetes and cloud CLIs — newest
versions, every download checked (SHA-256 or signed apt repository with a
verified key).

Almost everything goes into your home and belongs to you: your account
installs and updates it without sudo. Only what Ubuntu allows root alone
(packages, Docker, an AppArmor profile, a swap file, /tmp on the disk) is a separate step:

```bash
git clone <this-repo> setup-ubuntu-workstation && cd setup-ubuntu-workstation
sudo ./setup.sh system         # the system part (packages, browsers, Docker)
./setup.sh install             # everything else, in your home — no sudo
# log out and in once (docker group, fonts, menu, dock)
```

| Where | What |
|---|---|
| your home (`./setup.sh install`) | programs in `~/.local/bin` and `~/.local/opt` (kitty, PowerShell, Antigravity, Neovim, Go, Java, .NET, gcloud, the command-line tools, Kubernetes and cloud CLIs, Claude Code, Codex, OpenCode), fonts, menu entries, the Files app and Nemo additions, GNOME extensions, settings; nvm/Node, uv/Python, Flutter, Rust |
| the system (`sudo ./setup.sh system`) | Ubuntu packages (git, build-essential, htop, Ptyxis, Nemo, database clients, …), Chrome, Edge and VS Code (their apt repositories: `sudo apt upgrade` updates them), Chromium (snap, updates itself), Ghostty and Beyond Compare (.deb), Docker Engine with you in the `docker` group (docker then works without sudo), an AppArmor profile that lets Antigravity use Chromium's sandbox, as Ubuntu's own profiles do for VS Code and Chrome, a swap file (`SWAP_GB`, 16 GB) when the machine has no swap, and /tmp on the disk (`TMP_ON_DISK`; since 24.10 Ubuntu mounts it in RAM, up to half of it, so a big file there takes memory from the programs), emptied at every start as before |

`install` checks the system part first and names what is missing.

At the end it asks, one by one, to sign in to GitHub (`gh`, which also becomes
git's credential helper — no plain-text passwords; git's name and e-mail are
then taken from that account, with GitHub's private noreply address, unless
`GIT_USER_NAME`/`GIT_USER_EMAIL` are set), Claude Code, Codex, agy
and Muse, and for your own LLM servers for OpenCode. Muse 1.4 cannot keep its
login in the keyring on Linux yet
([muse-code-sdk#38](https://github.com/meta-models/muse-code-sdk/issues/38)), so
its file store (`~/.config/muse/auth.json`, 0600) is set for it. Skip any of them and
repeat later with `./setup.sh login`.

| Command | |
|---|---|
| `sudo ./setup.sh system` | the system part; again after switching on a tool that needs it, or for a newer Ghostty / Beyond Compare |
| `./setup.sh install` | install and configure everything else; re-run it any time (e.g. after a git pull) |
| `./setup.sh update` | every tool in your home with its installed and newest version; update all that is newer (Enter) or pick numbers (`2 5-7`); `--list` only shows, `--all` asks nothing. System packages: `sudo apt update && sudo apt upgrade` |
| `./setup.sh config set KEY 0\|1` | switch a tool on or off |
| `./setup.sh login` | the sign-ins above |
| `./setup.sh doctor` | the system part, then every enabled tool with its version |
| `./setup.sh opencode` | OpenCode with your own two LLM servers (below) |
| `./setup.sh configs [save]` | your settings from your own config repository, or back into it (below) |
| `./setup.sh config show` | the current settings |

Only `system` runs with sudo; every other command refuses it. Re-running is
safe and brings pinned tools to the versions in `versions.conf`.

**OpenCode with your own LLM servers** (OpenAI-compatible, e.g. llama-server):
`./setup.sh opencode` asks for the base URL, token and a display name of `llm1`
and `llm2`, reads model and context size from each server and writes
`~/.config/opencode/opencode.json` (mode 0600). URLs and tokens stay on your
machine; the repository only has the template with placeholders
(`templates/opencode.json`).

**Claude Code on the same servers**: `claude-llm1`, `claude-llm2` (one
`claude-<name>` per server in that file) start Claude Code with URL, token and
model from it; `claude-llm --list` shows them. The server has to speak
Anthropic's Messages API (llama-server does) and its chat template has to take
a system message in the middle of a conversation, which Claude Code sends.
Anthropic does not support other models in Claude Code: it works, but a Claude
Code update may break it.

## The terminals

Three terminals, each set up like Windows Terminal as far as it goes; tabs
show the name of the current directory:

- **kitty**, with **PowerShell 7** — Windows Terminal's keys, mouse and tabs (below).
- **Ghostty**, with PowerShell 7.
- **Terminal** (Ptyxis, Ubuntu's own), with **bash**.

`DEFAULT_TERMINAL` (kitty, ghostty or ptyxis; kitty unless set) is the one
Ctrl+Alt+T, "Open in Terminal" in Nemo and the F12 drop-down open.

| Keys / mouse | Action |
|---|---|
| Ctrl+C / Ctrl+V | copy when text is selected (else interrupt) / paste; also Ctrl+Shift+C/V, Ctrl+Insert, Shift+Insert, Ctrl+Shift+Insert |
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
bar cursor, 120×30, scrollbar, selecting does not copy. Cascadia is placed by
the hints built into the font, as on Windows; Ubuntu's light hinting would
round its lower case up a pixel and squeeze the text. For that the install
adds a fontconfig rule (kitty and every program that leaves hinting to
fontconfig), `freetype-load-flags = no-autohint` in Ghostty, and for Ptyxis
GNOME's full hinting, which GTK uses for the text of every application. Not in kitty: mark mode
(Ctrl+Shift+M), select all (Ctrl+Shift+A), a right-click menu on tabs. The
window runs through XWayland, so GNOME draws its title bar: move, resize, snap
and maximise like any other window.

The pwsh profile adds Windows editing keys, history suggestions as a list, a
prompt with the git state (`PS <path> [⑂ branch ↑1 M:2 untracked:1]>`, fetches
in the background every 10 minutes), `ll`, `la`, `l`, `which`, `gs`/`ga`/`gc`
for git status/add/commit, and `vim`, `cat`, `grep`, `find` as nvim, bat, rg,
fd. bash gets the starship prompt. AI agents (Claude Code, Codex,
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
switch tabs; the "+" menu offers its profiles. These settings are written
only where you have not set one yourself: what you change in Ptyxis's
preferences stays. It has no splits and copies with Ctrl+Shift+C.

**Nemo** is the file manager, set up like Windows Explorer: the folder tree on
the left, the details list (Name, Date modified, Type, Size) on the right,
folders first, double-click opens, sizes counted in 1024s (shown as KiB,
MiB), tabs with Ctrl+T/W and Ctrl+Tab, F2, F5,
Delete / Shift+Delete, Alt+Left/Right/Up, Alt+Enter, Ctrl+Shift+N, Ctrl+F,
and "Open in …" on right-click; "Copy as path" (right-click, Ctrl+Shift+C) puts
the full path of the selection on the clipboard, one per line, without quotes.
Folders open in it, Win+E opens it, and it
takes the Files app's place in the dock on the first install (unless `DOCK` sets the dock). Unlike Explorer, Backspace goes up and F3 opens a
second pane (fixed in Nemo). Nautilus stays installed: GNOME needs it for the
desktop icons and file dialogs, and "Show in folder" from an application may
still open it while it runs.

## The desktop

GNOME gets the Windows keys it lacks (`WINDOWS_KEYS`), where you have not set
the key yourself:

| Keys | Action |
|---|---|
| Win+R | run a command (as Alt+F2) |
| Ctrl+Esc | the overview with the search, as the Windows key alone |
| Win+Shift+S | screenshot: an area, a window or the screen (as Print) |
| Win+D | show the desktop (again: the windows come back) |
| Alt+Tab · Win+Tab | switch windows · switch applications (GNOME: Alt+Tab switches applications) |
| Win+I | Settings |
| Ctrl+Shift+Esc | the task manager, Resources (a custom shortcut: Settings → Keyboard) |
| Win+V | the clipboard history (`CLIPBOARD_HISTORY`, below); GNOME's notification list stays on Win+M |
| Win+E, Win+L, Win+Arrows | open Nemo · lock · arrange windows (GNOME's own, except Win+E) |

**Clipboard history** (`CLIPBOARD_HISTORY`): the GNOME extension Clipboard
Indicator, pinned, from extensions.gnome.org. Win+V opens the list of what you
copied; the entry you choose is pasted where you type, as on Windows (the
extension presses Shift+Insert, in a terminal Ctrl+Shift+Insert: both paste
in kitty, Ghostty and Ptyxis). Its own shortcuts
(Ctrl+F8…F12) are switched off: they would take those keys from every
application. GNOME loads it at the next login; switched off in the Extensions
app, it stays off.

**New Document** (`NEW_DOCUMENTS`): right-click in a folder → New Document →
"Text file" or "Markdown", in Nemo and the Files app (templates in
`~/Templates`; add your own there).

## Your own config repository

Keep your settings in a private repository of your own and put them on every
machine with one command. Set it once: `./setup.sh config set CONFIGS_REPO
OWNER/NAME`. It is cloned to `~/repos/<owner>/<name>`, and its folder
`setup-ubuntu-workstation/` holds:

| In the repository | Goes to |
|---|---|
| `config.conf` (with `DOCK`, the dock of a new machine) | `~/.config/setup-ubuntu-workstation/config.conf` |
| `kitty/local.conf`, `ghostty/local.conf` | `~/.config/kitty/`, `~/.config/ghostty/` |
| `powershell/profile.local.ps1` | `~/.config/powershell/` |
| `opencode/opencode.json` (URLs and tokens of your LLM servers) | `~/.config/opencode/opencode.json` (0600) |
| `nemo/settings.ini` (Nemo's settings, without a window's size and place) | GNOME settings `/org/nemo/` |
| `nemo/actions-tree.json` (Nemo's action menu and its shortcuts) · `nemo/bookmarks` (side pane; also the Files app's and the file dialogs') | `~/.config/nemo/`, `~/.config/gtk-3.0/bookmarks` |
| `ssh/` (your SSH keys, `config`; `authorized_keys`: the keys that may log in to your machines) | `~/.ssh/` (private keys 0600, `*.pub` 0644); a different file already there is left alone; of `authorized_keys` the keys missing in yours are added |
| `hosts/<hostname>/…` | the same files, for that machine only |

`./setup.sh configs` pulls the repository and puts the files in place, and
`./setup.sh install` does the same first (so its `config.conf` counts);
`./setup.sh configs save` copies yours back (from `~/.ssh` only `id_*` and
`config`, never `authorized_keys` or `known_hosts`), commits and pushes.
`DOCK` sets the dock of a new machine (also when it only comes with the second
install, the first with your config repository); once you arrange the dock
yourself it is yours: install, doctor and `configs save` leave it alone. A new machine then needs: `./setup.sh config set
CONFIGS_REPO OWNER/NAME`, `sudo ./setup.sh system`, `./setup.sh install`,
the sign-ins, `./setup.sh install` once more (now with your config). The files are kept
as they are, tokens and private keys included — keep the repository private.

## Where your settings live

Nothing of this goes into git — the repository only has examples with
placeholders (`config.example.conf`, `templates/opencode.json`).

| What | Where | Mode |
|---|---|---|
| Which tools are on or off | `~/.config/setup-ubuntu-workstation/config.conf` | 644 |
| Newer versions chosen with `update` (only once you chose one) | `~/.config/setup-ubuntu-workstation/versions.local.conf` | 644 |
| OpenCode: your LLM servers with URL, token and name | `~/.config/opencode/opencode.json` | 600 |
| SSH keys (from your config repository) | `~/.ssh/id_*` | 600 |
| Your own terminal and shell settings (never overwritten) | `~/.config/kitty/local.conf`, `~/.config/ghostty/local.conf`, `~/.config/powershell/profile.local.ps1`, `~/.bashrc` outside the marked block | 644 |
| GNOME settings (Ptyxis, Nemo, keys, clipboard history, font hinting, dock): what this setup set and what you changed | `~/.config/dconf/user` | 664 |
| git name and e-mail | `~/.gitconfig` | 664 |
| Sign-ins | gh `~/.config/gh/hosts.yml` (token in the keyring), Claude Code `~/.claude/.credentials.json`, Codex `~/.codex/auth.json`, Muse `~/.config/muse/auth.json`, agy in the GNOME keyring (`~/.local/share/keyrings/`) | 600 |

The files `setup-ubuntu-workstation` manages (`kitty.conf`, `config.ghostty`,
`profile.ps1`, the marked block in `~/.bashrc`, …) are rewritten by `install`;
put your own settings into the files above instead.

## What gets installed

`on` = default. Change with `./setup.sh config set KEY 0|1` (the keys and
numbers are in `~/.config/setup-ubuntu-workstation/config.conf`), then run
install again (and `sudo ./setup.sh system` for the ones marked *system*).
Nothing is removed when switched off.

| Nr | Tool | Source | On |
|---|---|---|---|
| **A** | **Terminal, shell and desktop** | | |
| 1 | kitty (default terminal) | GitHub, pinned, `~/.local/opt` | ✓ |
| 2 | Ghostty (to compare) | Ubuntu .deb (community), pinned — *system* | ✓ |
| 69 | Terminal (Ptyxis) set up like Windows Terminal, with bash; GNOME full font hinting | Ubuntu — *system* | ✓ |
| 72 | Files app: "Open in" kitty, Ghostty, Terminal (Ptyxis), VS Code, Antigravity IDE | this repo (nautilus-python: *system*) | ✓ |
| 75 | Nemo as the file manager, like Windows Explorer (below) | Ubuntu — *system* | ✓ |
| 3 | Quake Terminal: drop-down on F12 | GNOME extension, pinned | |
| 78 | Windows' keys: Win+R, Ctrl+Esc, Win+Shift+S, Win+D, Alt+Tab, Win+I, Ctrl+Shift+Esc (above) | this repo | ✓ |
| 79 | Clipboard history on Win+V (Clipboard Indicator) | GNOME extension, pinned | ✓ |
| 80 | New Document: text file, Markdown | this repo | ✓ |
| 4 | PowerShell 7 | GitHub tarball, pinned, `~/.local/opt` | ✓ |
| 5 | pwsh profile | this repo | ✓ |
| 6 | starship prompt | GitHub, pinned | ✓ |
| 7 | zoxide | GitHub, pinned | |
| 8 | Cascadia Code / Mono, drawn with their own hints as on Windows | Microsoft (GitHub), pinned | ✓ |
| 9 | Nerd Fonts (Caskaydia, FiraCode, JetBrains Mono) | GitHub, pinned | ✓ |
| **B** | **Browsers, editors, IDEs** | | |
| 10 | Google Chrome | Google apt repo — *system* | ✓ |
| 66 | Microsoft Edge | Microsoft apt repo — *system* | ✓ |
| 67 | Chromium | snap (Canonical), updates itself — *system* | ✓ |
| 11 | VS Code | Microsoft apt repo — *system* | ✓ |
| 12 | Antigravity IDE 2.x (the apt repository only has the old 1.x) | Google tarball, pinned, `~/.local/opt` (+ AppArmor profile: *system*) | ✓ |
| 73 | Antigravity 2.0, the agent manager (`antigravity-hub`) | Google tarball, pinned, `~/.local/opt` | ✓ |
| 13 | JetBrains Toolbox (in `~/.local/share/JetBrains/Toolbox`, updates itself) | JetBrains, pinned first version | ✓ |
| 14 | Neovim, Vim | GitHub tarball, pinned / Ubuntu (*system*) | ✓ |
| 15 | Beyond Compare (licence needed) | vendor .deb, pinned — *system* | ✓ |
| **C** | **AI coding agents** | | |
| 16 | Claude Code (`CLAUDE_CHANNEL`: latest or stable) | Anthropic installer, updates itself | ✓ |
| 17 | Codex CLI | GitHub, pinned | ✓ |
| 18 | Antigravity CLI (agy) | Google installer, ~/.local/bin | ✓ |
| 68 | Muse Code (muse) | Meta installer, ~/.local/bin | ✓ |
| 70 | OpenCode (opencode) | GitHub, pinned | ✓ |
| 74 | `claude-<server>`: Claude Code on your own LLM servers (below) | this repo | ✓ |
| **D** | **Git and GitHub** | | |
| 19 | git | git-core PPA — *system* | ✓ |
| 20 | GitHub CLI (also git's credential helper) | GitHub, pinned | ✓ |
| 21 | git-lfs | GitHub, pinned | ✓ |
| 22 | lazygit | GitHub, pinned | ✓ |
| 23 | delta | GitHub, pinned | |
| 77 | gitleaks — credential scan; ai-core's push gate runs it before a push | GitHub, pinned | ✓ |
| **E** | **Command-line tools** | | |
| 24-29 | jq · yq · ripgrep · fd · fzf · bat | GitHub, pinned | ✓ |
| 30-32 | 7-Zip · Midnight Commander · curl, wget, tree, htop, openssl, unzip | Ubuntu — *system* | ✓ |
| 76 | build-essential: gcc, g++, make — for npm and pip modules with native parts, Rust crates | Ubuntu — *system* | ✓ |
| **F** | **Languages** | | |
| 33 | Node.js — only via nvm, newest LTS, set as default | nvm, pinned | ✓ |
| 34 | yarn, pnpm | Corepack on the nvm Node | ✓ |
| 35 | Python (newest) | uv, pinned | ✓ |
| 36 | Go | go.dev tarball, pinned, `~/.local/opt` | ✓ |
| 37 | Java (Eclipse Temurin, LTS; `JAVA_HOME=~/.local/opt/jdk`) | Adoptium tarball, pinned (pulled in by 38/39) | |
| 38 | Maven | Apache tarball, pinned | |
| 39 | Flutter + Android SDK (newest platform, build-tools) | Google tarballs, pinned; Android CLI | ✓ |
| 40 | Rust | rustup, pinned | |
| 41 | .NET SDK (`DOTNET_ROOT=~/.local/opt/dotnet`) | Microsoft tarball, pinned | |
| **G** | **Database clients** | | |
| 42-45 | psql · mongosh · redis-cli · mysql | Ubuntu (*system*) / MongoDB tarball | ✓ |
| **H** | **Containers and Kubernetes** | | |
| 46 | Docker CLI, buildx, compose | Docker apt repo — *system* | ✓ |
| 47 | Docker Engine (no Docker Desktop); you in the `docker` group | Docker apt repo — *system* | ✓ |
| 48 | kubectl | dl.k8s.io, pinned | ✓ |
| 49 | helm | get.helm.sh, pinned | ✓ |
| 50-51 | kind · k9s | GitHub, pinned | |
| 52 | kubectx, kubens | GitHub, pinned | ✓ |
| 53-55 | stern · krew · cmctl | GitHub, pinned | |
| 56 | Argo CD CLI | GitHub, pinned | ✓ |
| 57 | Tekton CLI (tkn) | GitHub, pinned | ✓ |
| 58 | Argo Workflows + Rollouts CLIs | GitHub, pinned | |
| **I** | **Cloud** | | |
| 59-60 | Azure CLI · gcloud | PyPI via uv / Google tarball, pinned | ✓ |
| 61-62 | terraform · vault | HashiCorp releases, pinned | ✓ |
| 63 | mkcert | GitHub, pinned | ✓ |
| **J** | **Setup** | | |
| 64 | git identity (`GIT_USER_NAME`/`EMAIL` or asked) | | ✓ |
| 65 | sign-ins: gh (+ git credentials), Claude Code, Codex, agy, Muse | | ✓ |
| – | `DOCK`: the dock of the first install (desktop entry ids); after that it is yours | your config | |
| 81 | swap file `/swap.img` of `SWAP_GB` GB (16) when there is no swap; 0 = none | *system* | ✓ |
| 82 | /tmp on the disk (`systemctl mask tmp.mount`), emptied at every start; from the next start | *system* | ✓ |

## Maintenance

- **Newest versions:** `tools/pin-versions.sh > versions.conf.new`, review the
  diff against `versions.conf`, test, commit. Tools from apt repositories
  (Chrome, Edge, VS Code, Docker, …) update with `sudo apt upgrade`; Claude
  Code and JetBrains Toolbox update themselves, agy and Muse when install runs
  again.
- **apt sources:** the files marked `# Managed by setup-ubuntu-workstation` in
  `/etc/apt/sources.list.d` belong to this script. Chrome, Edge, VS Code and
  Beyond Compare keep their own source there (`google-chrome`,
  `microsoft-edge`, `vscode`, `scootersoftware`); the first install of the
  first three goes through a temporary `bootstrap-*` source with a verified
  key, which install removes again.
- `tests/run.sh` — shellcheck and unit tests (no root needed).

## Layout

```
setup.sh            entry point: system (sudo), install, update, login, doctor, config
lib/common.sh       logging, config, downloads + checksums, installs into the home, apt
modules/05-system.sh, 10-repos.sh   the system part (sudo ./setup.sh system)
modules/NN-*.sh     the rest, one area each (base, shell, terminal, apps, ai, …)
templates/          files written to the machine (terminal and shell configs, AppArmor)
versions.conf       pinned artifacts (URL + SHA-256/512), from tools/pin-versions.sh
config.example.conf numbered switches, copied to ~/.config on the first run
```
