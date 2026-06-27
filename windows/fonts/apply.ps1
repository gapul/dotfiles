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
    [switch]$Force,        # 既存があっても強制上書き
    [switch]$SkipHackGen   # HackGen 自動 DL を skip
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

# ─── HackGen 自動 DL (Mac の cask `font-hackgen-nerd` と整合) ───
# yuru7/HackGen は winget/scoop 未収録なので GitHub Release から直接 DL する。
# 既に install 済なら skip。
if (-not $SkipHackGen) {
    $hackgenInstalled = @(
        Get-ChildItem $FontsDst, 'C:\Windows\Fonts' -ErrorAction SilentlyContinue |
            Where-Object Name -match 'HackGen'
    ) | Select-Object -First 1
    if ($hackgenInstalled) {
        Log "HackGen install 済: $($hackgenInstalled.Name)"
    } else {
        if ($DryRun) {
            Dry 'gh release download yuru7/HackGen --pattern "HackGen_NF_v*.zip" → 解凍 → user fonts install'
        } else {
            Log 'HackGen 未 install → yuru7/HackGen から DL...'
            $tmpZip = Join-Path $env:TEMP "HackGen_NF-$(Get-Random).zip"
            $tmpDir = Join-Path $env:TEMP "HackGen_NF-$(Get-Random)"
            try {
                # gh release download (public repo は auth 不要)
                $exitOk = $false
                if (Get-Command gh -ErrorAction SilentlyContinue) {
                    gh release download --repo yuru7/HackGen --pattern 'HackGen_NF_v*.zip' `
                        --output $tmpZip --clobber 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpZip)) { $exitOk = $true }
                }
                if (-not $exitOk) {
                    # Fallback: GitHub API で latest release の asset URL を取って IWR
                    Log '  gh で取れず → GitHub API fallback'
                    $api = 'https://api.github.com/repos/yuru7/HackGen/releases/latest'
                    $rel = Invoke-RestMethod -Uri $api -UseBasicParsing
                    $assetUrl = ($rel.assets | Where-Object { $_.name -like 'HackGen_NF_v*.zip' } |
                                 Select-Object -First 1).browser_download_url
                    if (-not $assetUrl) { throw 'HackGen_NF_v*.zip asset が release に無い' }
                    Invoke-WebRequest -Uri $assetUrl -OutFile $tmpZip -UseBasicParsing
                }
                Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
                $ttfs = Get-ChildItem $tmpDir -Recurse -Filter '*.ttf'
                Log "  $($ttfs.Count) ファイル取得 → user-scope install"
                foreach ($ttf in $ttfs) {
                    $dst     = Join-Path $FontsDst $ttf.Name
                    $regName = "$([System.IO.Path]::GetFileNameWithoutExtension($ttf.Name)) (TrueType)"
                    Copy-Item $ttf.FullName $dst -Force
                    Set-ItemProperty -Path $RegPath -Name $regName -Value $dst -Force
                    Log "    installed: $($ttf.Name)"
                }
                Log 'HackGen install 完了'
            } catch {
                Err "HackGen 自動 DL 失敗 (続行): $($_.Exception.Message)"
            } finally {
                Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
                Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Log ''
Log '完了。新しい app で読み込まれます。WezTerm / Zebar が起動中なら再起動。'
