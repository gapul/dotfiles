# 遠くの yazi から、手元 (母艦 Mac) のアプリでファイルを開く Windows 版。
# Unix 版 configs/bin/open-on-mac と同じことをする。
#
# 使い方:
#   open-on-mac.cmd <file>...                                 手元では既定アプリ
#   set "OPEN_ON_MAC_LOCAL=mpv" && open-on-mac.cmd <file>...   手元では mpv
#
# Unix 版は `--` でローカル用コマンドを区切るが、PowerShell は `--` をパーサが食うので
# こちらは環境変数で受ける。yazi の run は cmd.exe /C 実行なので `set X=Y && ...` が使える。
#
# 判定は OS ではなくセッション。SSH_CONNECTION があり、かつ母艦へのトンネル
# (ssh_config の RemoteForward 127.0.0.1:2222) が生きていれば向こうへ渡す。
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files
)

$ErrorActionPreference = 'Stop'

$Port = if ($env:OPEN_ON_MAC_PORT) { $env:OPEN_ON_MAC_PORT } else { '2222' }
$User = if ($env:OPEN_ON_MAC_USER) { $env:OPEN_ON_MAC_USER } else { 'gapul' }
$MacHost = '127.0.0.1'
$KnownHosts = Join-Path $env:USERPROFILE '.ssh\known_hosts_open_on_mac'
$SshOpts = @(
    '-p', $Port,
    '-o', 'BatchMode=yes',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', "UserKnownHostsFile=$KnownHosts"
)

if (-not $Files -or $Files.Count -eq 0) {
    Write-Host 'Usage: open-on-mac.cmd <file>...' -ForegroundColor Yellow
    exit 1
}

# 手元で開く。OPEN_ON_MAC_LOCAL があればそのコマンド、無ければ関連付けの既定アプリ。
function Open-Here {
    if ($env:OPEN_ON_MAC_LOCAL) {
        Start-Process -FilePath $env:OPEN_ON_MAC_LOCAL -ArgumentList $Files
    }
    else {
        foreach ($f in $Files) { Start-Process -FilePath $f }
    }
    exit 0
}

# 手元で動いているならトンネルを試すだけ無駄なので先に弾く。
if (-not $env:SSH_CONNECTION) { Open-Here }

& ssh @SshOpts "$User@$MacHost" 'true' 2>$null
if ($LASTEXITCODE -ne 0) { Open-Here }

# 見るためだけのコピーなので /tmp に置く。母艦の再起動で勝手に消える。
# 接続元ごとに分けて、同名ファイルを別ホストから開いても踏まないようにする。
$Dest = "/tmp/open-on-mac/$($env:COMPUTERNAME)"
# 保険の掃除。母艦で常駐しているアプリに相乗りすると open -W はそれを畳むまで返らない。
& ssh @SshOpts "$User@$MacHost" "mkdir -p '$Dest' && find '$Dest' -type f -mmin +60 -delete 2>/dev/null || true"

foreach ($f in $Files) {
    $base = Split-Path -Leaf $f
    & scp -q -P $Port -o BatchMode=yes -o "UserKnownHostsFile=$KnownHosts" -- $f "${User}@${MacHost}:$Dest/$base"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "転送に失敗: $f" -ForegroundColor Red
        continue
    }
    # ビューアを閉じたら消す。母艦側で完結させるので ssh はすぐ返る。
    & ssh @SshOpts "$User@$MacHost" "nohup sh -c \"open -W '$Dest/$base'; rm -f '$Dest/$base'\" >/dev/null 2>&1 &"
}
