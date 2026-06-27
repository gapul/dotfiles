# Windows の最終 setup を一発で完了させる。
# - Locale 適用 (SKK のみ / UTF-8 / US Region) — 自動 UAC
# - Bootstrap 再実行 (zebar/glazewm/AHK symlink + font install) — 自動 UAC
# - 古い Ubuntu distro 削除 (Ubuntu-24.04 は残す)
# - 再起動の確認 prompt
#
# 使い方:
#   pwsh.exe -NoProfile -ExecutionPolicy Bypass -File scripts\win-finalize.ps1
#   再起動を促さない: -NoReboot
#   privacy も再適用: -ApplyPrivacy
[CmdletBinding()]
param(
    [switch]$NoReboot,
    [switch]$ApplyPrivacy
)

$ErrorActionPreference = 'Stop'
$DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
Set-Location $DotfilesDir

function Step($n, $msg) {
    Write-Host ''
    Write-Host "═══ Step $n. $msg ═══" -ForegroundColor Cyan
}

Step 1 'Locale 適用 (再起動で完全反映)'
& pwsh -NoProfile -ExecutionPolicy Bypass -File windows\locale\apply.ps1
if ($LASTEXITCODE -ne 0) { Write-Host '  → Locale 適用で警告あり (続行)' -ForegroundColor Yellow }

Step 2 'Bootstrap 再実行 (symlink + font install)'
$bootArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'windows\bootstrap.ps1')
if (-not $ApplyPrivacy) { $bootArgs += '-SkipPrivacy' }
& pwsh @bootArgs
if ($LASTEXITCODE -ne 0) { Write-Host '  → Bootstrap で警告あり (続行)' -ForegroundColor Yellow }

Step 3 '古い Ubuntu distro を削除 (Ubuntu-24.04 は残す)'
$distros = @(wsl -l -q 2>&1 | ForEach-Object { ($_ -replace '[^\x20-\x7E]', '').Trim() } |
            Where-Object { $_ })
$hasOld = $distros -contains 'Ubuntu'
$hasNew = $distros -contains 'Ubuntu-24.04'
Write-Host "  検出: $($distros -join ', ')"
if ($hasOld -and $hasNew) {
    wsl --unregister Ubuntu
    Write-Host '  ✓ Ubuntu (古い空 distro) を削除' -ForegroundColor Green
} elseif ($hasOld -and -not $hasNew) {
    Write-Host '  ⚠ Ubuntu-24.04 が無い。Ubuntu は削除せず残す' -ForegroundColor Yellow
} else {
    Write-Host '  ✓ Ubuntu (古い方) は既に不在' -ForegroundColor Green
}

Step 4 '残る手動 GUI 作業'
Write-Host '  - simplewall を Start から起動 → Filter mode 選択して activate'
Write-Host '  - AHK タスクトレイ右クリック → Open → View → Key history → Copilot キーを押して scancode 取得'
Write-Host '  - 取得した scancode を windows/sharpkeys/apply.ps1 か windows/autohotkey/keymap.ahk に反映'

Step 5 '再起動'
if ($NoReboot) {
    Write-Host '  -NoReboot 指定。手動で再起動してください (CapsLock→Ctrl + Bitdefender + UTF-8 ACP 反映のため)' -ForegroundColor Yellow
} else {
    $r = Read-Host '今すぐ再起動しますか? [y/N]'
    if ($r -match '^(y|Y)') {
        Write-Host '  10 秒後に再起動します...' -ForegroundColor Yellow
        shutdown /r /t 10 /c 'dotfiles finalize: 10 秒後に再起動'
    } else {
        Write-Host '  → 後で手動で再起動 (shutdown /r /t 0)' -ForegroundColor Yellow
    }
}
