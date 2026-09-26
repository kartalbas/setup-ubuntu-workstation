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

# Linux habits: the shortcuts Ubuntu's ~/.bashrc defines (ll, la, l) and
# coloured ls/grep, calling the real commands.
function ls { & /usr/bin/ls --color=auto @args }
function ll { & /usr/bin/ls --color=auto -alF @args }
function la { & /usr/bin/ls --color=auto -A @args }
function l { & /usr/bin/ls --color=auto -CF @args }
function grep { & /usr/bin/grep --color=auto @args }

if (Get-Command zoxide -ErrorAction SilentlyContinue) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }
# Muse 1.4 cannot store its login in the keyring on Linux yet
# (github.com/meta-models/muse-code-sdk/issues/38): use its file store.
if (Get-Command muse -ErrorAction SilentlyContinue) { $env:TBH_CREDENTIAL_BACKEND = 'file' }

# Tab title: the name of the current directory, set at every prompt.
function Set-TabTitle {
    $Host.UI.RawUI.WindowTitle = if ($PWD.ProviderPath -eq '/') { '/' } else { Split-Path -Leaf $PWD.ProviderPath }
}
if (Get-Command starship -ErrorAction SilentlyContinue) {
    function Invoke-Starship-PreCommand { Set-TabTitle }   # starship calls it before each prompt
    Invoke-Expression (& starship init powershell)
} else {
    $DefaultPrompt = $function:prompt
    function prompt { Set-TabTitle; & $DefaultPrompt }
}

$local = Join-Path $PSScriptRoot 'profile.local.ps1'
if (Test-Path $local) { . $local }
