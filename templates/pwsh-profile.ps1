# Managed by setup-ubuntu-workstation — your own settings go into
# profile.local.ps1 next to this file (loaded last, never overwritten).

# Editing like on Windows: Windows keys, history-based suggestions as a list,
# Tab cycles through completions.
# (Interactive terminal windows only: scripts and redirected output get none of it.)
if ((Get-Module -ListAvailable PSReadLine) -and -not [Console]::IsOutputRedirected -and
    $Host.UI.RawUI.WindowSize.Width -ge 50 -and $Host.UI.RawUI.WindowSize.Height -ge 5) {
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

function Add-PathFront([string] $dir) {
    if ((Test-Path $dir) -and -not ($env:PATH -split ':' -contains $dir)) { $env:PATH = "${dir}:$env:PATH" }
}

# Node.js from nvm: follow the default alias (default -> lts/* -> lts/<name>
# -> vX.Y.Z) to its bin directory, like `nvm use default` does in bash.
$nvmDir = Join-Path $HOME '.nvm'
$alias = 'default'
for ($i = 0; $i -lt 6 -and $alias -notmatch '^v\d'; $i++) {
    $file = Join-Path $nvmDir "alias/$alias"
    if (-not (Test-Path -LiteralPath $file)) { break }
    $alias = (Get-Content -LiteralPath $file -TotalCount 1).Trim()
}
if ($alias -match '^v\d') {
    $env:NVM_DIR = $nvmDir
    Add-PathFront (Join-Path $nvmDir "versions/node/$alias/bin")
}
Add-PathFront (Join-Path $HOME '.local/bin')
Add-PathFront '/usr/local/go/bin'
Add-PathFront (Join-Path $HOME 'go/bin')
if (Test-Path (Join-Path $HOME '.local/share/flutter/bin')) {
    $env:ANDROID_HOME = Join-Path $HOME 'Android/Sdk'
    Add-PathFront (Join-Path $env:ANDROID_HOME 'platform-tools')
    Add-PathFront (Join-Path $env:ANDROID_HOME 'cmdline-tools/latest/bin')
    Add-PathFront (Join-Path $HOME '.local/share/flutter/bin')
}
Add-PathFront (Join-Path $HOME '.cargo/bin')
Add-PathFront (Join-Path $HOME '.krew/bin')
Add-PathFront (Join-Path $HOME '.local/share/JetBrains/Toolbox/scripts')   # IDE launchers

# ---- Commands --------------------------------------------------------------------
# The real ls and pwd, not PowerShell's aliases; gc is Get-Content's alias,
# which would win over the git shortcut below.
Remove-Item Alias:ls, Alias:pwd, Alias:gc -Force -ErrorAction SilentlyContinue
function ls { & /usr/bin/ls --color=auto @args }
function ll { Get-ChildItem -Force @args }
function la { & /usr/bin/ls --color=auto -A @args }
function l { & /usr/bin/ls --color=auto -CF @args }
function gs { git status @args }
function ga { git add @args }
function gc { git commit @args }
# which: the program's path, or what an alias points to.
function which([string] $Name) {
    $c = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) { return }
    switch ($c.CommandType) {
        'Application' { $c.Source }
        'Alias' { "$Name -> $($c.Definition)" }
        default { "$Name ($($c.CommandType))" }
    }
}
# The newer tools under the familiar names, where they are installed.
foreach ($pair in @(('vim', 'nvim'), ('cat', 'bat'), ('grep', 'rg'), ('find', 'fd'))) {
    if (Get-Command $pair[1] -CommandType Application -ErrorAction SilentlyContinue) { Set-Alias $pair[0] $pair[1] }
}
# uv's Python for python3 in the shell; the desktop keeps the system's.
if (Test-Path "$HOME/.local/bin/python") { Set-Alias python3 "$HOME/.local/bin/python" }

if (Get-Command zoxide -ErrorAction SilentlyContinue) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }
# Muse 1.4 cannot store its login in the keyring on Linux yet
# (github.com/meta-models/muse-code-sdk/issues/38): use its file store.
if (Get-Command muse -ErrorAction SilentlyContinue) { $env:TBH_CREDENTIAL_BACKEND = 'file' }

# Tab title: the name of the current directory, set at every prompt.
function Set-TabTitle {
    $Host.UI.RawUI.WindowTitle = if ($PWD.ProviderPath -eq '/') { '/' } else { Split-Path -Leaf $PWD.ProviderPath }
}

# ---- Prompt ------------------------------------------------------------------------
# PS <path> [⑂ branch ↑ahead ↓behind Ai: Ri: Mi: Di: | M: D: U: | untracked: stashes:]>
# One `git status` per prompt; the fetch that keeps ↑/↓ current runs in the
# background, at most every 10 minutes. The last command's exit code stays.
function Write-GitCount([string] $Label, [int] $Count, [string] $Color) {
    if ($Count -gt 0) {
        Write-Host $Label -NoNewline -ForegroundColor White
        Write-Host $Count -NoNewline -ForegroundColor $Color
    }
}
function Prompt {
    $lastExit = $global:LASTEXITCODE
    Set-TabTitle
    $g = $null
    $status = git status --porcelain=v2 --branch 2>$null
    if ($LASTEXITCODE -eq 0 -and $status) {
        $g = @{ ahead = 0; behind = 0; Ai = 0; Ri = 0; Mi = 0; Di = 0; M = 0; D = 0; U = 0; untracked = 0 }
        foreach ($line in $status) {
            if ($line -like '# branch.head *') { $g.branch = $line.Substring(14) }
            elseif ($line -match '^# branch\.ab \+(\d+) -(\d+)') { $g.ahead = [int]$Matches[1]; $g.behind = [int]$Matches[2] }
            elseif ($line -match '^[12] (.)(.) ') {
                switch ($Matches[1]) { 'A' { $g.Ai++ } 'M' { $g.Mi++ } 'D' { $g.Di++ } 'R' { $g.Ri++ } }
                switch ($Matches[2]) { 'M' { $g.M++ } 'D' { $g.D++ } }
            }
            elseif ($line -like 'u *') { $g.U++ }
            elseif ($line -like '? *') { $g.untracked++ }
        }
        $g.label = if ($g.branch -eq '(detached)') { git describe --tags --always 2>$null } else { "⑂ $($g.branch)" }
        $g.stashes = @(git stash list 2>$null).Count
        $fetchHead = Join-Path (git rev-parse --git-dir 2>$null) 'FETCH_HEAD'
        if (-not (Test-Path $fetchHead) -or ((Get-Date) - (Get-Item $fetchHead).LastWriteTime).TotalMinutes -gt 10) {
            $null = New-Item $fetchHead -ItemType File -Force -ErrorAction SilentlyContinue   # no second fetch meanwhile
            & /bin/sh -c 'GIT_TERMINAL_PROMPT=0 git fetch --all --quiet >/dev/null 2>&1 &'
        }
    }
    if (Test-Path variable:/PSDebugContext) { Write-Host '[DBG]: ' -NoNewline -ForegroundColor Yellow }
    Write-Host 'PS ' -NoNewline -ForegroundColor White
    Write-Host $executionContext.SessionState.Path.CurrentLocation -NoNewline -ForegroundColor White
    if ($g) {
        Write-Host ' [' -NoNewline -ForegroundColor Magenta
        Write-Host $g.label -NoNewline -ForegroundColor $(if ($g.branch -in 'master', 'main') { 'White' } else { 'Red' })
        Write-GitCount ' ↑' $g.ahead Green
        Write-GitCount ' ↓' $g.behind Yellow
        Write-GitCount ' Ai:' $g.Ai Green
        Write-GitCount ' Ri:' $g.Ri DarkGreen
        Write-GitCount ' Mi:' $g.Mi Yellow
        Write-GitCount ' Di:' $g.Di Red
        if (($g.Ai + $g.Ri + $g.Mi + $g.Di) -and ($g.M + $g.D + $g.U)) { Write-Host ' |' -NoNewline -ForegroundColor White }
        Write-GitCount ' M:' $g.M Yellow
        Write-GitCount ' D:' $g.D Red
        Write-GitCount ' U:' $g.U Red
        if ($g.untracked + $g.stashes) { Write-Host ' |' -NoNewline -ForegroundColor White }
        Write-GitCount ' untracked:' $g.untracked Red
        Write-GitCount ' stashes:' $g.stashes Yellow
        Write-Host ']' -NoNewline -ForegroundColor Magenta
    }
    Write-Host ('>' * ($nestedPromptLevel + 1)) -NoNewline -ForegroundColor White
    $global:LASTEXITCODE = $lastExit
    ' '
}

$local = Join-Path $PSScriptRoot 'profile.local.ps1'
if (Test-Path $local) { . $local }
