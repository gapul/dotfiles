# Windows プライバシー / 標準機能を declarative に適用する orchestrator。
# - Win11Debloat: win11debloat-args.txt の引数で自動実行 (CLI 完結)
# - WinUtil:      winutil-config.json を引数で渡して GUI 起動 (ユーザーが Apply)
#
# 管理者 PowerShell で実行推奨 (両ツールともレジストリ HKLM / Set-Service / 等)。
# -DryRun で副作用なしの計画表示。
#
# 関連: windows/privacy/README.md
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipWinUtil,       # WinUtil GUI 起動を skip
    [switch]$SkipWin11Debloat   # Win11Debloat 実行を skip
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
        $debloatArgs = Get-Content $argsFile -Encoding UTF8 |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
        Log "Win11Debloat 引数 ($($debloatArgs.Count) 個): $($debloatArgs -join ' ')"
        if ($DryRun) {
            Dry "irm https://win11debloat.raphi.re/ | iex (引数 -> $($debloatArgs -join ' '))"
        } else {
            $tmpDebloat = Join-Path $env:TEMP "Win11Debloat-$(Get-Random).ps1"
            try {
                Log "Win11Debloat を取得 → $tmpDebloat"
                Invoke-WebRequest -Uri 'https://win11debloat.raphi.re/' -OutFile $tmpDebloat -UseBasicParsing
                Log "Win11Debloat 実行..."
                & $tmpDebloat @debloatArgs
                Log "Win11Debloat 完了"
            } finally {
                Remove-Item $tmpDebloat -ErrorAction SilentlyContinue
            }
        }
    }
} else {
    Log 'SkipWin11Debloat: Win11Debloat を skip'
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
            $tmpWinUtil = Join-Path $env:TEMP "winutil-$(Get-Random).ps1"
            try {
                Log "WinUtil を取得 → $tmpWinUtil"
                Invoke-WebRequest -Uri 'https://christitus.com/win' -OutFile $tmpWinUtil -UseBasicParsing
                Log "WinUtil GUI 起動 (Settings → Import Config で $configFile を選択 → Apply)"
                # WinUtil は -Config 引数で起動時 import に対応。version 差で動かない時は
                # GUI で手動 Import → Apply してください。
                & $tmpWinUtil -Config $configFile
                Log "WinUtil 終了"
            } finally {
                Remove-Item $tmpWinUtil -ErrorAction SilentlyContinue
            }
        }
    }
} else {
    Log 'SkipWinUtil: WinUtil を skip'
}

Log ''
Log '完了。設定の変更を反映するには再ログイン or 再起動が必要なものがあります。'
