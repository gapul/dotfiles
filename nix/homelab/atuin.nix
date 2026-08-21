# シェル履歴の同期サーバー (atuin)。tailnet 内のみ。
#
# 端末のコマンド履歴を複数端末で共有するための口。ファイル同期ではなく atuin 本体の
# 同期機構を使う。理由は競合で、履歴の SQLite を Syncthing に載せると両方の端末が
# 同じファイルを書くので必ず衝突する。atuin はレコード単位の追記型で設計されていて、
# しかも同期前にクライアント側で暗号化する (サーバーは中身を読めない)。
#
# つまり「自前でホストする」ことの意味が、他のサービスと少し違う。プライバシーは
# 暗号化で担保されているので、自前にする理由は可用性と、他人のサーバーに依存しない
# ことのほう。
#
# database.createLocally が既定で true なので、ネイティブの PostgreSQL がこの箱に
# 初めて1つ生える (今までの postgres は全部コンテナ側だった)。UNIX ソケット越しに
# 繋がるので、ポートは開かない。
#
# openRegistration は false のまま。アカウントを作るときだけ一時的に true にして
# `atuin register` し、済んだら戻す。開けっ放しにすると tailnet 内の誰でも
# アカウントを作れてしまう。
{
  services.atuin = {
    enable = true;
    # Caddy が同じ箱から叩くので loopback で足りる。
    host = "127.0.0.1";
    port = 8888;
    openRegistration = false;
  };
}
