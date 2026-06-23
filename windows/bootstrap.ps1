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

# 4. Windows Terminal settings.json を symlink
$WTSrc = Join-Path $WindowsDir 'terminal\settings.json'
$WTDst = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if ((Test-Path $WTSrc) -and (Test-Path (Split-Path $WTDst -Parent))) {
    if (Test-Path $WTDst) {
        $existing = Get-Item $WTDst
        if ($existing.LinkType -ne 'SymbolicLink' -or $existing.Target -ne $WTSrc) {
            $backup = "$WTDst.bak-$(Get-Date -Format yyyyMMddHHmmss)"
            Move-Item $WTDst $backup
            Log "既存 WT settings → $backup に退避"
        }
    }
    if (-not (Test-Path $WTDst)) {
        New-Item -ItemType SymbolicLink -Path $WTDst -Target $WTSrc | Out-Null
        Log "WT settings.json → $WTSrc"
    }
}

# 5. age / SSH 鍵 (任意、未配置なら警告のみ)
$AgeKey = Join-Path $env:USERPROFILE '.config\sops\age\keys.txt'
if (-not (Test-Path $AgeKey)) {
    Err "age 秘密鍵 ($AgeKey) が未配置 — Bitwarden 等から手動で配置してください"
}
$SshPriv = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
if (-not (Test-Path $SshPriv)) {
    Err "SSH 秘密鍵 ($SshPriv) が未配置 — Bitwarden 等から配置 + chmod 600"
}

# 6. git global config (gh/git は winget で別途 install されてる前提)
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global user.name 'gapul'
    git config --global user.email '92638132+gapul@users.noreply.github.com'
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
