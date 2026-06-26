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

# === scoop と winget の重複ツールを診断 ===
# 方針: winget が一次パッケージマネージャ。scoop は winget に無いものだけ補助で使う。
# 同名ツールが両方から入った時は PATH 順で勝った方になるが、意図と違うことがあるので
# `Find-DotfilesToolOverlap` を呼んで重複を可視化。重複が見つかったら winget 残し /
# scoop 側 `scoop uninstall <name>` で揃える。
function Find-DotfilesToolOverlap {
    $scoopRoot = Join-Path $env:USERPROFILE 'scoop\shims'
    if (-not (Test-Path $scoopRoot)) { Write-Host 'scoop が未導入のため重複なし。'; return }
    $tools = 'starship','zoxide','gh','nvim','yazi','bat','fzf','rg','fd','jq','lazygit','sops','age','oh-my-posh','git'
    $overlap = @()
    foreach ($t in $tools) {
        $cmds = @(Get-Command $t -All -ErrorAction SilentlyContinue | Where-Object CommandType -eq 'Application')
        if ($cmds.Count -lt 2) { continue }
        $sources = $cmds | ForEach-Object { $_.Source }
        $hasScoop  = $sources | Where-Object { $_ -like "$scoopRoot*" }
        $hasOther  = $sources | Where-Object { $_ -notlike "$scoopRoot*" }
        if ($hasScoop -and $hasOther) {
            $overlap += [pscustomobject]@{ Tool=$t; Active=$cmds[0].Source; Sources=$sources }
        }
    }
    if (-not $overlap) { Write-Host 'scoop/winget 重複なし。'; return }
    Write-Host '重複検出 (PATH 先頭 = Active):' -ForegroundColor Yellow
    $overlap | ForEach-Object {
        Write-Host ("  {0}" -f $_.Tool) -ForegroundColor Cyan
        Write-Host ("    -> {0}  (active)" -f $_.Active)
        $_.Sources | Where-Object { $_ -ne $_.Active } | ForEach-Object { Write-Host ("       {0}" -f $_) }
    }
    Write-Host '対処: winget を残す方針なら `scoop uninstall <tool>`。逆も可。'
}

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
