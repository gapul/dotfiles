# Windows ロケール / 言語設定を declarative に揃える。
# 英語 UI で動かしつつ、SJIS 由来の mojibake (`\` → `¥` 等) を解消する。
#
# 適用内容:
#   A. User Language List を en-US, ja-JP の順で固定
#      (アプリの自動 UI 言語選択を英語側にする / IME は ja-JP を残して SKK 等使用)
#   B. System Locale を en-US にして CodePage (ACP/OEMCP/MACCP) を 65001 (UTF-8) 化
#      (Win10 "Use Unicode UTF-8 for worldwide language support" Beta 機能)
#   C. Home Location を US (GeoId 244) にする
#
# B は **再起動必須** (CodePage 切替は OS 起動時にしか効かない)。
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipLanguageList,   # A を skip
    [switch]$SkipSystemLocale,   # B を skip (`\` → `¥` 解消も skip)
    [switch]$SkipHomeLocation    # C を skip (Japan のまま残す)
)

$ErrorActionPreference = 'Stop'

function Log($msg) { Write-Host "[locale] $msg"      -ForegroundColor Blue }
function Dry($msg) { Write-Host "[locale][dry] $msg" -ForegroundColor DarkYellow }
function Err($msg) { Write-Host "[locale] $msg"      -ForegroundColor Red }

# ─── 管理者チェック (DryRun は除外) ───
if (-not $DryRun) {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log '管理者権限が必要です。UAC promptで再起動します...'
        $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($SkipLanguageList) { $childArgs += '-SkipLanguageList' }
        if ($SkipSystemLocale) { $childArgs += '-SkipSystemLocale' }
        if ($SkipHomeLocation) { $childArgs += '-SkipHomeLocation' }
        Start-Process pwsh -Verb RunAs -ArgumentList $childArgs
        exit
    }
}

# ─── A. User Language List を ja-JP 1 個に、IME を CorvusSKK のみに ───
# - en-US 言語を削除 → 英語キーボードレイアウト (0409:00000409) が消える
# - ja-JP の InputMethodTips を CorvusSKK だけにして MS-IME を消す
# - 結果: Win+Space で切替表示が出ない / Language Bar に 1 個だけ表示
# - 英語入力は CorvusSKK の直接入力モードで OK (l キーで切替)
# - UI Display Language は en-US Override で英語維持
#
# CorvusSKK の TIP は固定 (install 時に登録される、ユーザー間で共通):
#   ProfileGUID: {956F14B3-5310-4CEF-9651-26710EB72F3A}
#   CLSID      : {EAEA0E29-AA1E-48EF-B2DF-46F4E24C6265}
if (-not $SkipLanguageList) {
    $skkTip = '0411:{EAEA0E29-AA1E-48EF-B2DF-46F4E24C6265}{956F14B3-5310-4CEF-9651-26710EB72F3A}'
    $current = Get-WinUserLanguageList
    $currentTags = $current | ForEach-Object LanguageTag
    $currentTips = ($current | Where-Object LanguageTag -in 'ja', 'ja-JP' | ForEach-Object { $_.InputMethodTips }) -join ', '
    Log "User Language List - 現状 tags: $($currentTags -join ', ') / Tips: $currentTips"

    $skkRegistered = Get-Item "Registry::HKEY_CLASSES_ROOT\CLSID\{EAEA0E29-AA1E-48EF-B2DF-46F4E24C6265}" -ErrorAction SilentlyContinue
    if (-not $skkRegistered) {
        Err 'CorvusSKK が install されていない (CLSID 未登録)。winget install nathancorvussolis.corvusskk → 再ログイン後にもう一度 just win-locale'
    } else {
        if ($DryRun) {
            Dry "New-WinUserLanguageList -Language ja-JP → InputMethodTips を [$skkTip] のみに"
            Dry "Set-WinUserLanguageList → ja-JP 1 個のみ (en-US 言語と 0409:00000409 キーボードレイアウトが消える)"
            Dry "Set-WinUILanguageOverride -Language en-US (UI は英語維持)"
        } else {
            $langList = New-WinUserLanguageList -Language 'ja-JP'
            $langList[0].InputMethodTips.Clear()
            $langList[0].InputMethodTips.Add($skkTip)
            Set-WinUserLanguageList -LanguageList $langList -Force -WarningAction SilentlyContinue
            Set-WinUILanguageOverride -Language en-US
            Log 'User Language List = ja-JP 1 個 / IME = CorvusSKK のみ / UI Display = en-US (override)'
            Log '⚠ 言語/IME 変更は **再ログイン** で完全反映'
        }
    }
}

# ─── B. System Locale + ACP/OEMCP/MACCP = 65001 (UTF-8) ────
if (-not $SkipSystemLocale) {
    $currentSL = (Get-WinSystemLocale).Name
    Log "System Locale - 現状: $currentSL"
    if ($currentSL -ne 'en-US') {
        if ($DryRun) {
            Dry 'Set-WinSystemLocale -SystemLocale en-US'
        } else {
            Set-WinSystemLocale -SystemLocale en-US
            Log 'System Locale を en-US に設定'
        }
    }

    # CodePage (Beta UTF-8) — レジストリ書込
    $cpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
    $cpProps = @{ ACP = '65001'; OEMCP = '65001'; MACCP = '65001' }
    foreach ($name in $cpProps.Keys) {
        $current = (Get-ItemProperty -Path $cpKey -Name $name -ErrorAction SilentlyContinue).$name
        if ($current -ne $cpProps[$name]) {
            if ($DryRun) {
                Dry "Set $cpKey\$name = $($cpProps[$name]) (was: $current)"
            } else {
                Set-ItemProperty -Path $cpKey -Name $name -Value $cpProps[$name] -Force
                Log "CodePage $name = $($cpProps[$name]) (was: $current)"
            }
        }
    }
    Log '⚠ System Locale + CodePage の変更は **再起動** で反映されます'
}

# ─── C. Home Location ─────────────────────────────────────
if (-not $SkipHomeLocation) {
    # 244 = United States, 122 = Japan
    $desiredGeo = 244
    $current = (Get-WinHomeLocation).GeoId
    Log "Home Location - 現状 GeoId: $current"
    if ($current -ne $desiredGeo) {
        if ($DryRun) {
            Dry "Set-WinHomeLocation -GeoId $desiredGeo (United States)"
        } else {
            Set-WinHomeLocation -GeoId $desiredGeo
            Log "Home Location: United States (GeoId $desiredGeo)"
        }
    } else {
        Log 'Home Location 既に United States (no-op)'
    }
}

Log ''
Log '完了。System Locale / CodePage を変更した場合は **再起動** で反映されます。'
