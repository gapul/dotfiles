# iMessage を Matrix に繋ぐ。macmini でしかできないブリッジ。
#
# 他のブリッジ (discord / signal / meta) は homeserver に置いてある。これだけ
# こちらにあるのは、iMessage に外から叩ける API が無いため。ブリッジは
# ~/Library/Messages/chat.db を読み、送信は Messages.app を動かして行う。つまり
# 「iMessage にログイン済みの Mac」そのものが接続の実体で、Linux には置けない。
#
# ## Synapse との繋がり
#
# appservice なので双方向に届く必要がある。homeserver の Synapse は 0.0.0.0:8008 で
# 待っていて tailnet から入れる。こちら側の受け口も tailnet アドレスで公開するので、
# wsproxy (上流が NAT 越えのために用意しているもの) は要らない。
#
# 登録ファイルは homeserver 側の Synapse が読む必要がある。生成はこちらで行い、
# 中身を homeserver へ運ぶ手作業が一度だけ要る。他のブリッジのように
# services.mautrix-* が両側を面倒みてくれる構成にはならない (機械が別なので)。
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
  dataDir = "${config.home.homeDirectory}/.local/share/mautrix-imessage";
  stable = "${config.home.homeDirectory}/.local/libexec/tcc/mautrix-imessage";
in
{
  home.activation.tccStableIMessage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${../../configs/bin/tcc-stable-binary} \
      ${bridge}/bin/mautrix-imessage mautrix-imessage || true
  '';

  home.activation.imessageDataDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD /bin/mkdir -p ${dataDir}
  '';

  launchd.agents.mautrix-imessage = {
    enable = true;
    config = {
      # store ではなく署名済みの安定した場所を指す。理由は上の activation を参照。
      ProgramArguments = [
        stable
        "-c"
        "${dataDir}/config.yaml"
      ];
      WorkingDirectory = dataDir;
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${dataDir}/bridge.log";
      StandardErrorPath = "${dataDir}/bridge.log";
    };
  };
}
