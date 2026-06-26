# PowerShell 7+ プロファイル (dotfiles 管理)
# 配置先: $PROFILE → ~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1
# bootstrap.ps1 で symlink される
#
# 具体的なツール (oh-my-posh / Terminal Icons / PSReadLine 等) は
# Windows 環境で実装するときに追記する。
# 当面は最低限のエイリアスと PSReadLine 推奨設定のみ。

# === PSReadLine: 履歴検索を強化 ===
# 5.1 同梱は PSReadLine 2.0 で -PredictionSource を持たないため能力検出。
# pwsh 7 ($PROFILE) と 5.1 (Documents\WindowsPowerShell\$PROFILE) の両方から
# 同じファイルが symlink で読まれるので、片方でエラーが出ないようにする。
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    if ((Get-Command Set-PSReadLineOption).Parameters.ContainsKey('PredictionSource')) {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    }
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

# 任意 dir / 任意 distro で WSL に入る (`Open-Wsl C:\src -Distro Ubuntu-24.04`)
function Open-Wsl {
    [CmdletBinding()]
    param(
        [string]$Directory = (Get-Location).Path,
        [string]$Distro
    )
    $wargs = @('--cd', $Directory)
    if ($Distro) { $wargs = @('-d', $Distro) + $wargs }
    wsl @wargs
}

# Windows path → WSL path (パイプ可: `Get-Location | ConvertTo-WslPath`)
function ConvertTo-WslPath {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$Path)
    process { (wsl wslpath -u "$Path").Trim() }
}

# WSL path → Windows path
function ConvertFrom-WslPath {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$Path)
    process { (wsl wslpath -w "$Path").Trim() }
}

# === ghq root (nvim lazy.lua の dev.path と整合) ===
# macOS の nix/home/common.nix で `programs.git.extraConfig.ghq.root` を ~/Developer
# に固定している。Windows ネイティブでも同じレイアウトにして lazy.lua の
# ~/Developer/github.com/gapul/* がローカル参照で動くようにする。
$env:GHQ_ROOT = Join-Path $env:USERPROFILE 'Developer'

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

# === SOPS (age 復号) ===
# 秘密鍵パスを env で固定。sops は SOPS_AGE_KEY_FILE があれば --age オプション不要。
$env:SOPS_AGE_KEY_FILE = Join-Path $env:USERPROFILE '.config\sops\age\keys.txt'

# `Get-DotfilesSecret 'github.token'` で secrets.yaml から該当値を復号取得。
# - dotfiles 配下の secrets/secrets.yaml をデフォルト参照、-File で上書き可
# - sops / 秘密鍵 / ファイル不在は明示的にエラー (UI で何が足りないか分かるように)
# - 復号結果は単純に文字列で返す (Set-Clipboard などへパイプ前提)
function Get-DotfilesSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [string]$File = (Join-Path $env:USERPROFILE 'dotfiles\secrets\secrets.yaml')
    )
    if (-not (Get-Command sops -ErrorAction SilentlyContinue)) {
        throw 'sops が PATH に無い。winget install --id SecretsOPerationS.SOPS で導入'
    }
    if (-not (Test-Path $env:SOPS_AGE_KEY_FILE)) {
        throw "age 秘密鍵が無い: $env:SOPS_AGE_KEY_FILE (Bitwarden 等から配置)"
    }
    if (-not (Test-Path $File)) {
        throw "secrets ファイルが無い: $File"
    }
    # YAML キー指定は ['a']['b'] 形式。ドット区切りで分解して構築する。
    $extract = ($Key -split '\.') | ForEach-Object { "['$_']" }
    sops --decrypt --extract ($extract -join '') $File
}

# Windows ssh-agent サービスに鍵を登録 (passphrase 入力あり)。
# WSL は npiperelay 経由でこの agent を共有 (wsl.nix)。鍵を登録すれば WSL 側 ssh
# でも自動認証が効く (P2-11)。
function Add-SshKey {
    [CmdletBinding()]
    param([string]$KeyPath = (Join-Path $env:USERPROFILE '.ssh\id_ed25519'))
    if (-not (Test-Path $KeyPath))                              { throw "鍵不在: $KeyPath" }
    if (-not (Get-Command ssh-add -ErrorAction SilentlyContinue)) { throw 'ssh-add 不在 (OpenSSH Client が無効)' }
    if ((Get-Service ssh-agent -ErrorAction SilentlyContinue).Status -ne 'Running') {
        throw 'ssh-agent サービスが停止中 — 管理者で Start-Service ssh-agent'
    }
    ssh-add $KeyPath
}

# クリップボードに直接 (`Copy-DotfilesSecret github.token` 風)。
function Copy-DotfilesSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Key, [string]$File)
    $splat = @{ Key = $Key }
    if ($File) { $splat['File'] = $File }
    (Get-DotfilesSecret @splat) | Set-Clipboard
    Write-Host "secret '$Key' をクリップボードへコピーしました。" -ForegroundColor Green
}
