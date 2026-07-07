{ ... }:
# disko 宣言的ディスクレイアウト (nixos-laptop)。
#
# ⚠️ dual-boot 安全方針: ここで管理するのは **空き領域に手動作成した単一の Linux パーティション
#    (= LUKS root) だけ**。GPT 全体・Windows・ESP には一切触れない。
#    `device` は必ずその単一パーティション (例 /dev/nvme0n1p5) を指すこと。
#    ディスク全体 (/dev/nvme0n1) や Windows/ESP を指すと破壊する。
#
# 使い方 (インストーラの live 環境):
#   1. cfdisk で空き領域に「Linux filesystem」パーティションを 1 つ作る
#   2. 下の device を実機の値に置換 (by-id 推奨。lsblk -o NAME,SIZE,FSTYPE,PATH で確認)
#   3. sudo disko --mode destroy,format,mount --flake <repo>/nix#nixos-laptop
#      → そのパーティションだけを LUKS 暗号化 + ext4 + /mnt にマウント
#   4. ESP は disko 管理外。手動で `mount <ESP> /mnt/boot` する (フォーマット禁止)
#
# enableConfig=false は flake 側 (nixos モジュール文脈) で指定する。実行時の
# fileSystems / luks.devices は生成 hardware-configuration.nix に任せ、二重定義を避ける。
{
  disko.devices.disk.cryptroot = {
    type = "disk";
    # ↓ 実機の単一 Linux パーティションに置換 (絶対にディスク全体/Windows/ESP にしない)
    device = "/dev/disk/by-id/REPLACE_WITH_ROOT_PARTITION";
    content = {
      type = "luks";
      name = "cryptroot"; # hosts/nixos-laptop.nix の crypttabExtraOpts と一致
      settings.allowDiscards = true; # SSD の TRIM を許可
      content = {
        type = "filesystem";
        format = "ext4";
        mountpoint = "/";
      };
    };
  };
}
