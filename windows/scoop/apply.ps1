# Scoop で bucket / app を declarative に適用する orchestrator。
# - winget で取れない MS Store 専用 app (Files 等) を sideload 経由で取得する目的。
# - 設定: windows/scoop/scoop.json
# - 関連: windows/scoop/README.md
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipBuckets,
    [switch]$SkipApps
)

$ErrorActionPreference = 'Stop'
$ScoopDir = $PSScriptRoot
if (-not $ScoopDir) {
    $ScoopDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Log($msg) { Write-Host "[scoop] $msg"      -ForegroundColor Blue }
function Dry($msg) { Write-Host "[scoop][dry] $msg" -ForegroundColor DarkYellow }
function Err($msg) { Write-Host "[scoop] $msg"      -ForegroundColor Red }

# ─── 0. Scoop 自体の確保 ───
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    if ($DryRun) {
        Dry 'irm https://get.scoop.sh | iex (Scoop install)'
    } else {
        Log 'Scoop 未導入 → install...'
        # 管理者だと Scoop は警告して止まる。-RunAsAdmin で強制可能だが推奨は非管理者。
        Invoke-Expression (Invoke-WebRequest -Uri 'https://get.scoop.sh' -UseBasicParsing).Content
        Log 'Scoop install 完了'
    }
} else {
    $sv = scoop --version 2>&1 | Select-Object -First 1
    Log "Scoop OK ($sv)"
}

# ─── 1. scoop.json 読込 ───
$ConfigFile = Join-Path $ScoopDir 'scoop.json'
if (-not (Test-Path $ConfigFile)) {
    Err "scoop.json が無い: $ConfigFile"
    return
}
try {
    $conf = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Err "scoop.json が不正 JSON: $($_.Exception.Message)"
    return
}

# ─── 2. bucket 追加 ───
if (-not $SkipBuckets -and $conf.buckets) {
    foreach ($bucket in $conf.buckets) {
        if ($DryRun) {
            Dry "scoop bucket add $bucket"
            continue
        }
        # 既存 bucket なら scoop は exit 1 を返すが、冪等運用したいので無視
        scoop bucket add $bucket 2>&1 | Out-Null
        Log "bucket: $bucket OK"
    }
} elseif ($SkipBuckets) {
    Log 'SkipBuckets: bucket 追加を skip'
}

# ─── 3. app install ───
if (-not $SkipApps -and $conf.apps) {
    foreach ($app in $conf.apps) {
        if ($DryRun) {
            Dry "scoop install $app"
            continue
        }
        Log "install: $app ..."
        scoop install $app
    }
} elseif ($SkipApps) {
    Log 'SkipApps: app install を skip'
}

Log ''
Log '完了。'
