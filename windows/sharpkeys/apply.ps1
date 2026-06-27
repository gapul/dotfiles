# Windows 物理キー remap (SharpKeys 同等、レジストリ直書き)
# Scancode Map (HKLM) を declarative に書き換える。
# SharpKeys GUI 不要 / .skl ファイル不要で再現可能。.skl は人間が読む参照用。
#
# 仕様: HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout\Scancode Map
#   Header(8B 0) + Version(4B 0) + Count(4B: mappings+1) +
#   Each mapping (4B: dst_scancode(2B LE) + src_scancode(2B LE)) +
#   Terminator(4B 0)
#
# 反映には **再起動 (またはサインアウト)** が必要 (Windows の起動時 layout 読込)。
# 関連: windows/sharpkeys/keymap.skl (人間可読版)、windows/autohotkey/keymap.ahk (組合せ remap)
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Clear   # remap を全削除して standard layout に戻す
)

$ErrorActionPreference = 'Stop'
$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'

function Log($msg) { Write-Host "[sharpkeys] $msg"      -ForegroundColor Blue }
function Dry($msg) { Write-Host "[sharpkeys][dry] $msg" -ForegroundColor DarkYellow }
function Err($msg) { Write-Host "[sharpkeys] $msg"      -ForegroundColor Red }

# ─── 管理者チェック (DryRun は除外) ───
# HKLM\SYSTEM\CurrentControlSet 書込みは管理者要。非管理者で起動された場合は
# UAC 起こして elevate した子プロセスに引き継ぐ。
if (-not $DryRun) {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log '管理者権限が必要です。UAC promptで再起動します...'
        $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($Clear) { $childArgs += '-Clear' }
        Start-Process pwsh -Verb RunAs -ArgumentList $childArgs
        exit
    }
}

# Clear モード: remap を全削除
if ($Clear) {
    if ($DryRun) {
        Dry "Remove-ItemProperty $RegPath\Scancode Map"
    } else {
        try {
            Remove-ItemProperty -Path $RegPath -Name 'Scancode Map' -ErrorAction Stop
            Log 'Scancode Map を削除しました (再起動で適用)'
        } catch {
            Err "削除失敗 (もともと無い可能性): $($_.Exception.Message)"
        }
    }
    return
}

# ─── 適用する remap ───
# 配列の各要素は { Source = '<scancode hex>'; Dest = '<scancode hex>' }
# scancode は 16 進文字列 ('3A' = CapsLock、'1D' = Left Ctrl、'E01D' = Right Ctrl、'E05C' = Copilot 候補)
$Mappings = @(
    @{ Source = '3A';   Dest = '1D';   Comment = 'CapsLock -> Left Ctrl' }
    # Copilot key は実機の scancode 調査後に有効化:
    # @{ Source = 'E05C'; Dest = 'E01D'; Comment = 'Copilot -> Right Ctrl (要実機検証)' }
)

# scancode hex (e.g. '3A' or 'E05C') を 2 バイト little-endian に変換
function ConvertTo-ScancodeBytes([string]$hex) {
    $hex = $hex.PadLeft(4, '0')   # '3A' -> '003A', 'E05C' -> 'E05C'
    $hi = [Convert]::ToByte($hex.Substring(0, 2), 16)
    $lo = [Convert]::ToByte($hex.Substring(2, 2), 16)
    return @($lo, $hi)
}

# バイナリ組み立て
$bytes = New-Object System.Collections.Generic.List[byte]
1..8  | ForEach-Object { $bytes.Add(0) }              # Header: 8 bytes
1..4  | ForEach-Object { $bytes.Add(0) }              # Version: 4 bytes
$count = $Mappings.Count + 1                          # entries + terminator
$bytes.Add(($count -band 0xFF))
$bytes.Add((($count -shr 8)  -band 0xFF))
$bytes.Add((($count -shr 16) -band 0xFF))
$bytes.Add((($count -shr 24) -band 0xFF))
foreach ($m in $Mappings) {
    (ConvertTo-ScancodeBytes $m.Dest)   | ForEach-Object { $bytes.Add($_) }
    (ConvertTo-ScancodeBytes $m.Source) | ForEach-Object { $bytes.Add($_) }
    Log "Mapping: $($m.Comment) (src=$($m.Source) -> dst=$($m.Dest))"
}
1..4  | ForEach-Object { $bytes.Add(0) }              # Terminator: 4 bytes

if ($DryRun) {
    $hex = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    Dry "Set $RegPath\Scancode Map = $hex"
    Dry '(再起動で反映)'
} else {
    Set-ItemProperty -Path $RegPath -Name 'Scancode Map' -Value ([byte[]]$bytes.ToArray()) -Type Binary -Force
    Log "Scancode Map を書き込みました ($($Mappings.Count) mapping)"
    Log '反映には **再起動** または **サインアウト** が必要です'
}
