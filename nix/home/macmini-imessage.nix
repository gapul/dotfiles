# iMessage を Matrix に繋ぐ。macmini でしかできないブリッジ。
#
# 他のブリッジ (discord / signal / meta) は homeserver に置いてある。これだけ
# こちらにあるのは、iMessage に外から叩ける API が無いため。ブリッジは
# ~/Library/Messages/chat.db を読み、送信は Messages.app を動かして行う。つまり
# 「iMessage にログイン済みの Mac」そのものが接続の実体で、Linux には置けない。
#
# ## 常駐と config は system 側
#
# launchd のジョブと config.yaml の生成は nix/hosts/macmini-imessage.nix にある。
# home-manager の launchd.agents は必ず /bin/sh で包むので、macOS 26 ではフルディスク
# アクセスが /bin/sh に対して判定されて効かない。理由と実測はあちらの冒頭に。
# ここに残るのは、ビルドと署名済みの安定した場所への配置だけ。
#
# ## フルディスクアクセス
#
# chat.db は TCC で守られているので、許可が要る。store のパスを直接 launchd に
# 書くと、ブリッジを更新するたびに別物と見なされて許可が切れる。sunshine と同じく
# 自己署名の identity で署名して ~/.local/libexec/tcc/ に置き、そこを指す。
# 署名の要件式から cdhash が落ちるので、中身が変わっても同じものとして扱われる。
#
# 許可の付与そのものは一度だけ人の手が要る (システム設定 > プライバシーとセキュリティ
# > フルディスクアクセス に ~/.local/libexec/tcc/mautrix-imessage を足す)。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # olm は insecure の印が付いている。homeserver 側 (nix/homelab/matrix-bridges.nix) と
  # 同じ判断で許可する: 使われるのはブリッジ側の E2EE だけで、そこは有効にしていない。
  # ここで nixpkgs を import し直すのは、home-manager から host の nixpkgs.config に
  # 手が届かないため。E2EE を入れるときは両方まとめて判断し直すこと。
  pkgsWithOlm = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.permittedInsecurePackages = [ "olm-3.2.16" ];
  };
  bridge = pkgsWithOlm.callPackage ../pkgs/mautrix-imessage.nix { };
in
{
  home.activation.tccStableIMessage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${../../configs/bin/tcc-stable-binary} \
      ${bridge}/bin/mautrix-imessage mautrix-imessage || true
  '';
}
