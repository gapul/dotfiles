# apps.json (宣言) と winget list (実 install) の差分を表示する。
# - MISSING : apps.json 宣言にあるが install されていない
# - EXTRA   : install されているが apps.json に居ない (手動 install / scoop 等)
# - INSTALLED : 両方にある
# 設計判断: winget import は宣言外を消さないので "EXTRA" を機械的に削除しない
#           (Nix の cleanup="uninstall" 相当が無い)。可視化のみ。
[CmdletBinding()]
param(
    [string]$AppsJson,
    [switch]$ShowExtra # EXTRA も全件出す (既定は数だけ要約)
)

$ErrorActionPreference = 'Stop'
if (-not $AppsJson) {
    # 5.1 では param デフォルト式の $PSScriptRoot が空になるケースがあるため
    # 関数本体に入ってから解決する。
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $AppsJson  = Join-Path $scriptDir 'apps.json'
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Error 'winget 不在'; exit 2 }
if (-not (Test-Path $AppsJson))                              { Write-Error "apps.json 不在: $AppsJson"; exit 2 }

$env:WINGET_DISABLE_PROGRESS = '1'

# 1. 宣言側
$declared = (Get-Content $AppsJson -Raw | ConvertFrom-Json).Sources[0].Packages.PackageIdentifier
if (-not $declared) { Write-Error 'apps.json に Packages が無い'; exit 2 }
$declaredSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$declared, [System.StringComparer]::OrdinalIgnoreCase)

# 2. 実 install (winget export で JSON dump → ID を取り出す)。
#    旧実装は `winget list` の表を正規表現で parse していたが、以下の理由で外した:
#    ・winget の auto-fit column 幅で Name と ID の境界 spacing が 1 文字になることがあり
#      `\s{2,}` で区切れない (例: wez.wezterm の "WezTerm version <ver>" Name)
#    ・ID に `+` や `@` 等の特殊文字が来ると charset から漏れる (例: Henry++.simplewall)
#    winget export は公式機能で確実に全 installed ID を JSON で吐く。
Write-Host 'winget export を取得中...' -ForegroundColor DarkGray
$tmpExport = Join-Path $env:TEMP "winget-export-$(Get-Random).json"
try {
    winget export --include-versions --source winget --accept-source-agreements --output $tmpExport 2>&1 | Out-Null
    if (-not (Test-Path $tmpExport)) { Write-Error 'winget export が失敗 (file not created)'; exit 2 }
    $exported = Get-Content $tmpExport -Raw | ConvertFrom-Json
    $ids = @($exported.Sources | ForEach-Object { $_.Packages.PackageIdentifier })
} finally {
    Remove-Item $tmpExport -ErrorAction SilentlyContinue
}
$installedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$ids, [System.StringComparer]::OrdinalIgnoreCase)

# 3. 差分計算
$missing = $declared | Where-Object { -not $installedSet.Contains($_) } | Sort-Object
$extra   = $ids      | Where-Object { -not $declaredSet.Contains($_) } | Sort-Object -Unique
$both    = $declared | Where-Object { $installedSet.Contains($_) } | Sort-Object

Write-Host ''
Write-Host ("INSTALLED: {0} / {1}" -f $both.Count, $declared.Count) -ForegroundColor Green
Write-Host ("MISSING  : {0}  (apps.json 宣言 - 実 install)" -f $missing.Count) -ForegroundColor Yellow
Write-Host ("EXTRA    : {0}  (実 install - apps.json 宣言)" -f $extra.Count) -ForegroundColor DarkCyan

if ($missing) {
    Write-Host ''
    Write-Host 'MISSING:' -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  - $_" }
    Write-Host ('対処: pwsh -File windows\bootstrap.ps1 (winget import で一括 install)') -ForegroundColor DarkGray
}

if ($extra -and $ShowExtra) {
    Write-Host ''
    Write-Host 'EXTRA:' -ForegroundColor DarkCyan
    $extra | ForEach-Object { Write-Host "  - $_" }
}

# missing があれば exit 1 (CI / just gate 用)
if ($missing.Count -gt 0) { exit 1 }
exit 0
