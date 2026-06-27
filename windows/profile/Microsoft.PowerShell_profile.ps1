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

# === 健全性チェック (macOS の `just doctor` 相当) ===
# 起動後 `Test-DotfilesSetup` を呼ぶと、symlink / 環境変数 / 主要ツール / 鍵 /
# ssh-agent を一気に診断。bootstrap 後の検証や、別マシン移植時に使う。
function Test-DotfilesSetup {
    [CmdletBinding()]
    param()
    $dotfiles = Join-Path $env:USERPROFILE 'dotfiles'
    $pass = 0; $fail = 0
    function _row($label, [bool]$ok, $extra = '') {
        $tag = if ($ok) { '[ok]  ' } else { '[FAIL]' }
        $color = if ($ok) { 'Green' } else { 'Red' }
        $line = if ($extra) { "$tag $label   ($extra)" } else { "$tag $label" }
        Write-Host $line -ForegroundColor $color
        if ($ok) { Set-Variable -Name pass -Value (++$script:pass) -Scope 1 -ErrorAction SilentlyContinue }
    }

    Write-Host '== configs symlink ==' -ForegroundColor Cyan
    $links = @(
        @{ Label = 'gh';      Path = "$env:APPDATA\GitHub CLI";              Target = "$dotfiles\configs\cli\gh" }
        @{ Label = 'bat';     Path = "$env:APPDATA\bat";                     Target = "$dotfiles\configs\cli\bat" }
        @{ Label = 'yazi';    Path = "$env:APPDATA\yazi\config";             Target = "$dotfiles\configs\cli\yazi" }
        @{ Label = 'nvim';    Path = "$env:LOCALAPPDATA\nvim";               Target = "$dotfiles\configs\editors\nvim" }
        @{ Label = 'zed';     Path = "$env:APPDATA\Zed";                     Target = "$dotfiles\configs\editors\zed" }
        @{ Label = 'espanso'; Path = "$env:APPDATA\espanso\match\base.yml";  Target = "$dotfiles\configs\espanso\base.yml" }
        @{ Label = 'wezterm'; Path = "$env:USERPROFILE\.wezterm.lua";        Target = "$dotfiles\configs\terminals\wezterm\wezterm.lua" }
    )
    foreach ($l in $links) {
        $item = Get-Item -LiteralPath $l.Path -Force -ErrorAction SilentlyContinue
        $ok = $item -and $item.LinkType -eq 'SymbolicLink' -and $item.Target -eq $l.Target
        if ($ok) { Write-Host "  [ok]   $($l.Label)" -ForegroundColor Green; $pass++ }
        else     { Write-Host "  [FAIL] $($l.Label) — bootstrap 未実行 or 別 target" -ForegroundColor Red; $fail++ }
    }

    Write-Host '== 環境変数 ==' -ForegroundColor Cyan
    foreach ($v in 'STARSHIP_CONFIG','SOPS_AGE_KEY_FILE','GHQ_ROOT') {
        $val = [Environment]::GetEnvironmentVariable($v, 'Process')
        if ($val) { Write-Host "  [ok]   $v = $val" -ForegroundColor Green; $pass++ }
        else      { Write-Host "  [FAIL] $v 未設定 (profile が読まれてない?)" -ForegroundColor Red; $fail++ }
    }

    Write-Host '== 主要ツール ==' -ForegroundColor Cyan
    foreach ($t in 'pwsh','git','gh','nvim','yazi','starship','zoxide','sops','age','ssh-add') {
        if (Get-Command $t -ErrorAction SilentlyContinue) { Write-Host "  [ok]   $t" -ForegroundColor Green; $pass++ }
        else                                              { Write-Host "  [warn] $t 未導入 (winget import で入る)" -ForegroundColor Yellow }
    }

    Write-Host '== 鍵 ==' -ForegroundColor Cyan
    foreach ($k in @(
        @{ Label = 'age'; Path = (Join-Path $env:USERPROFILE '.config\sops\age\keys.txt') },
        @{ Label = 'ssh'; Path = (Join-Path $env:USERPROFILE '.ssh\id_ed25519') }
    )) {
        if (Test-Path $k.Path) {
            # icacls 制限済 = 自分以外の許可エントリが無い (簡易判定)
            $acl = (icacls $k.Path 2>$null) -join ' '
            $restricted = $acl -notmatch 'BUILTIN\\Users' -and $acl -notmatch 'Authenticated Users'
            if ($restricted) { Write-Host "  [ok]   $($k.Label): $($k.Path) (ACL 本人のみ)" -ForegroundColor Green; $pass++ }
            else             { Write-Host "  [warn] $($k.Label): ACL 制限が緩い — pwsh -File bootstrap.ps1 で再制限" -ForegroundColor Yellow }
        } else {
            Write-Host "  [warn] $($k.Label) 未配置 ($($k.Path))" -ForegroundColor Yellow
        }
    }

    Write-Host '== ssh-agent サービス ==' -ForegroundColor Cyan
    $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($svc) {
        # 2 つの正常パターン:
        #   (a) Bitwarden Desktop に委譲: Stopped + Disabled
        #   (b) Windows 標準を使う: Running + Automatic
        $bitwarden = $svc.Status -eq 'Stopped' -and $svc.StartType -eq 'Disabled'
        $standard  = $svc.Status -eq 'Running' -and $svc.StartType -eq 'Automatic'
        if ($bitwarden) { Write-Host "  [ok]   ssh-agent: Stopped/Disabled (Bitwarden Desktop に委譲)" -ForegroundColor Green; $pass++ }
        elseif ($standard) { Write-Host "  [ok]   ssh-agent: Running/Automatic" -ForegroundColor Green; $pass++ }
        else { Write-Host "  [FAIL] ssh-agent: $($svc.Status) / $($svc.StartType) — 中間状態" -ForegroundColor Red; $fail++ }
    } else {
        Write-Host "  [warn] OpenSSH Authentication Agent 未導入" -ForegroundColor Yellow
    }

    Write-Host '== Bitwarden SSH Agent パイプ ==' -ForegroundColor Cyan
    # Bitwarden Desktop が SSH Agent を listen している前提のときだけ評価。
    # app.log の存在を見て判定 (ssh-agent サービスが Disabled = Bitwarden 期待されている)
    if ($svc -and $svc.StartType -eq 'Disabled') {
        $bdLog = Join-Path $env:APPDATA 'Bitwarden\app.log'
        if (Test-Path $bdLog) {
            $recent = Get-Content $bdLog -Tail 200 -ErrorAction SilentlyContinue
            $started = $recent | Where-Object { $_ -match 'SSH agent started|Creating named pipe server on .*openssh-ssh-agent' } | Select-Object -Last 1
            if ($started) { Write-Host "  [ok]   Bitwarden SSH Agent listen 中" -ForegroundColor Green; $pass++ }
            else { Write-Host "  [warn] Bitwarden app.log に SSH agent 起動 log が無い — Settings → SSH Agent を ON + 再起動" -ForegroundColor Yellow }
        } else {
            Write-Host "  [warn] Bitwarden Desktop が未起動 or app.log なし" -ForegroundColor Yellow
        }
    }

    Write-Host '== AHK keymap (Startup symlink + プロセス) ==' -ForegroundColor Cyan
    $ahkLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\dotfiles-keymap.ahk'
    $ahkTarget = "$dotfiles\windows\autohotkey\keymap.ahk"
    $item = Get-Item -LiteralPath $ahkLink -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'SymbolicLink' -and $item.Target -eq $ahkTarget) {
        Write-Host "  [ok]   Startup symlink" -ForegroundColor Green; $pass++
    } else { Write-Host "  [warn] Startup symlink 未設定 — bootstrap.ps1 を管理者で実行" -ForegroundColor Yellow }
    if (Get-Process AutoHotkey* -ErrorAction SilentlyContinue) {
        Write-Host "  [ok]   AutoHotkey プロセス稼働中" -ForegroundColor Green; $pass++
    } else { Write-Host "  [warn] AutoHotkey プロセス未起動 — just win-keymap で起動" -ForegroundColor Yellow }

    Write-Host '== SharpKeys (Scancode Map) ==' -ForegroundColor Cyan
    $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'Scancode Map' -ErrorAction SilentlyContinue
    if ($sm) { Write-Host "  [ok]   Scancode Map 書込済 ($($sm.'Scancode Map'.Length) bytes、再起動で反映)" -ForegroundColor Green; $pass++ }
    else { Write-Host "  [warn] Scancode Map 未設定 — just win-keymap" -ForegroundColor Yellow }

    Write-Host '== Bitdefender (Defender 代替 AV) ==' -ForegroundColor Cyan
    $bdsvc = Get-Service BDAppSrv -ErrorAction SilentlyContinue
    if ($bdsvc -and $bdsvc.Status -eq 'Running') {
        Write-Host "  [ok]   Bitdefender 稼働中 (Defender は自動待機モード)" -ForegroundColor Green; $pass++
    } else { Write-Host "  [warn] Bitdefender 未稼働 — winget install Bitdefender.Bitdefender" -ForegroundColor Yellow }

    Write-Host ''
    Write-Host "Result: $pass passed, $fail failed" -ForegroundColor ($(if ($fail -eq 0) { 'Green' } else { 'Yellow' }))
}

# === ghq root (nvim lazy.lua の dev.path と整合) ===
# macOS の nix/home/common.nix で `programs.git.extraConfig.ghq.root` を ~/Developer
# に固定している。Windows ネイティブでも同じレイアウトにして lazy.lua の
# ~/Developer/github.com/gapul/* がローカル参照で動くようにする。
$env:GHQ_ROOT = Join-Path $env:USERPROFILE 'Developer'

# === starship 設定パス (winget で入れる想定) ===
# macOS/WSL と同じ prompt にするため共有 configs/shell/starship.toml を参照。
# starship 未導入でも env だけは先に設定 (Test-DotfilesSetup の判定容易化)。
$sharedStarship = Join-Path $env:USERPROFILE 'dotfiles\configs\shell\starship.toml'
if (Test-Path $sharedStarship) { $env:STARSHIP_CONFIG = $sharedStarship }
if (Get-Command starship -ErrorAction SilentlyContinue) {
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
