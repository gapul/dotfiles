# Terraria の専用サーバ。ワールドはここが正で、キャラクターは各自の Steam Cloud
# (母艦では restic が Steam/userdata も拾う) に任せる。TShock のサーバーサイド
# キャラクターは使わない: 単にワールドを一箇所に置きたいだけで、持ち込みチート対策は要らない。
#
# macmini の Minecraft と違ってここに置くのは、nixpkgs の terraria-server が
# x86_64-linux 専用で、NixOS にはこのモジュールがあるから。サーバは 1 スレッドで数百 MB
# なので lazymc のように寝かせる仕組みも要らない。
#
# 到達は tailnet のみ (firewall は tailscale0 を trusted にしている)。外の友人を入れる
# ときは Minecraft と同じく playit を 7777 に向ける。ワールドは
# /var/lib/terraria/.local/share/Terraria/Worlds に自動生成され、backup.nix の /var/lib
# ごと restic に乗る。コンソールは `tmux -S /var/lib/terraria/terraria.sock attach`。
{ lib, ... }:
{
  # terraria-server は unfree (Re-Logic の再配布可バイナリ)。このホストで unfree を
  # 許すのはこれだけなので、matrix-bridges.nix の permittedInsecurePackages と同じく
  # 使うモジュールの側に置く。
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "terraria-server" ];

  services.terraria = {
    enable = true;
    port = 7777;
    maxPlayers = 8;
    # 省略すると -world が渡らず、サーバは "Choose World:" の対話プロンプトで止まったまま
    # 一度も listen しない (2026-09-26 に初回 switch で実際にそうなった)。パスを明示すると
    # -autocreate と組で無ければ作る。ディレクトリはモジュールが tmpfiles で用意する。
    worldPath = "/var/lib/terraria/.local/share/Terraria/Worlds/world.wld";
    autoCreatedWorldSize = "medium";
    messageOfTheDay = "homeserver terraria";
    # tailnet only. Anything wider goes through playit, not the LAN firewall.
    openFirewall = false;
    noUPnP = true;
  };
}
