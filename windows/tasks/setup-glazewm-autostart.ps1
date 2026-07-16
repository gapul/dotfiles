# GlazeWM のログイン時自動起動を Task Scheduler に登録する (1 回実行)。
#
# 背景:
# - glazewm.exe (main) は manifest で requireAdministrator 指定のため、
#   Startup folder の .lnk からは UAC ブロックで起動失敗する。
# - GlazeWM v3.10 で CLI 仕様変更 (`start` サブコマンド必須化) + manifest 変更が同時に
#   入ったため、これより前の version では Startup .lnk のみで動いていたが現状不可。
# - Task Scheduler の LogonType S4U (Service for User) を使うと、password なしで
#   UAC token filtering を回避して Highest RunLevel の token を取得できる。
#   制約: ネットワーク資源アクセス不可だが GlazeWM はローカル GUI app なので問題ない。
#
# 使い方:
#   just win-autostart-glazewm                  # 登録
#   just win-autostart-glazewm -Unregister      # 削除
[CmdletBinding()]
param(
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'
$TaskName = 'dotfiles-glazewm'
$ExePath  = 'C:\Program Files\glzr.io\GlazeWM\glazewm.exe'

function Log($m) { Write-Host "[autostart-glazewm] $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host "[autostart-glazewm] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[autostart-glazewm] $m" -ForegroundColor Yellow }

# 管理者チェック (Task Scheduler 登録に必要) → 非 admin なら UAC で elevate
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Warn '管理者権限が必要です。UAC promptで再起動します...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Unregister) { $argList += '-Unregister' }
    Start-Process pwsh -Verb RunAs -ArgumentList $argList -Wait
    exit
}

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Ok "$TaskName を削除"
    } else {
        Warn "$TaskName は存在しない (skip)"
    }
    exit
}

if (-not (Test-Path $ExePath)) {
    throw "GlazeWM 未 install: $ExePath ( winget install glzr-io.glazewm で導入 )"
}

# 旧 Startup folder の .lnk があれば削除 (Task Scheduler に統一)
$oldLnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\GlazeWM.lnk'
if (Test-Path $oldLnk) {
    Remove-Item $oldLnk -Force
    Log "旧 Startup .lnk を削除 (Task Scheduler に統一)"
}

# 既存タスク削除 (re-register)
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Log "既存の $TaskName を削除 (re-register)"
}

# LogonType S4U: Service for User. Password 不要で UAC token filtering の影響を受けず
# Highest RunLevel が効く。制約はネットワーク資源アクセス不可だが GlazeWM はローカル
# GUI app なので問題ない。
# (Password モードでは Win10/11 のローカルアカウント UAC filter で Highest が無効化される
#  ケースがあり、ERROR_ELEVATION_REQUIRED 0x800702E4 になる。S4U はこの問題を回避する。)
$fullUser = "$env:USERDOMAIN\$env:USERNAME"
$action  = New-ScheduledTaskAction -Execute $ExePath -Argument 'start'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $fullUser
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -DisallowHardTerminate `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal `
    -UserId $fullUser -RunLevel Highest -LogonType S4U
Register-ScheduledTask -TaskName $TaskName `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Ok "Task '$TaskName' 登録 (AtLogOn / Highest / Password)"

Write-Host ''
Log '動作確認のため今すぐ起動します...'
Start-ScheduledTask -TaskName $TaskName
Start-Sleep 3
$info = Get-ScheduledTaskInfo -TaskName $TaskName
$resultHex = '0x{0:X}' -f $info.LastTaskResult
$proc = Get-Process glazewm -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
    Ok "glazewm 起動成功 (PID $($proc.Id)) — LastResult=$resultHex"
} else {
    Warn "glazewm プロセス未検出 — LastResult=$resultHex"
    Warn '0x0 (= 成功) なら起動直後にクラッシュ。0x800704DC (1244) なら password 間違い。'
}
