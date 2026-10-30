# Windows プライバシー / 標準機能を declarative に適用する orchestrator。
# - Win11Debloat:   upstream.psd1 で固定した版を SHA256 照合して、win11debloat-args.txt の引数で実行
# - CustomApps:     win11debloat-customapps.txt 列挙の UWP を Remove-AppxPackage 直接実行
# - OneDrive:       公式 uninstaller
# - WinUtil:        upstream.psd1 で固定した版を SHA256 照合して、winutil-config.json を headless 適用
# - Baseline:       baseline.psd1 のレジストリ / サービス / タスク (ツールの版に依存しない部分、最後に適用)
#
# 管理者 PowerShell で実行 (UWP 削除 / レジストリ HKLM / Set-Service 等)。PowerShell 5.1 / 7 どちらでも動く。
# -DryRun で副作用なしの計画表示。適用後の確認は verify.ps1 (just win-privacy-verify)。
#
# 関連: windows/privacy/README.md
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipWinUtil,        # WinUtil の headless 適用を skip
    [switch]$SkipWin11Debloat,   # Win11Debloat 実行 + OneDrive uninstall を skip
    [switch]$SkipCustomApps,     # カスタム UWP 削除 (customapps.txt) を skip
    [switch]$SkipBaseline        # baseline.psd1 の適用を skip
)

$ErrorActionPreference = 'Stop'
$PrivacyDir = $PSScriptRoot
if (-not $PrivacyDir) {
    $PrivacyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Log($msg) { Write-Host "[privacy] $msg"      -ForegroundColor Blue }
function Dry($msg) { Write-Host "[privacy][dry] $msg" -ForegroundColor DarkYellow }
# Err は失敗として数え、最後に 1 件でもあれば exit 1 にする
$script:Failures = 0
function Err($msg)  { Write-Host "[privacy] $msg"      -ForegroundColor Red; $script:Failures++ }
function Warn($msg) { Write-Host "[privacy] $msg"      -ForegroundColor Yellow }

# 外部スクリプトは Windows PowerShell 5.1 で動かす (Win11Debloat の公式 launcher も powershell.exe を使う)
$WinPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$Upstream = Import-PowerShellDataFile (Join-Path $PrivacyDir 'upstream.psd1')
$Baseline = Import-PowerShellDataFile (Join-Path $PrivacyDir 'baseline.psd1')

# ─── 0. 管理者チェック (DryRun は除外) ───
# レジストリ HKLM 書込 / UWP Provisioned 削除 / OneDrive uninstall は全部管理者要。
# 非管理者で起動された場合は UAC 起こして elevate した子プロセスに引き継ぐ。
# 子は今と同じ PowerShell (5.1 なら powershell.exe、7 なら pwsh.exe) で起動する。
if (-not $DryRun) {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log '管理者権限が必要です。UAC promptで再起動します...'
        $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($SkipWinUtil)      { $childArgs += '-SkipWinUtil' }
        if ($SkipWin11Debloat) { $childArgs += '-SkipWin11Debloat' }
        if ($SkipCustomApps)   { $childArgs += '-SkipCustomApps' }
        if ($SkipBaseline)     { $childArgs += '-SkipBaseline' }
        # 子の終了を待って exit code を引き継ぐ (just / bootstrap が失敗を検知できるように)
        $child = Start-Process (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $childArgs -Wait -PassThru
        exit $child.ExitCode
    }
    # 昇格したウィンドウは終了時に閉じるので、出力はログにも残す
    $logDir = Join-Path $env:LOCALAPPDATA 'dotfiles'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logFile = Join-Path $logDir "privacy-apply-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Start-Transcript -Path $logFile | Out-Null
}

# 追加機能の名前 (Hello.Face.20134~~~~0.0.1.0) が baseline の名前 (Hello.Face) に当たるか。
# ~~~~ より前が一致するか、その後ろに .<枝番> が付いたものを同じ機能とみなす
function Test-CapabilityName([string]$Name, [string]$Base) {
    $head = ($Name -split '~')[0]
    return ($head -eq $Base) -or ($head -like "$Base.*")
}

# 取得物の置き場。%TEMP% は昇格前のユーザー権限でも書けるので、SHA256 照合の後に
# 中身を差し替えられうる (照合したものと実行するものが一致しない)。
# Administrators と SYSTEM だけが書ける ACL を作成時点で付けたディレクトリを使う。
function New-PrivateWorkDir {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only called outside -DryRun; the script-level -DryRun mode replaces ShouldProcess.')]
    param([string]$Prefix)
    $dir = Join-Path $env:SystemRoot "Temp\$Prefix-$([guid]::NewGuid().ToString('N'))"
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-32-544', 'S-1-5-18') {   # BUILTIN\Administrators, SYSTEM
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier($sid)),
            'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        [System.IO.FileSystemAclExtensions]::Create([System.IO.DirectoryInfo]::new($dir), $acl)
    } else {
        [System.IO.Directory]::CreateDirectory($dir, $acl) | Out-Null
    }
    return $dir
}

# 固定版を取得して SHA256 を照合する。一致しなければ消して throw (実行はしない)
function Get-PinnedFile($Name, $Pin, $OutFile) {
    Log "$Name $($Pin.Version) を取得: $($Pin.Url)"
    # PS 5.1 の既定は TLS 1.0 のことがあり GitHub に弾かれる
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Pin.Url -OutFile $OutFile -UseBasicParsing
    $actual = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Pin.Sha256.ToLowerInvariant()) {
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        throw "$Name の SHA256 が upstream.psd1 と不一致 (取得 $actual / 固定 $($Pin.Sha256))。実行を中止"
    }
    Unblock-File -Path $OutFile
    Log "$Name の SHA256 一致"
}

# 子の powershell.exe に PS 7 のモジュールパスを継がせない (Win11Debloat の launcher と同じ対処)
function Invoke-WinPS([string[]]$ArgumentList) {
    $savedModulePath = $env:PSModulePath
    try {
        $env:PSModulePath = ($env:PSModulePath -split ';' | Where-Object { $_ -like '*WindowsPowerShell*' }) -join ';'
        # 出力は画面へ流す (戻り値に混ざると exit code が読めなくなる)
        & $WinPS @ArgumentList | Out-Host
        return $LASTEXITCODE
    } finally {
        $env:PSModulePath = $savedModulePath
    }
}

# ─── 0.5 Appx モジュールを Windows PowerShell 5.1 互換モードで load (PS 7 のみ) ───
# PS 7 の Appx モジュールは部分対応で、Get-AppxProvisionedPackage が
# 「クラスが登録されていません」(Class not registered) で死ぬ。
# -UseWindowsPowerShell で WinPS 5.1 経由でモジュールを取得して proxy 経由で使う。
if (-not $DryRun -and $PSVersionTable.PSVersion.Major -ge 7) {
    try {
        Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
    } catch {
        Err "Appx モジュール load 失敗 (Provisioned 削除が動かない可能性): $($_.Exception.Message)"
    }
}

# ─── 1. Win11Debloat ───
if (-not $SkipWin11Debloat) {
    $argsFile = Join-Path $PrivacyDir 'win11debloat-args.txt'
    # 空行と `#` コメントを除外 (5.1 の Get-Content default は ANSI のため -Encoding UTF8 明示)
    $debloatArgs = @(Get-Content $argsFile -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
    $pin = $Upstream.Win11Debloat
    Log "Win11Debloat $($pin.Version) 引数 ($($debloatArgs.Count) 個): $($debloatArgs -join ' ')"
    if ($DryRun) {
        Dry "取得 $($pin.Url) (sha256 $($pin.Sha256)) → 展開 → powershell.exe -File Win11Debloat.ps1 $($debloatArgs -join ' ')"
    } else {
        # Win11Debloat は multi-file プロジェクト (Scripts / Config / Assets が必要) なので
        # repo の zip を commit 固定で取得して展開し、Win11Debloat.ps1 を直接呼ぶ。
        # 公式 launcher の Get.ps1 は中で最新版を取りに行くため固定にならない。
        $work = $null
        try {
            $work = New-PrivateWorkDir 'Win11Debloat'
            $zip = Join-Path $work 'src.zip'
            Get-PinnedFile 'Win11Debloat' $pin $zip
            Expand-Archive -Path $zip -DestinationPath $work
            $script = Get-ChildItem -Path $work -Filter 'Win11Debloat.ps1' -Recurse | Select-Object -First 1
            if (-not $script) { throw 'zip に Win11Debloat.ps1 が無い' }
            Get-ChildItem -Path $script.DirectoryName -Recurse -File | Unblock-File
            Log 'Win11Debloat 実行...'
            $code = Invoke-WinPS (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script.FullName) + $debloatArgs)
            if ($code -ne 0) { Err "Win11Debloat exit code: $code" } else { Log 'Win11Debloat 完了' }
        } catch {
            Err "Win11Debloat 失敗: $($_.Exception.Message)"
        } finally {
            if ($work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
} else {
    Log 'SkipWin11Debloat: Win11Debloat を skip'
}

# ─── 1.5 カスタム UWP 削除 (Win11Debloat 標準セット外、安全側追加) ───
if (-not $SkipCustomApps) {
    $customAppsFile = Join-Path $PrivacyDir 'win11debloat-customapps.txt'
    if (-not (Test-Path $customAppsFile)) {
        Log 'win11debloat-customapps.txt が無いので skip'
    } else {
        $customApps = Get-Content $customAppsFile -Encoding UTF8 |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
        Log "カスタム UWP 削除対象 ($($customApps.Count) 個): $($customApps -join ', ')"
        foreach ($app in $customApps) {
            if ($DryRun) {
                Dry "Get-AppxPackage -Name '$app' | Remove-AppxPackage"
                Dry "Get-AppxProvisionedPackage -Online | Where DisplayName -eq '$app' | Remove-AppxProvisionedPackage"
                continue
            }
            # 現ユーザーから削除
            $pkg = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
            if ($pkg) {
                try {
                    $pkg | Remove-AppxPackage -ErrorAction Stop
                    Log "Removed (user): $app"
                } catch {
                    Err "Remove 失敗 (user): $app - $($_.Exception.Message)"
                }
            } else {
                Log "Skip (user): $app (未 install)"
            }
            # Provisioned (system プリイン) も削除 → 新規アカウントに戻らない (管理者要)
            try {
                $prov = Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                    Where-Object { $_.DisplayName -eq $app } |
                    Select-Object -First 1
                if ($prov) {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    Log "Removed (provisioned): $app"
                }
            } catch {
                # Get-AppxProvisionedPackage は管理者要。非管理者なら静かに skip
                if ($_.Exception.Message -match 'elevation') {
                    Log "Skip (provisioned): $app (管理者要)"
                } elseif ($_.Exception.Message -match 'not found') {
                    # user 側の削除と一緒に provisioned も消えていた (Edge.GameAssist など)
                    Log "Skip (provisioned): $app (既に無い)"
                } else {
                    Err "Provisioned 削除失敗: $app - $($_.Exception.Message)"
                }
            }
        }
    }
} else {
    Log 'SkipCustomApps: カスタム UWP 削除を skip'
}

# ─── 1.6 OneDrive uninstall (Win11Debloat の -DisableOnedrive は Win10 only のため代替) ───
if (-not $SkipWin11Debloat) {
    $oneDriveSetup = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($oneDriveSetup) {
        if ($DryRun) {
            Dry "Start-Process $oneDriveSetup /uninstall"
        } else {
            Log "OneDrive uninstall (Syncthing 代替前提) — $oneDriveSetup /uninstall"
            try {
                # 起動中の OneDrive を停止 → 公式 uninstaller 実行
                Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Process $oneDriveSetup -ArgumentList '/uninstall' -Wait
                Log 'OneDrive uninstall 完了'
            } catch {
                Err "OneDrive uninstall 失敗 (管理者要 / 既に削除済の可能性): $($_.Exception.Message)"
            }
        }
    } else {
        Log 'OneDrive: 既に削除済 or 未 install (skip)'
    }
}

# ─── 2. WinUtil ───
# -Config を渡すと WinUtil は GUI を出さずに選択を適用して終了する (headless run)。
# 知らない ID が 1 つでもあると何も適用せずに失敗するので、版を上げたら check-upstream.ts で確認。
if (-not $SkipWinUtil) {
    $configFile = Join-Path $PrivacyDir 'winutil-config.json'
    $pin = $Upstream.WinUtil
    # 5.1 の ConvertFrom-Json は配列を 1 オブジェクトのまま流すので ForEach-Object で展開する
    $ids = @(Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
    Log "WinUtil $($pin.Version) の適用対象 ($($ids.Count) 個): $($ids -join ', ')"
    if ($DryRun) {
        Dry "取得 $($pin.Url) (sha256 $($pin.Sha256)) → powershell.exe -File winutil.ps1 -Config $configFile"
    } else {
        $work = $null
        try {
            $work = New-PrivateWorkDir 'winutil'
            $tmpWinUtil = Join-Path $work 'winutil.ps1'
            Get-PinnedFile 'WinUtil' $pin $tmpWinUtil
            Log 'WinUtil 実行 (headless)...'
            $code = Invoke-WinPS @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmpWinUtil, '-Config', $configFile)
            # 26.10.07 は存在しない wermgr サービスを止めようとして、全 tweak 適用後も exit 1 になる
            # 失敗としては数えない (数えると apply が毎回 exit 1 になる)
            if ($code -ne 0) { Warn "WinUtil exit code: $code (上の [ERROR] 行を確認)" } else { Log 'WinUtil 完了' }
        } catch {
            Err "WinUtil 失敗: $($_.Exception.Message)"
        } finally {
            if ($work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
} else {
    Log 'SkipWinUtil: WinUtil を skip'
}

# ─── 3. Baseline (baseline.psd1) ───
# 上の 2 ツールの実装が版で変わっても、ここに書いたものは必ず入る。
# 最後に置くのは、ツールが同じキーを別の値にした場合にこちらを勝たせるため。
if (-not $SkipBaseline) {
    Log "Baseline: レジストリ $($Baseline.Registry.Count) / サービス $($Baseline.Services.Count) / タスク $($Baseline.Tasks.Count) / 追加機能 $($Baseline.Capabilities.Count)"
    foreach ($r in $Baseline.Registry) {
        if ($DryRun) { Dry "Set $($r.Path)\$($r.Name) = $($r.Value)"; continue }
        try {
            if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
            New-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -PropertyType DWord -Force | Out-Null
        } catch {
            Err "レジストリ設定失敗: $($r.Path)\$($r.Name) - $($_.Exception.Message)"
        }
    }
    foreach ($s in $Baseline.Services) {
        if ($DryRun) { Dry "Stop-Service $s; Set-Service $s -StartupType Disabled"; continue }
        if (-not (Get-Service -Name $s -ErrorAction SilentlyContinue)) { Log "Skip (service): $s (存在しない)"; continue }
        try {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled
            Log "Disabled (service): $s"
        } catch {
            Err "サービス無効化失敗: $s - $($_.Exception.Message)"
        }
    }
    foreach ($t in $Baseline.Tasks) {
        $taskPath = $t.Substring(0, $t.LastIndexOf('\') + 1)
        $taskName = $t.Substring($t.LastIndexOf('\') + 1)
        if ($DryRun) { Dry "Disable-ScheduledTask $t"; continue }
        $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) { Log "Skip (task): $t (この build に無い)"; continue }
        try {
            $task | Disable-ScheduledTask | Out-Null
            Log "Disabled (task): $t"
        } catch {
            Err "タスク無効化失敗: $t - $($_.Exception.Message)"
        }
    }
    if ($Baseline.Capabilities) {
        if ($DryRun) {
            foreach ($c in $Baseline.Capabilities) { Dry "Remove-WindowsCapability -Online -Name $c (~~~~ より前で照合)" }
        } else {
            $installed = @(Get-WindowsCapability -Online | Where-Object State -eq 'Installed')
            foreach ($c in $Baseline.Capabilities) {
                $caps = @($installed | Where-Object { Test-CapabilityName $_.Name $c })
                if (-not $caps) { Log "Skip (capability): $c (未 install)"; continue }
                foreach ($cap in $caps) {
                    try {
                        Remove-WindowsCapability -Online -Name $cap.Name | Out-Null
                        Log "Removed (capability): $($cap.Name)"
                    } catch {
                        Err "追加機能削除失敗: $($cap.Name) - $($_.Exception.Message)"
                    }
                }
            }
        }
    }
} else {
    Log 'SkipBaseline: baseline.psd1 の適用を skip'
}

Log ''
if ($script:Failures -gt 0) {
    Write-Host "[privacy] 失敗 $($script:Failures) 件 (赤い行)。" -ForegroundColor Red
} else {
    Log '完了。設定の変更を反映するには再ログイン or 再起動が必要なものがあります。'
}
Log '状態の確認: just win-privacy-verify (windows/privacy/verify.ps1)'
if (-not $DryRun) {
    Log "ログ: $logFile"
    Stop-Transcript | Out-Null
}
if ($script:Failures -gt 0) { exit 1 }
