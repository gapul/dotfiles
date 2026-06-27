# Windows プライバシー / 標準機能を declarative に適用する orchestrator。
# - Win11Debloat:   win11debloat-args.txt の引数で自動実行 (CLI 完結)
# - CustomApps:     win11debloat-customapps.txt 列挙の UWP を Remove-AppxPackage 直接実行
# - ExtraRegistry:  Windows Backup UI など、宣言的な追加レジストリ tweak
# - WinUtil:        winutil-config.json を引数で渡して GUI 起動 (ユーザーが Apply)
#
# 管理者 PowerShell で実行推奨 (UWP 削除 / レジストリ HKLM / Set-Service / 等)。
# -DryRun で副作用なしの計画表示。
#
# 関連: windows/privacy/README.md
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipWinUtil,        # WinUtil GUI 起動を skip
    [switch]$SkipWin11Debloat,   # Win11Debloat 実行 + ExtraRegistry を skip
    [switch]$SkipCustomApps      # カスタム UWP 削除 (customapps.txt) を skip
)

$ErrorActionPreference = 'Stop'
$PrivacyDir = $PSScriptRoot
if (-not $PrivacyDir) {
    $PrivacyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Log($msg) { Write-Host "[privacy] $msg"      -ForegroundColor Blue }
function Dry($msg) { Write-Host "[privacy][dry] $msg" -ForegroundColor DarkYellow }
function Err($msg) { Write-Host "[privacy] $msg"      -ForegroundColor Red }

# ─── 1. Win11Debloat ───
if (-not $SkipWin11Debloat) {
    $argsFile = Join-Path $PrivacyDir 'win11debloat-args.txt'
    if (-not (Test-Path $argsFile)) {
        Err "win11debloat-args.txt が無い: $argsFile"
    } else {
        # 空行と `#` コメントを除外 (5.1 の Get-Content default は ANSI のため -Encoding UTF8 明示)
        # BOM 由来の空要素や CR 残りを完全除外するため $_ -notmatch '^\s*$' でガード
        $debloatArgs = Get-Content $argsFile -Encoding UTF8 |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') -and $_ -notmatch '^\s*$' }
        Log "Win11Debloat 引数 ($($debloatArgs.Count) 個): $($debloatArgs -join ' ')"
        if ($DryRun) {
            Dry "irm https://win11debloat.raphi.re/ | iex (引数 -> $($debloatArgs -join ' '))"
        } else {
            # 公式推奨パターン: Web から取得 → [scriptblock]::Create() で実行。
            # `Invoke-WebRequest -OutFile` + `& $file @args` は Win11Debloat のスクリプト内部
            # 引数解析で「Missing expression after unary operator '--'」になる事例があるため避ける。
            Log "Win11Debloat 実行 (script block)..."
            $debloatContent = (Invoke-WebRequest -Uri 'https://win11debloat.raphi.re/' -UseBasicParsing).Content
            $debloatBlock = [scriptblock]::Create($debloatContent)
            & $debloatBlock @debloatArgs
            Log "Win11Debloat 完了"
        }
    }
} else {
    Log 'SkipWin11Debloat: Win11Debloat を skip'
}

# ─── 1.5 カスタム UWP 削除 (Win11Debloat 標準セット外、安全側追加) ───
if (-not $SkipCustomApps) {
    $customAppsFile = Join-Path $PrivacyDir 'win11debloat-customapps.txt'
    if (-not (Test-Path $customAppsFile)) {
        Log 'win11debloat-customapps.txt が無いので skip'
    } else {
        $customApps = Get-Content $customAppsFile -Encoding UTF8 |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
        Log "カスタム UWP 削除対象 ($($customApps.Count) 個): $($customApps -join ', ')"
        foreach ($app in $customApps) {
            if ($DryRun) {
                Dry "Get-AppxPackage -Name '$app' | Remove-AppxPackage"
                Dry "Get-AppxProvisionedPackage -Online | Where DisplayName -eq '$app' | Remove-AppxProvisionedPackage"
                continue
            }
            # 現ユーザーから削除
            $pkg = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
            if ($pkg) {
                try {
                    $pkg | Remove-AppxPackage -ErrorAction Stop
                    Log "Removed (user): $app"
                } catch {
                    Err "Remove 失敗 (user): $app - $($_.Exception.Message)"
                }
            } else {
                Log "Skip (user): $app (未 install)"
            }
            # Provisioned (system プリイン) も削除 → 新規アカウントに戻らない (管理者要)
            try {
                $prov = Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                    Where-Object { $_.DisplayName -eq $app } |
                    Select-Object -First 1
                if ($prov) {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    Log "Removed (provisioned): $app"
                }
            } catch {
                # Get-AppxProvisionedPackage は管理者要。非管理者なら静かに skip
                if ($_.Exception.Message -match 'elevation') {
                    Log "Skip (provisioned): $app (管理者要)"
                } else {
                    Err "Provisioned 削除失敗: $app - $($_.Exception.Message)"
                }
            }
        }
    }
} else {
    Log 'SkipCustomApps: カスタム UWP 削除を skip'
}

# ─── 1.6 OneDrive uninstall (Win11Debloat の -DisableOnedrive は Win10 only のため代替) ───
if (-not $SkipWin11Debloat) {
    $oneDriveSetup = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($oneDriveSetup) {
        if ($DryRun) {
            Dry "Start-Process $oneDriveSetup /uninstall"
        } else {
            Log "OneDrive uninstall (Syncthing 代替前提) — $oneDriveSetup /uninstall"
            try {
                # 起動中の OneDrive を停止 → 公式 uninstaller 実行
                Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Process $oneDriveSetup -ArgumentList '/uninstall' -Wait
                Log 'OneDrive uninstall 完了'
            } catch {
                Err "OneDrive uninstall 失敗 (管理者要 / 既に削除済の可能性): $($_.Exception.Message)"
            }
        }
    } else {
        Log 'OneDrive: 既に削除済 or 未 install (skip)'
    }
}

# ─── 1.7 追加レジストリ tweak (Win11Debloat / WinUtil でカバーされない宣言的 OFF) ───
# Windows Backup (UWP 本体は CBS で削除不可、機能のみ無効化)
if (-not $SkipWin11Debloat) {
    $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsBackup'
    if ($DryRun) {
        Dry "Set $regPath\DisableWindowsBackupUI = 1 (Windows Backup UI を無効化)"
    } else {
        try {
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name 'DisableWindowsBackupUI' -Value 1 -Type DWord -Force
            Log "Windows Backup UI 無効化 (registry: $regPath)"
        } catch {
            Err "Windows Backup registry 設定失敗 (管理者要): $($_.Exception.Message)"
        }
    }
}

# ─── 2. WinUtil ───
if (-not $SkipWinUtil) {
    $configFile = Join-Path $PrivacyDir 'winutil-config.json'
    if (-not (Test-Path $configFile)) {
        Err "winutil-config.json が無い: $configFile"
    } else {
        # JSON 構文検証 (5.1 の Get-Content default は ANSI のため -Encoding UTF8 明示)
        try { Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
        catch {
            Err "winutil-config.json が不正 JSON: $($_.Exception.Message)"
            return
        }
        if ($DryRun) {
            Dry "irm https://christitus.com/win | iex -Args '-Config $configFile'"
            Dry "(GUI 起動 → Settings → Import Config で $configFile を選択 → Apply)"
        } else {
            # Win11Debloat と同じ公式パターン: Web → scriptblock。
            Log "WinUtil 実行 (script block, GUI 起動)..."
            $winutilContent = (Invoke-WebRequest -Uri 'https://christitus.com/win' -UseBasicParsing).Content
            $winutilBlock = [scriptblock]::Create($winutilContent)
            # WinUtil は -Config 引数で起動時 import に対応。version 差で動かない時は
            # GUI で手動 Import → Apply してください。
            & $winutilBlock -Config $configFile
            Log "WinUtil 終了"
        }
    }
} else {
    Log 'SkipWinUtil: WinUtil を skip'
}

Log ''
Log '完了。設定の変更を反映するには再ログイン or 再起動が必要なものがあります。'
