# baseline.psd1 の宣言と実機の状態を照合する (読み取りのみ。追加機能の照合だけは管理者が要る)。
# apply.ps1 の後や Windows Update の後に回して、戻された設定が無いかを見る。
# 不一致が 1 つでもあれば exit 1。
#
#   just win-privacy-verify
#   powershell -NoProfile -File windows/privacy/verify.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PrivacyDir = $PSScriptRoot
if (-not $PrivacyDir) {
    $PrivacyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$Baseline = Import-PowerShellDataFile (Join-Path $PrivacyDir 'baseline.psd1')

$script:Bad = 0
function Ok($msg)   { Write-Host "OK    $msg" -ForegroundColor Green }
function Skip($msg) { Write-Host "SKIP  $msg" -ForegroundColor DarkGray }
function Bad($msg)  { Write-Host "DRIFT $msg" -ForegroundColor Red; $script:Bad++ }

$os = Get-CimInstance Win32_OperatingSystem
$edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
Write-Host "$($os.Caption) ($edition) build $($os.BuildNumber)"
if ($edition -notmatch 'Enterprise|Education|ServerRdsh') {
    Write-Host '  この edition では AllowTelemetry=0 は「必須 (1)」として扱われる。送信停止は DiagTrack 無効化が担う' -ForegroundColor DarkYellow
}

foreach ($r in $Baseline.Registry) {
    $key = "$($r.Path)\$($r.Name)"
    $item = Get-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        Bad "$key が無い (期待 $($r.Value))"
    } elseif ($item.($r.Name) -ne $r.Value) {
        Bad "$key = $($item.($r.Name)) (期待 $($r.Value))"
    } else {
        Ok "$key = $($r.Value)"
    }
}

foreach ($s in $Baseline.Services) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) {
        Skip "service $s (存在しない)"
    } elseif ($svc.StartType -ne 'Disabled' -or $svc.Status -ne 'Stopped') {
        Bad "service $s : $($svc.Status) / $($svc.StartType) (期待 Stopped / Disabled)"
    } else {
        Ok "service $s : Stopped / Disabled"
    }
}

foreach ($t in $Baseline.Tasks) {
    $taskPath = $t.Substring(0, $t.LastIndexOf('\') + 1)
    $taskName = $t.Substring($t.LastIndexOf('\') + 1)
    $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Skip "task $t (この build に無い)"
    } elseif ($task.State -ne 'Disabled') {
        Bad "task $t : $($task.State) (期待 Disabled)"
    } else {
        Ok "task $t : Disabled"
    }
}

# Get-WindowsCapability は管理者が要る。非管理者なら追加機能だけ照合を飛ばす
$isAdmin = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Baseline.Capabilities -and -not $isAdmin) {
    Skip "追加機能 $($Baseline.Capabilities.Count) 件 (照合には管理者 PowerShell が要る)"
} elseif ($Baseline.Capabilities) {
    $installed = @(Get-WindowsCapability -Online | Where-Object State -eq 'Installed')
    foreach ($c in $Baseline.Capabilities) {
        # apply.ps1 の Test-CapabilityName と同じ照合
        $caps = @($installed | Where-Object { $h = ($_.Name -split '~')[0]; ($h -eq $c) -or ($h -like "$c.*") })
        if ($caps) {
            Bad "capability $c : Installed (期待 削除)"
        } else {
            Ok "capability $c : 未 install"
        }
    }
}

Write-Host ''
if ($script:Bad -gt 0) {
    Write-Host "DRIFT $($script:Bad) 件。just win-privacy -SkipWin11Debloat -SkipCustomApps -SkipWinUtil で baseline だけ再適用できる" -ForegroundColor Red
    exit 1
}
Write-Host 'baseline と一致' -ForegroundColor Green
