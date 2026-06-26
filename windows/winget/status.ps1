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

# 2. 実 install (winget source=winget 由来のみ。MS Store 由来等は除外)
#    --source winget で winget リポジトリ由来のみに絞る。
Write-Host 'winget list を取得中...' -ForegroundColor DarkGray
$raw = winget list --source winget --disable-interactivity --accept-source-agreements 2>&1 | Out-String
# 出力は表形式 (列: 名前 / ID / バージョン)。ID 列を正規表現で拾う。
$ids = @()
foreach ($line in ($raw -split "`r?`n")) {
    if ($line -match '^\s*\S.*?\s{2,}([A-Za-z0-9_.\-]+)\s{2,}\S') {
        $candidate = $matches[1]
        # ヘッダ行 ("Id"/"ID") を除外
        if ($candidate -notmatch '^(Id|ID|名前|Name)$' -and $candidate.Length -gt 2) {
            $ids += $candidate
        }
    }
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
