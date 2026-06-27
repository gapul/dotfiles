# Windows native 0→1 セットアップ (PowerShell 7+ 想定)
# 想定: Windows 11 fresh install + WSL2 未導入 (or 別途)
#
# 流れ:
#   1. winget 確認
#   1.5 PowerShell 7 を先に確保
#   2. winget/apps.json から一括 install (空ファイルなら skip)
#   2.5 scoop bucket + app の declarative 適用 (MS Store 回避用)
#   3. PowerShell $PROFILE を dotfiles 内ファイルへ symlink
#   4. Windows Terminal settings.json を生成 (WSL user/distro 注入)
#   4.5 configs/ の各ツール config を %APPDATA% / %LOCALAPPDATA% へ symlink
#   5. (任意) age / SSH 鍵 paste 待ち
#   5.5 ssh-agent サービスを Auto+Running に
#   6. git の global config
#   7. プライバシー / 標準機能の declarative 適用 (-SkipPrivacy で省略可)
#   8. キーマップ — SharpKeys (Scancode Map) + AHK (Startup 登録) (-SkipKeymap で省略可)
#   9. ロケール / 言語 — User Language List / System Locale / Home Location (-SkipLocale で省略可)
#
# -DryRun で symlink 作成等の副作用を出さず計画だけ表示。
#
# 何度走らせても安全 (idempotent)。
# 管理者 PowerShell で実行推奨 (symlink 作成に SeCreateSymbolicLinkPrivilege が必要)
#
# WSL の distro/ユーザー名は -WslDistro / -WslUser で上書き可:
#   & bootstrap.ps1 -WslUser alice -WslDistro Debian
param(
    [string]$WslUser   = $env:USERNAME,  # WSL 側ユーザー名 (Terminal の startingDirectory に注入)。WSL のユーザー名が違えば -WslUser で上書き
    [string]$WslDistro = 'Ubuntu',    # WSL ディストリ名
    # git author (macOS/WSL は nix/user.nix が正。Windows は nix eval 不可のため引数で渡す)
    [string]$GitUser   = 'gapul',
    [string]$GitEmail  = '92638132+gapul@users.noreply.github.com',
    # 実害なしでステップを表示するだけ (configs symlink 検証等)
    [switch]$DryRun,
    # プライバシー適用 (Win11Debloat + WinUtil) を skip
    [switch]$SkipPrivacy,
    # Scoop (windows/scoop/scoop.json) の bucket / app 適用を skip
    [switch]$SkipScoop,
    # キーマップ (SharpKeys + AHK Startup) を skip
    [switch]$SkipKeymap,
    # ロケール / 言語 (User Language List / System Locale / Home Location) を skip
    [switch]$SkipLocale
)

$ErrorActionPreference = 'Stop'

# ─── 0. 管理者チェック (DryRun は除外) ───
# symlink 作成 (SeCreateSymbolicLinkPrivilege) / ssh-agent サービス変更 /
# プライバシー & SharpKeys の各 apply.ps1 が全部管理者要なので、
# 非管理者で起動された場合は UAC 起こして elevate した子プロセスに引き継ぐ。
if (-not $DryRun) {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host '[bootstrap-win] 管理者権限が必要です。UAC promptで再起動します...' -ForegroundColor Blue
        $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        $childArgs += @('-WslUser', $WslUser, '-WslDistro', $WslDistro, '-GitUser', $GitUser, '-GitEmail', $GitEmail)
        if ($SkipPrivacy) { $childArgs += '-SkipPrivacy' }
        if ($SkipScoop)   { $childArgs += '-SkipScoop' }
        if ($SkipKeymap)  { $childArgs += '-SkipKeymap' }
        if ($SkipLocale)  { $childArgs += '-SkipLocale' }
        Start-Process pwsh -Verb RunAs -ArgumentList $childArgs
        exit
    }
}

$DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
$WindowsDir = Join-Path $DotfilesDir 'windows'

function Log($msg) { Write-Host "[bootstrap-win] $msg" -ForegroundColor Blue }
function Err($msg) { Write-Host "[bootstrap-win] $msg" -ForegroundColor Red }
function Dry($msg) { Write-Host "[bootstrap-win][dry] $msg" -ForegroundColor DarkYellow }

# 任意の (src, dest) を symlink する共通関数。
# - dest 親ディレクトリが無ければ作る
# - 既存が同一 target の symlink なら no-op (冪等)
# - 既存が別物 (実ファイル / ディレクトリ / 別 target の symlink) なら .bak-<日時> に退避
# - -DryRun では何もせず計画だけ出す
function New-DotfilesLink {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Label
    )
    if (-not $Label) { $Label = Split-Path $Destination -Leaf }
    if (-not (Test-Path -LiteralPath $Source)) {
        Err "$Label : source 不在 ($Source) → skip"
        return
    }
    $destParent = Split-Path $Destination -Parent
    if (-not (Test-Path -LiteralPath $destParent)) {
        if ($DryRun) { Dry "mkdir $destParent" }
        else { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
    }
    if (Test-Path -LiteralPath $Destination) {
        $item = Get-Item -LiteralPath $Destination -Force
        if ($item.LinkType -eq 'SymbolicLink' -and $item.Target -eq $Source) {
            Log "$Label : 既に正しい symlink ($Destination)"
            return
        }
        $backup = "$Destination.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        if ($DryRun) { Dry "move $Destination -> $backup" }
        else {
            Move-Item -LiteralPath $Destination -Destination $backup -Force
            Log "$Label : 既存を $backup に退避"
        }
    }
    if ($DryRun) { Dry "symlink $Destination -> $Source"; return }
    New-Item -ItemType SymbolicLink -Path $Destination -Target $Source | Out-Null
    Log "$Label : $Destination -> $Source"
}

# 1. winget 確認
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err 'winget が見つかりません。Microsoft Store で "App Installer" を install してください。'
    Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1'
    exit 1
}
Log 'winget OK'

# 1.5 PowerShell 7 (pwsh) を先に確保。
# Windows 同梱は 5.1 (PSReadLine 2.0 系)。本 dotfiles の profile は
# `Set-PSReadLineOption -PredictionSource HistoryAndPlugin` (PSReadLine 2.2+) を使うため
# 5.1 では parameter validation で失敗する。後段の winget import より先に必ず入れる。
# なお既に pwsh が在れば再 install しない (winget 自身が冪等)。
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    if ($DryRun) {
        Dry 'winget install --id Microsoft.PowerShell (PowerShell 7)'
    } else {
        Log 'PowerShell 7 (pwsh) が未導入 -> winget で install...'
        winget install --id Microsoft.PowerShell --exact `
            --accept-package-agreements --accept-source-agreements `
            --silent --disable-interactivity
        # 当プロセスの PATH はインストーラが更新しないので、以降のステップで pwsh を
        # 直接呼ぶ必要があるなら絶対パスを使うこと。新しい PowerShell を開き直せば PATH に乗る。
        Log 'PowerShell 7 install 完了。今後は pwsh.exe で本スクリプトを再実行推奨。'
    }
} else {
    Log "pwsh OK ($($PSVersionTable.PSVersion))"
}

# 2. winget/apps.json import
$AppsJson = Join-Path $WindowsDir 'winget\apps.json'
if (Test-Path $AppsJson) {
    $content = Get-Content $AppsJson -Raw
    if ($content -match '"PackageIdentifier"') {
        if ($DryRun) {
            Dry "winget import --import-file $AppsJson --no-upgrade"
        } else {
            Log "Installing apps from $AppsJson ..."
            # --no-upgrade: 既存 install は触らない (Claude Code 等の自己プロセス lock 回避、
            #   アップグレードは `just win-upgrade` で別途実行する分離設計)
            # try-catch: 1 個失敗しても残り step (symlink / privacy / keymap) は続行する
            try {
                winget import --import-file $AppsJson --no-upgrade `
                    --accept-package-agreements --accept-source-agreements
                if ($LASTEXITCODE -ne 0) {
                    Log "winget import で 1 件以上失敗 (LASTEXITCODE=$LASTEXITCODE) — 続行"
                }
            } catch {
                Err "winget import 例外 (続行): $($_.Exception.Message)"
            }
        }
    } else {
        Log 'apps.json は空 (winget import スキップ)'
    }
} else {
    Log "$AppsJson が無いので winget import スキップ"
}

# 2.5 Scoop bucket / app の declarative 適用。
#     winget で取れない MS Store 専用 app (Files 等) を sideload するための補助。
#     詳細は windows/scoop/README.md。
if (-not $SkipScoop) {
    $scoopApply = Join-Path $WindowsDir 'scoop\apply.ps1'
    if (Test-Path $scoopApply) {
        if ($DryRun) {
            & $scoopApply -DryRun
        } else {
            Log 'Scoop 適用 (bucket + app) — skip するには -SkipScoop'
            & $scoopApply
        }
    } else {
        Log "$scoopApply が無い (skip)"
    }
} else {
    Log 'SkipScoop 指定: just win-scoop で後から適用可'
}

# 3. PowerShell $PROFILE を symlink。
#    PowerShell 5.1 と 7 で $PROFILE のパスが違うので両方を symlink するため
#    Documents 配下の WindowsPowerShell / PowerShell の両方に張る。
$ProfileSrc      = Join-Path $WindowsDir 'profile\Microsoft.PowerShell_profile.ps1'
$ProfilePwsh7    = Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
$ProfilePwsh5    = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
foreach ($dst in @($ProfilePwsh7, $ProfilePwsh5)) {
    New-DotfilesLink -Source $ProfileSrc -Destination $dst -Label 'profile'
}

# 4. Windows Terminal settings.json を生成 (symlink でなく render)
#    startingDirectory の __WSL_USER__ / __WSL_DISTRO__ を実値へ置換するため、
#    symlink でなく「コピー + 置換」で配置する。settings を編集したら再実行で反映。
$WTSrc = Join-Path $WindowsDir 'terminal\settings.json'
$WTDst = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if ((Test-Path $WTSrc) -and (Test-Path (Split-Path $WTDst -Parent))) {
    $rendered = (Get-Content $WTSrc -Raw) `
        -replace '__WSL_USER__',   $WslUser `
        -replace '__WSL_DISTRO__', $WslDistro
    if ($DryRun) {
        Dry "render WT settings.json (WslUser=$WslUser / WslDistro=$WslDistro) -> $WTDst"
    } else {
        # 既存が手書き設定 (symlink でない & placeholder 由来でない) なら backup 退避
        if ((Test-Path $WTDst) -and ((Get-Content $WTDst -Raw) -ne $rendered)) {
            $backup = "$WTDst.bak-$(Get-Date -Format yyyyMMddHHmmss)"
            Copy-Item $WTDst $backup
            Log "既存 WT settings → $backup に退避"
        }
        Set-Content -Path $WTDst -Value $rendered -Encoding UTF8 -NoNewline
        Log "WT settings.json を生成 (WslUser=$WslUser / WslDistro=$WslDistro)"
    }
}

# 4.5 各ツールの config を %APPDATA% / %LOCALAPPDATA% へ symlink。
#     starship は $env:STARSHIP_CONFIG で profile.ps1 から直接参照するため symlink 不要。
#     yazi は config dir として "config" サブディレクトリを期待するため階層注意。
$ConfigLinks = @(
    @{ Label = 'gh';      Src = (Join-Path $DotfilesDir 'configs\cli\gh');           Dst = (Join-Path $env:APPDATA      'GitHub CLI') },
    @{ Label = 'bat';     Src = (Join-Path $DotfilesDir 'configs\cli\bat');          Dst = (Join-Path $env:APPDATA      'bat') },
    @{ Label = 'yazi';    Src = (Join-Path $DotfilesDir 'configs\cli\yazi');         Dst = (Join-Path $env:APPDATA      'yazi\config') },
    @{ Label = 'nvim';    Src = (Join-Path $DotfilesDir 'configs\editors\nvim');     Dst = (Join-Path $env:LOCALAPPDATA 'nvim') },
    @{ Label = 'zed';     Src = (Join-Path $DotfilesDir 'configs\editors\zed');      Dst = (Join-Path $env:APPDATA      'Zed') },
    # espanso: match/base.yml をファイル単独で symlink。macOS と同じ matches を再利用。
    @{ Label = 'espanso'; Src = (Join-Path $DotfilesDir 'configs\espanso\base.yml'); Dst = (Join-Path $env:APPDATA      'espanso\match\base.yml') },
    # wezterm: ~/.wezterm.lua を symlink (WezTerm は ~/.config/wezterm/ より優先)。
    @{ Label = 'wezterm'; Src = (Join-Path $DotfilesDir 'configs\terminals\wezterm\wezterm.lua'); Dst = (Join-Path $env:USERPROFILE '.wezterm.lua') },
    # glazewm: ~/.glzr/glazewm/config.yaml を symlink (AeroSpace 設定移植版)
    @{ Label = 'glazewm'; Src = (Join-Path $DotfilesDir 'configs\wm\glazewm\config.yaml'); Dst = (Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml') },
    # zebar: ~/.glzr/zebar/{styles.css,settings.json} を symlink (SketchyBar 寄せ Rose Pine)
    @{ Label = 'zebar-css';      Src = (Join-Path $DotfilesDir 'configs\wm\zebar\styles.css');    Dst = (Join-Path $env:USERPROFILE '.glzr\zebar\styles.css') },
    @{ Label = 'zebar-settings'; Src = (Join-Path $DotfilesDir 'configs\wm\zebar\settings.json'); Dst = (Join-Path $env:USERPROFILE '.glzr\zebar\settings.json') }
)
foreach ($link in $ConfigLinks) {
    New-DotfilesLink -Source $link.Src -Destination $link.Dst -Label $link.Label
}

# 5. age / SSH 鍵 (任意)。存在すれば ACL を本人のみに絞る。
#    Windows には chmod が無く、OpenSSH は「他ユーザーが読める秘密鍵」を拒否するため
#    icacls で継承を切り、現在のユーザーだけにアクセス許可を付け直す。
function Protect-KeyFile($path) {
    if (-not (Test-Path $path)) { return }
    if ($DryRun) { Dry "icacls 制限 $path"; return }
    icacls $path /inheritance:r              | Out-Null  # 継承された ACL を全削除
    icacls $path /grant:r "${env:USERNAME}:F" | Out-Null  # 本人のみフルコントロール
    # 既定で付く緩いグループを念のため除去 (無くてもエラーにしない)
    foreach ($p in @('BUILTIN\Users', 'BUILTIN\Administrators', 'NT AUTHORITY\Authenticated Users')) {
        icacls $path /remove:g "$p" 2>$null | Out-Null
    }
    Log "鍵 ACL を本人のみに制限: $path"
}

$AgeKey = Join-Path $env:USERPROFILE '.config\sops\age\keys.txt'
if (Test-Path $AgeKey) { Protect-KeyFile $AgeKey }
else { Err "age 秘密鍵 ($AgeKey) が未配置 — Bitwarden 等から手動で配置してください" }

$SshPriv = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
if (Test-Path $SshPriv) { Protect-KeyFile $SshPriv }
else { Err "SSH 秘密鍵 ($SshPriv) が未配置 — Bitwarden 等から配置後に本スクリプト再実行で ACL 設定" }

# 5.5 Windows OpenSSH Authentication Agent を auto start。
#     WSL 側 (nix/home/wsl.nix) で npiperelay 経由 socat フォワードして Windows
#     ssh-agent を共有する仕組みの前提。Set-Service は管理者要なので非管理時は
#     warn 留め (鍵単発利用なら省略可)。
$sshAgent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($sshAgent) {
    if ($DryRun) {
        Dry "Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent"
    } else {
        try {
            if ($sshAgent.StartType -ne 'Automatic') { Set-Service ssh-agent -StartupType Automatic }
            if ($sshAgent.Status   -ne 'Running')   { Start-Service ssh-agent }
            Log "ssh-agent: $((Get-Service ssh-agent).Status) / $((Get-Service ssh-agent).StartType)"
        } catch {
            Err "ssh-agent サービス起動失敗 (管理者で再実行): $($_.Exception.Message)"
        }
    }
}

# 6. git global config (gh/git は winget で別途 install されてる前提)
if (Get-Command git -ErrorAction SilentlyContinue) {
    if ($DryRun) {
        Dry "git config --global user.name $GitUser / user.email $GitEmail / init.defaultBranch main / pull.rebase true / push.autoSetupRemote true"
    } else {
        git config --global user.name $GitUser
        git config --global user.email $GitEmail
        git config --global init.defaultBranch main
        git config --global pull.rebase true
        git config --global push.autoSetupRemote true
        Log 'git global config 設定済'
    }
}

# 7. プライバシー / 標準機能の declarative 適用 (Win11Debloat + WinUtil)
#    - Win11Debloat: CLI 完結 (引数は windows/privacy/win11debloat-args.txt)
#    - WinUtil: GUI 起動 (設定は windows/privacy/winutil-config.json を Import)
#    -SkipPrivacy で個別実行 (just win-privacy) に振替可能。
if (-not $SkipPrivacy) {
    $applyPs1 = Join-Path $WindowsDir 'privacy\apply.ps1'
    if (Test-Path $applyPs1) {
        if ($DryRun) {
            & $applyPs1 -DryRun
        } else {
            Log 'プライバシー適用 (Win11Debloat + WinUtil) — skip するには -SkipPrivacy'
            & $applyPs1
        }
    } else {
        Err "$applyPs1 が無い (skip)"
    }
} else {
    Log 'SkipPrivacy 指定: just win-privacy で後から適用可'
}

# 8. キーマップ — SharpKeys (Scancode Map) + AHK Startup
#    SharpKeys は管理者必須 + 反映に再起動が要る。AHK は Startup フォルダに symlink すれば
#    次回ログインから自動起動。今走らせるなら手動で .ahk を実行。
if (-not $SkipKeymap) {
    # SharpKeys: 物理キー remap (CapsLock → Ctrl)
    $skApply = Join-Path $WindowsDir 'sharpkeys\apply.ps1'
    if (Test-Path $skApply) {
        if ($DryRun) {
            & $skApply -DryRun
        } else {
            Log 'SharpKeys 適用 (再起動で反映) — skip するには -SkipKeymap'
            try { & $skApply }
            catch { Err "SharpKeys 適用失敗 (管理者要): $($_.Exception.Message)" }
        }
    } else {
        Log "$skApply が無い (skip)"
    }
    # AHK: Startup フォルダに symlink (組合せ remap = Emacs ショートカット + Copilot 保険)
    $ahkSrc = Join-Path $WindowsDir 'autohotkey\keymap.ahk'
    $ahkDst = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\dotfiles-keymap.ahk'
    if (Test-Path $ahkSrc) {
        New-DotfilesLink -Source $ahkSrc -Destination $ahkDst -Label 'AHK keymap (Startup)'
    } else {
        Log "$ahkSrc が無い (skip)"
    }
} else {
    Log 'SkipKeymap 指定: just win-keymap で後から適用可'
}

# 9. ロケール / 言語 — User Language List / System Locale / Home Location
if (-not $SkipLocale) {
    $localeApply = Join-Path $WindowsDir 'locale\apply.ps1'
    if (Test-Path $localeApply) {
        if ($DryRun) {
            & $localeApply -DryRun
        } else {
            Log 'Locale 適用 (en-US UI / UTF-8 / SKK のみ / 再起動で完全反映) — skip するには -SkipLocale'
            try { & $localeApply }
            catch { Err "Locale 適用失敗: $($_.Exception.Message)" }
        }
    } else {
        Log "$localeApply が無い (skip)"
    }
} else {
    Log 'SkipLocale 指定: just win-locale で後から適用可'
}

Log ''
Log '完了! 新しい PowerShell を開いてください。'
Log ''
Log '追加で手動でやること:'
Log '  - WSL2 を入れる場合: wsl --install -d Ubuntu (管理者で別 PowerShell)'
Log '  - winget/apps.json に install したい app を追記して再実行'
