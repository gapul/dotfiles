# windows/winget/apps.json の全 PackageIdentifier が winget に実在するか検証する。
#
# 実行: pwsh -NoProfile -File windows/winget/verify.ps1
# 出力: 各 ID に対し OK / MISS / ERR。MISS が 1 件でもあれば exit 1。
#
# bootstrap.ps1 を回す前 / apps.json を編集した後 / SETUP-CHECKLIST 検証時に使う。
# `winget show --id <id> --exact` を 1 件ずつ叩くため数十秒〜数分かかる。
# CI からは `--Strict` で MISS=fail、ローカル探索時はそのままで MISS=警告のみにする。
[CmdletBinding()]
param(
    [string]$AppsJson = (Join-Path $PSScriptRoot 'apps.json'),
    [switch]$Strict   # MISS があれば exit 1 (CI 用)
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error 'winget が見つかりません。bootstrap.ps1 の手順で App Installer を導入してください。'
    exit 2
}
if (-not (Test-Path $AppsJson)) {
    Write-Error "apps.json が見つかりません: $AppsJson"
    exit 2
}

# winget の進捗バーが pwsh ホストの再描画と干渉して 255 終了することがあるため抑止
$env:WINGET_DISABLE_PROGRESS = '1'

$pkgs = (Get-Content $AppsJson -Raw | ConvertFrom-Json).Sources[0].Packages
if (-not $pkgs) {
    Write-Error 'apps.json に Packages がありません。'
    exit 2
}

$total = $pkgs.Count
$ok    = 0
$miss  = @()
$err   = @()
$i     = 0

foreach ($p in $pkgs) {
    $i++
    $id = $p.PackageIdentifier
    Write-Progress -Activity 'winget 実在検証' -Status "[$i/$total] $id" -PercentComplete (($i / $total) * 100)
    # `winget show` は ID が無い時 exit code 非 0、見つかると "バージョン:" / "Version:" 行が出る
    $raw = winget show --id $id --exact --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and ($raw -match '(?m)^\s*(バージョン|Version)\s*:')) {
        Write-Host ("  OK   {0}" -f $id) -ForegroundColor Green
        $ok++
    } elseif ($raw -match 'No package found' -or $raw -match 'パッケージが見つかりません') {
        Write-Host ("  MISS {0}" -f $id) -ForegroundColor Yellow
        $miss += $id
    } else {
        # winget 自身が落ちた / 想定外フォーマット
        Write-Host ("  ERR  {0}  (winget exit={1})" -f $id, $LASTEXITCODE) -ForegroundColor Red
        $err += $id
    }
}
Write-Progress -Activity 'winget 実在検証' -Completed

Write-Host ''
Write-Host ("結果: OK={0} / MISS={1} / ERR={2} / total={3}" -f $ok, $miss.Count, $err.Count, $total)
if ($miss.Count -gt 0) {
    Write-Host ''
    Write-Host '存在しなかった ID (apps.json から削除 or 正しい ID へ修正):' -ForegroundColor Yellow
    $miss | ForEach-Object { Write-Host "  - $_" }
}
if ($err.Count -gt 0) {
    Write-Host ''
    Write-Host 'winget が想定外応答を返した ID (再試行 / source 更新を検討):' -ForegroundColor Red
    $err | ForEach-Object { Write-Host "  - $_" }
}

if ($Strict -and ($miss.Count -gt 0 -or $err.Count -gt 0)) {
    exit 1
}
exit 0
