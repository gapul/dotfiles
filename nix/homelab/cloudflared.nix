# Cloudflare トンネル。gapul.net の3つのホスト名を外から入れるための入口で、
# 2026-08-12 まで Raspberry Pi の docker で動いていた。
#
# ここへ移した理由は2つ。宛先はどれもこの箱の中のサービスなので、別の箱に置くと
# 「homeserver は生きているのにトンネルだけ旧 IP を向いている」という壊れ方ができて
# しまう。実際それで Matrix の federation が一日落ちていた。もうひとつは、ingress が
# Cloudflare 側のリモート設定に置かれていてリポジトリの外だったこと。credentialsFile を
# 使うと設定はこのファイルが正になり、Cloudflare 側の設定は参照されない。
#
# 資格情報は /var/lib/secrets/cloudflared-homelab.json。tunnel token を base64
# デコードして {AccountTag, TunnelID, TunnelSecret} に組み直したもの。DNS の CNAME は
# トンネル ID を指しているので、動かす場所を変えても DNS は触らなくていい。
{
  services.cloudflared = {
    enable = true;
    tunnels."8fe36752-bc96-40d6-9036-e706102fb79d" = {
      credentialsFile = "/var/lib/secrets/cloudflared-homelab.json";
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
