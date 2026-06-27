# テーマ palette を configs/theme/palettes.json から読んで Windows 側
# 各 config に染込む (Mac の home-manager で nix/lib/theme.nix を参照する
# のと同じ精神の SSO 化)。
#
# 対象:
#   - configs/wm/zebar/styles.css   (CSS 変数を palette で上書き)
#   - configs/wm/glazewm/config.yaml (border 色を palette で上書き)
#   - configs/terminals/wezterm/wezterm.lua (color_scheme は内蔵で OK だが
#     window/cursor 色を palette と整合させる)
#   - windows/terminal/settings.json (schemes に Rose Pine を生成 + 適用)
#
# template マーカー: {{ palette.X }} を palette.json の値で置換。
# X は base/surface/overlay/muted/subtle/text/love/gold/rose/pine/foam/iris/hlMed。
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$ActivePalette   # 'rose-pine' / 'rose-pine-dawn' 等。未指定なら palettes.json の active
)

$ErrorActionPreference = 'Stop'
$DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
$PalettesJson = Join-Path $DotfilesDir 'configs\theme\palettes.json'

function Log($msg) { Write-Host "[theme] $msg"      -ForegroundColor Blue }
function Dry($msg) { Write-Host "[theme][dry] $msg" -ForegroundColor DarkYellow }
function Err($msg) { Write-Host "[theme] $msg"      -ForegroundColor Red }

if (-not (Test-Path $PalettesJson)) {
    Err "palettes.json が無い: $PalettesJson"
    exit 1
}

# UTF-8 で確実に読む (PS 5.1 の Get-Content default は ANSI)
$themeData = Get-Content $PalettesJson -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $ActivePalette) { $ActivePalette = $themeData.active }
$palette = $themeData.palettes.$ActivePalette
if (-not $palette) {
    Err "palette '$ActivePalette' が palettes.json に無い"
    exit 1
}
Log "active palette: $ActivePalette (variant: $($palette.variant))"

# ─── template 置換 helper ───
# template ファイルを読んで {{ palette.X }} を palette の hex (# prefix 付き) で置換、出力先に書く。
function Render-Template {
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$OutputPath
    )
    if (-not (Test-Path $TemplatePath)) {
        Err "template 不在 (skip): $TemplatePath"
        return
    }
    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
    # palette キー (base/surface/...) を全部置換。各キーは "#${hex}" 形式に。
    foreach ($prop in $palette.PSObject.Properties) {
        $placeholder = '\{\{\s*palette\.' + [regex]::Escape($prop.Name) + '\s*\}\}'
        $value = "#$($prop.Value)"   # palette.json は prefix 無し hex なので # を付与
        $content = [regex]::Replace($content, $placeholder, $value)
    }
    # palette 全体に対する hex のみ (# 無し) パターン: {{ palette.X:raw }}
    foreach ($prop in $palette.PSObject.Properties) {
        $placeholder = '\{\{\s*palette\.' + [regex]::Escape($prop.Name) + ':raw\s*\}\}'
        $content = [regex]::Replace($content, $placeholder, $prop.Value)
    }

    if ($DryRun) {
        Dry "render $TemplatePath -> $OutputPath ($($content.Length) bytes)"
        return
    }
    $outDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    # UTF-8 BOM 無しで書出 (CSS/YAML/JSON は BOM が問題になる場合あり)
    [System.IO.File]::WriteAllText($OutputPath, $content, [System.Text.UTF8Encoding]::new($false))
    Log "rendered: $OutputPath"
}

# ─── 対象 (template -> output) ───
# template が無いものは skip。output は dotfiles 内の通常 config パス
# (bootstrap.ps1 が symlink で各 app の実 path に link する)。
$Targets = @(
    @{ Tmpl = Join-Path $DotfilesDir 'configs\wm\zebar\styles.css.tmpl';
       Out  = Join-Path $DotfilesDir 'configs\wm\zebar\styles.css' },
    @{ Tmpl = Join-Path $DotfilesDir 'configs\wm\glazewm\config.yaml.tmpl';
       Out  = Join-Path $DotfilesDir 'configs\wm\glazewm\config.yaml' },
    @{ Tmpl = Join-Path $DotfilesDir 'windows\terminal\settings.json.tmpl';
       Out  = Join-Path $DotfilesDir 'windows\terminal\settings.json' },
    @{ Tmpl = Join-Path $DotfilesDir 'configs\terminals\wezterm\wezterm.lua.tmpl';
       Out  = Join-Path $DotfilesDir 'configs\terminals\wezterm\wezterm.lua' }
)
foreach ($t in $Targets) {
    Render-Template -TemplatePath $t.Tmpl -OutputPath $t.Out
}

Log ''
Log '完了。app を再起動すると新色が反映されます (GlazeWM/Zebar/WezTerm/Windows Terminal)。'
