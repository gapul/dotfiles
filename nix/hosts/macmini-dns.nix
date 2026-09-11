# 家の DNS の副。主は homeserver の blocky (homelab/blocky.nix)。
#
# ## なぜ 2 台目が要るか
#
# ルーター (192.168.116.254) は DHCP で自分自身を DNS として配っていて、その転送が
# 止まった。LAN の端末は名前を引けないのに、blocky は隣で正常に答えていた
# (2026-09-11 に確認)。宛先をルーターから blocky に移せばその遠回りは消えるが、
# 今度は blocky が落ちた時点で家中の名前解決が止まる。DHCP は 2 つ配れるので、
# 2 台目を置いてから移す。
#
# この機械を選ぶのは、常時電源で、同じ LAN にいて、すでに宣言管理下にあるから。
#
# ## NixOS 側と何が違うか
#
# nix-darwin に services.blocky は無いので、設定ファイルを書いて launchd の
# デーモンとして起こす。53 番は 1024 未満なので root で走らせる (エージェントでは
# 足りない)。設定の中身は lib/blocky-settings.nix で homeserver と共有していて、
# 差は待ち受けアドレスだけ。
{ pkgs, ... }:
let
  # このホストの LAN アドレス。ルーターの DHCP 予約で固定してある。
  lanAddress = "192.168.116.100";

  settings = import ../lib/blocky-settings.nix {
    listen = "127.0.0.1:53,${lanAddress}:53";
  };

  # blocky は YAML を読む。JSON は YAML の部分集合なので、そのまま渡せる。
  configFile = pkgs.writeText "blocky.yml" (builtins.toJSON settings);

  # macOS のアプリケーションファイアウォールは、素性を知らないバイナリへの着信を黙って
  # 落とす。nix のバイナリは ad-hoc 署名なので毎回それに当たり、ループバックからは引ける
  # のに LAN からは無応答、という一番わかりにくい壊れ方をする (ComfyUI の 8188 と同じ)。
  #
  # 許可は activation ではなくここで入れる。ALF は「このバイナリへの着信を許すか」を
  # プロセスの起動時に見るので、順序がすべてになる。activation 側に置くと、許可を足す
  # 処理と launchd がデーモンを起こす処理の前後関係が保証されず、実際 2026-09-11 の
  # 初回デプロイでは許可が入っているのに LAN から無応答のままだった (手で起動し直して
  # 直った)。起動の直前に自分の store path を入れれば、順序も更新も考えなくていい。
  launch = pkgs.writeShellScript "blocky-with-firewall" ''
    fw=/usr/libexec/ApplicationFirewall/socketfilterfw
    if [ -x "$fw" ]; then
      "$fw" --add ${pkgs.blocky}/bin/blocky >/dev/null 2>&1 || true
      "$fw" --unblockapp ${pkgs.blocky}/bin/blocky >/dev/null 2>&1 || true
    fi
    exec ${pkgs.blocky}/bin/blocky --config ${configFile}
  '';
in
{
  launchd.daemons.blocky = {
    serviceConfig = {
      ProgramArguments = [ "${launch}" ];
      RunAtLoad = true;
      KeepAlive = true;
      # 上流が落ちている間に再起動を繰り返しても意味がないので少し置く。
      ThrottleInterval = 30;
      StandardOutPath = "/var/log/blocky.log";
      StandardErrorPath = "/var/log/blocky.log";
    };
  };
}
