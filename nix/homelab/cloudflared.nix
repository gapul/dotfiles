# Cloudflare トンネル。gapul.net の3つのホスト名を外から入れるための入口で、
# 2026-08-12 まで Raspberry Pi の docker で動いていた。
#
# ここへ移した理由。宛先はどれもこの箱の中のサービスなので、別の箱に置くと
# 「homeserver は生きているのにトンネルだけ旧 IP を向いている」という壊れ方ができて
# しまう。実際それで Matrix の federation が一日落ちていた。homeserver が落ちたときに
# トンネルも落ちるのは損失ではない。前に出すものが同時に落ちているので。
#
# トンネルは作り直した。元の homelab-pi は Cloudflare 側に ingress を持つ
# 「リモート管理」で、cloudflared は起動時にそれを取ってきてローカルの設定を捨てる
# (実測した。ローカルに書いた alert の宛先が無視され、Pi の docker 内でしか解決
# しない http://ntfy:80 を引き続き掴んでいた)。API では config_src を後から変えられ
# なかったので、config_src=local で新規に作って CNAME を差し替えてある。これで下の
# ingress がそのまま効く。
#
# 資格情報は /var/lib/secrets/cloudflared-homeserver.json。{AccountTag, TunnelID,
# TunnelSecret} の3つで、トンネルの token を base64 デコードすれば組み直せる。
{
  services.cloudflared = {
    enable = true;
    tunnels."3e0ea569-07c5-4d37-a18f-e7295083ed83" = {
      credentialsFile = "/var/lib/secrets/cloudflared-homeserver.json";
      ingress = {
        # Conduit。federation はここだけを通る。
        "matrix.gapul.net" = "http://127.0.0.1:6167";
        # ntfy。push はアプリ通知用、alert は unified-calendar の worker が
        # watchdog トピックへ投げてくる先で、Pi 側の ntfy にいたユーザとトークンは
        # この箱の ntfy へ移してある。
        "push.gapul.net" = "http://127.0.0.1:8082";
        "alert.gapul.net" = "http://127.0.0.1:8082";
      };
      # 知らないホスト名は 404。Pi 側の設定もこうなっていた。
      default = "http_status:404";
    };
  };
}
