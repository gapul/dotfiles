#!/usr/bin/env bash
#
# NixOS デュアルブート インストール補助 (HP ノート, nixos-laptop)。
# Windows を温存しつつ、空き領域に作った Linux パーティションを LUKS 暗号化し、
# 既存 Windows ESP を流用してマウント → hardware 設定生成 → flake 取り込みまでを安全に行う。
#
# 想定: NixOS minimal ISO の live 環境で root として実行 (docs/NIXOS_DUALBOOT.md Phase 4-6 を自動化)。
# 事前: Windows 側で C: を縮小し未割り当てを作成 → `cfdisk` で空き領域に
#       「Linux filesystem」パーティションを 1 つ作っておくこと (本スクリプトは作成しない)。
#
# 使い方:
#   install-nixos-laptop.sh <root-partition> <esp-partition>
#   例:  install-nixos-laptop.sh /dev/nvme0n1p5 /dev/nvme0n1p1
#
# 安全策: デバイス取り違え / Windows(NTFS)・ESP の誤消去を機械的に拒否し、
#         破壊操作の前に対象デバイス名のタイプ確認を求める。最終の nixos-install は
#         自動実行せず、確認用にコマンドを表示する (パスワード設定を手動で行うため)。

set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/gapul/dotfiles.git}"
CRYPT_NAME="cryptroot"                          # hosts/nixos-laptop.nix の crypttabExtraOpts と一致させること
ESP_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" # EFI System Partition の PARTTYPE

log() { printf '\033[1;34m[install-nixos]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[install-nixos]\033[0m %s\n' "$*" >&2; }
die() {
  err "$*"
  exit 1
}

# 0. 前提チェック
[ "$(id -u)" -eq 0 ] || die "root で実行してください (sudo -i)。"
ROOT_PART="${1:-}"
ESP_PART="${2:-}"
[ -n "$ROOT_PART" ] && [ -n "$ESP_PART" ] || die "使い方: $0 <root-partition> <esp-partition>"
for c in cryptsetup mkfs.ext4 lsblk blkid nixos-generate-config git; do
  command -v "$c" >/dev/null || die "$c が無い (git は 'nix-shell -p git' で入れてから再実行)。"
done

# 1. デバイスの素性確認
[ -b "$ROOT_PART" ] || die "$ROOT_PART はブロックデバイスではない。"
[ -b "$ESP_PART" ] || die "$ESP_PART はブロックデバイスではない。"

root_fstype=$(blkid -o value -s TYPE "$ROOT_PART" 2>/dev/null || true)
esp_fstype=$(blkid -o value -s TYPE "$ESP_PART" 2>/dev/null || true)
esp_parttype=$(lsblk -dno PARTTYPE "$ESP_PART" 2>/dev/null || true)

# ROOT が Windows/ESP を指していないか (NTFS / vfat は拒否)
case "$root_fstype" in
ntfs) die "$ROOT_PART は NTFS (= Windows 領域)。絶対に消さない。対象パーティションを間違えている。" ;;
vfat) die "$ROOT_PART は vfat (= ESP の可能性)。root には指定しない。" ;;
esac
if [ -n "$root_fstype" ]; then
  err "警告: $ROOT_PART には既存 FS ($root_fstype) がある。これから LUKS で上書き=全消去する。"
fi

# ESP が本当に ESP か
if [ "$esp_parttype" != "$ESP_GUID" ] && [ "$esp_fstype" != "vfat" ]; then
  die "$ESP_PART は ESP に見えない (parttype=$esp_parttype, fstype=$esp_fstype)。ESP を間違えている。"
fi

# 2. 最終確認 (タイプ確認)
echo
lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME,MOUNTPOINT "$(lsblk -no PKNAME "$ROOT_PART" | head -1 | sed 's#^#/dev/#')" || lsblk
echo
err "次を実行する:"
err "  - $ROOT_PART を LUKS 暗号化して ext4(label=nixos) で全消去"
err "  - $ESP_PART は ESP として /mnt/boot にマウント (フォーマットしない)"
printf '本当に %s を消去してよければ、デバイス名を正確に入力: ' "$ROOT_PART"
read -r confirm
[ "$confirm" = "$ROOT_PART" ] || die "入力が一致しない。中止。"

# 3. LUKS 暗号化 + ext4
log "luksFormat $ROOT_PART (パスフレーズを設定。後で TPM2 自動解錠も登録可)"
cryptsetup luksFormat --type luks2 "$ROOT_PART"
log "luksOpen → /dev/mapper/$CRYPT_NAME"
cryptsetup open "$ROOT_PART" "$CRYPT_NAME"
log "mkfs.ext4 (label=nixos)"
mkfs.ext4 -L nixos "/dev/mapper/$CRYPT_NAME"

# 4. マウント (ESP は流用、フォーマットしない)
log "mount /mnt + ESP を /mnt/boot へ"
mount "/dev/mapper/$CRYPT_NAME" /mnt
mkdir -p /mnt/boot
mount "$ESP_PART" /mnt/boot

# 5. hardware 設定生成
log "nixos-generate-config --root /mnt"
nixos-generate-config --root /mnt

# cryptroot / fileSystems の自動検出を軽く検証
if ! grep -q "$CRYPT_NAME" /mnt/etc/nixos/hardware-configuration.nix; then
  err "警告: hardware-configuration.nix に $CRYPT_NAME が見当たらない。LUKS 検出を確認すること。"
fi

# 6. flake 取り込み + hardware を所定名へ
log "dotfiles を clone して hardware を nix/hosts/nixos-laptop-hardware.nix へ"
git clone "$DOTFILES_REPO" /mnt/etc/nixos/dotfiles
cp /mnt/etc/nixos/hardware-configuration.nix \
  /mnt/etc/nixos/dotfiles/nix/hosts/nixos-laptop-hardware.nix
git -C /mnt/etc/nixos/dotfiles add -A # flake は git 追跡ファイルのみ含む

# 7. 次の手順を表示 (最終 install は手動。Secure Boot はまだ OFF)
cat <<'EOF'

──────────────────────────────────────────────
ここまで OK。最後のインストールは手動で実行してください
(root パスワード・ユーザーパスワードを対話設定するため):

  nixos-install --flake /mnt/etc/nixos/dotfiles/nix#nixos-laptop
  nixos-enter --root /mnt -c 'passwd gapul'
  reboot   # USB を抜く

この時点では BIOS の Secure Boot は OFF のまま。
初回起動後に sbctl で鍵登録 → Secure Boot ON → TPM2 登録
(docs/NIXOS_DUALBOOT.md Phase 8 / 付録A)。
──────────────────────────────────────────────
EOF
log "done."
