# PowerShell 7+ プロファイル (dotfiles 管理)
# 配置先: $PROFILE → ~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1
# bootstrap.ps1 で symlink される
#
# 具体的なツール (oh-my-posh / Terminal Icons / PSReadLine 等) は
# Windows 環境で実装するときに追記する。
# 当面は最低限のエイリアスと PSReadLine 推奨設定のみ。

# === PSReadLine: 履歴検索を強化 ===
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

# === Mac / Linux 系から来た人向け alias ===
# (PowerShell 既定の ls=Get-ChildItem を上書きしない範囲で互換 helper)
function ll { Get-ChildItem -Force $args }
function la { Get-ChildItem -Force -Hidden $args }

# === git short alias (zsh の `g`/`gs`/`ga` 等を踏襲) ===
function g { git $args }
function gs { git status $args }
function ga { git add $args }
function gc { git commit $args }
function gl { git pull $args }
function gp { git push $args }

# === エディタ (nvim があれば vi/vim/v を nvim に) ===
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    function v   { nvim $args }
    function vi  { nvim $args }
    function vim { nvim $args }
    $env:EDITOR = 'nvim'
}

# === ディレクトリ移動の便利 ===
function .. { Set-Location .. }
function ... { Set-Location ../.. }

# === Windows ↔ WSL の橋渡し ===
function wsl-here {
    # 現在ディレクトリで WSL を起動
    wsl --cd (Get-Location).Path
}

# === starship があれば使う (winget で入れる想定) ===
# macOS/WSL と同じ prompt にするため共有 configs/shell/starship.toml を参照。
# (Windows ネイティブの clone 先は %USERPROFILE%\dotfiles)
if (Get-Command starship -ErrorAction SilentlyContinue) {
    $sharedStarship = Join-Path $env:USERPROFILE 'dotfiles\configs\shell\starship.toml'
    if (Test-Path $sharedStarship) { $env:STARSHIP_CONFIG = $sharedStarship }
    Invoke-Expression (& starship init powershell)
}

# === zoxide があれば使う ===
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
