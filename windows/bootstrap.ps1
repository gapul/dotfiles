# Windows native 0→1 セットアップ (PowerShell 7+ 想定)
# 想定: Windows 11 fresh install + WSL2 未導入 (or 別途)
#
# 流れ:
#   1. winget 確認
#   2. winget/apps.json から一括 install (空ファイルなら skip)
#   3. PowerShell $PROFILE を dotfiles 内ファイルへ symlink
#   4. Windows Terminal settings.json を symlink
#   5. (任意) age / SSH 鍵 paste 待ち
#   6. git の global config
#
# 何度走らせても安全 (idempotent)。
# 管理者 PowerShell で実行推奨 (symlink 作成に SeCreateSymbolicLinkPrivilege が必要)
#
# WSL の distro/ユーザー名は -WslDistro / -WslUser で上書き可:
#   & bootstrap.ps1 -WslUser alice -WslDistro Debian
param(
    [string]$WslUser   = $env:USERNAME,  # WSL 側ユーザー名 (Terminal の startingDirectory に注入)。WSL のユーザー名が違えば -WslUser で上書き
    [string]$WslDistro = 'Ubuntu',    # WSL ディストリ名
    # git author (macOS/WSL は nix/user.nix が正。Windows は nix eval 不可のため引数で渡す)
    [string]$GitUser   = 'gapul',
    [string]$GitEmail  = '92638132+gapul@users.noreply.github.com'
)

$ErrorActionPreference = 'Stop'
$DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
$WindowsDir = Join-Path $DotfilesDir 'windows'

function Log($msg) { Write-Host "[bootstrap-win] $msg" -ForegroundColor Blue }
function Err($msg) { Write-Host "[bootstrap-win] $msg" -ForegroundColor Red }

# 1. winget 確認
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err 'winget が見つかりません。Microsoft Store で "App Installer" を install してください。'
    Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1'
    exit 1
}
Log 'winget OK'

# 1.5 PowerShell 7 (pwsh) を先に確保。
# Windows 同梱は 5.1 (PSReadLine 2.0 系)。本 dotfiles の profile は
# `Set-PSReadLineOption -PredictionSource HistoryAndPlugin` (PSReadLine 2.2+) を使うため
# 5.1 では parameter validation で失敗する。後段の winget import より先に必ず入れる。
# なお既に pwsh が在れば再 install しない (winget 自身が冪等)。
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Log 'PowerShell 7 (pwsh) が未導入 -> winget で install...'
    winget install --id Microsoft.PowerShell --exact `
        --accept-package-agreements --accept-source-agreements `
        --silent --disable-interactivity
    # 当プロセスの PATH はインストーラが更新しないので、以降のステップで pwsh を
    # 直接呼ぶ必要があるなら絶対パスを使うこと。新しい PowerShell を開き直せば PATH に乗る。
    Log 'PowerShell 7 install 完了。今後は pwsh.exe で本スクリプトを再実行推奨。'
} else {
    Log "pwsh OK ($($PSVersionTable.PSVersion))"
}

# 2. winget/apps.json import
$AppsJson = Join-Path $WindowsDir 'winget\apps.json'
if (Test-Path $AppsJson) {
    $content = Get-Content $AppsJson -Raw
    if ($content -match '"PackageIdentifier"') {
        Log "Installing apps from $AppsJson ..."
        winget import --import-file $AppsJson --accept-package-agreements --accept-source-agreements
    } else {
        Log 'apps.json は空 (winget import スキップ)'
    }
} else {
    Log "$AppsJson が無いので winget import スキップ"
}

# 3. PowerShell $PROFILE を symlink
$ProfileSrc = Join-Path $WindowsDir 'profile\Microsoft.PowerShell_profile.ps1'
if (Test-Path $ProfileSrc) {
    $ProfileDir = Split-Path $PROFILE -Parent
    if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Path $ProfileDir | Out-Null }
    if (Test-Path $PROFILE) {
        $existing = Get-Item $PROFILE
        if ($existing.LinkType -ne 'SymbolicLink' -or $existing.Target -ne $ProfileSrc) {
            $backup = "$PROFILE.bak-$(Get-Date -Format yyyyMMddHHmmss)"
            Move-Item $PROFILE $backup
            Log "既存 $PROFILE → $backup に退避"
        }
    }
    if (-not (Test-Path $PROFILE)) {
        New-Item -ItemType SymbolicLink -Path $PROFILE -Target $ProfileSrc | Out-Null
        Log "$PROFILE → $ProfileSrc"
    }
}

# 4. Windows Terminal settings.json を生成 (symlink でなく render)
#    startingDirectory の __WSL_USER__ / __WSL_DISTRO__ を実値へ置換するため、
#    symlink でなく「コピー + 置換」で配置する。settings を編集したら再実行で反映。
$WTSrc = Join-Path $WindowsDir 'terminal\settings.json'
$WTDst = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if ((Test-Path $WTSrc) -and (Test-Path (Split-Path $WTDst -Parent))) {
    $rendered = (Get-Content $WTSrc -Raw) `
        -replace '__WSL_USER__',   $WslUser `
        -replace '__WSL_DISTRO__', $WslDistro
    # 既存が手書き設定 (symlink でない & placeholder 由来でない) なら backup 退避
    if ((Test-Path $WTDst) -and ((Get-Content $WTDst -Raw) -ne $rendered)) {
        $backup = "$WTDst.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        Copy-Item $WTDst $backup
        Log "既存 WT settings → $backup に退避"
    }
    Set-Content -Path $WTDst -Value $rendered -Encoding UTF8 -NoNewline
    Log "WT settings.json を生成 (WslUser=$WslUser / WslDistro=$WslDistro)"
}

# 5. age / SSH 鍵 (任意)。存在すれば ACL を本人のみに絞る。
#    Windows には chmod が無く、OpenSSH は「他ユーザーが読める秘密鍵」を拒否するため
#    icacls で継承を切り、現在のユーザーだけにアクセス許可を付け直す。
function Protect-KeyFile($path) {
    if (-not (Test-Path $path)) { return }
    icacls $path /inheritance:r              | Out-Null  # 継承された ACL を全削除
    icacls $path /grant:r "${env:USERNAME}:F" | Out-Null  # 本人のみフルコントロール
    # 既定で付く緩いグループを念のため除去 (無くてもエラーにしない)
    foreach ($p in @('BUILTIN\Users', 'BUILTIN\Administrators', 'NT AUTHORITY\Authenticated Users')) {
        icacls $path /remove:g "$p" 2>$null | Out-Null
    }
    Log "鍵 ACL を本人のみに制限: $path"
}

$AgeKey = Join-Path $env:USERPROFILE '.config\sops\age\keys.txt'
if (Test-Path $AgeKey) { Protect-KeyFile $AgeKey }
else { Err "age 秘密鍵 ($AgeKey) が未配置 — Bitwarden 等から手動で配置してください" }

$SshPriv = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
if (Test-Path $SshPriv) { Protect-KeyFile $SshPriv }
else { Err "SSH 秘密鍵 ($SshPriv) が未配置 — Bitwarden 等から配置後に本スクリプト再実行で ACL 設定" }

# 6. git global config (gh/git は winget で別途 install されてる前提)
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global user.name $GitUser
    git config --global user.email $GitEmail
    git config --global init.defaultBranch main
    git config --global pull.rebase true
    git config --global push.autoSetupRemote true
    Log 'git global config 設定済'
}

Log ''
Log '完了! 新しい PowerShell を開いてください。'
Log ''
Log '追加で手動でやること:'
Log '  - WSL2 を入れる場合: wsl --install -d Ubuntu (管理者で別 PowerShell)'
Log '  - winget/apps.json に install したい app を追記して再実行'
