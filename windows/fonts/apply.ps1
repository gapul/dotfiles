# configs/fonts/ の .ttf / .otf を Windows に user-scope install。
# Mac の home-manager で `font-hackgen-nerd` 等を入れているのと同じ精神で、
# Windows でも declarative にフォント install を再現する。
#
# user-scope install (Windows 10 1809 以降):
#   - %LOCALAPPDATA%\Microsoft\Windows\Fonts\ にコピー
#   - HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts にレジストリ登録
#   - 管理者権限不要
#
# 関連: windows/fonts/README.md, configs/fonts/
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force   # 既存があっても強制上書き
)

$ErrorActionPreference = 'Stop'
$DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
$FontsSrc    = Join-Path $DotfilesDir 'configs\fonts'
$FontsDst    = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$RegPath     = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

function Log($msg) { Write-Host "[fonts] $msg"      -ForegroundColor Blue }
function Dry($msg) { Write-Host "[fonts][dry] $msg" -ForegroundColor DarkYellow }
function Err($msg) { Write-Host "[fonts] $msg"      -ForegroundColor Red }

if (-not (Test-Path $FontsSrc)) {
    Err "$FontsSrc が無い (skip)"
    return
}

if (-not $DryRun -and -not (Test-Path $FontsDst)) {
    New-Item -ItemType Directory -Path $FontsDst -Force | Out-Null
}

# .ttf / .otf を全部対象に。ttc も対応するなら追加。
$fonts = Get-ChildItem $FontsSrc -Include '*.ttf', '*.otf' -Recurse
Log "対象 $($fonts.Count) ファイル: $($fonts | ForEach-Object Name | Sort-Object) -join ', "

foreach ($f in $fonts) {
    $dst = Join-Path $FontsDst $f.Name
    $regName = "$([System.IO.Path]::GetFileNameWithoutExtension($f.Name)) (TrueType)"
    if ($f.Extension -eq '.otf') {
        $regName = "$([System.IO.Path]::GetFileNameWithoutExtension($f.Name)) (OpenType)"
    }

    # 既に同一ファイルが配置済 + 同 registry 名で値も同じなら skip
    $existsFile = Test-Path $dst
    $existsReg  = (Get-ItemProperty -Path $RegPath -Name $regName -ErrorAction SilentlyContinue).$regName -eq $dst
    if ($existsFile -and $existsReg -and -not $Force) {
        Log "skip (既に登録済): $($f.Name)"
        continue
    }

    if ($DryRun) {
        Dry "copy $($f.FullName) -> $dst"
        Dry "Set-ItemProperty $RegPath\$regName = $dst"
        continue
    }

    Copy-Item $f.FullName $dst -Force
    Set-ItemProperty -Path $RegPath -Name $regName -Value $dst -Force
    Log "installed: $($f.Name) -> $regName"
}

Log ''
Log '完了。新しい app で読み込まれます。WezTerm / Zebar が起動中なら再起動。'
