# LINE のブリッジ。nixpkgs に services.mautrix-* のモジュールもパッケージも無いので、
# パッケージは pkgs/matrix-line.nix、モジュールは mk-matrix-bridgev2.nix で作る。
#
# ログインは Matrix 側で @linebot:gapul.net に DM して `login` を送る。LINE の
# Chrome 拡張として振る舞うため、ログインすると Chrome 拡張版 LINE は切断される。
#
# 過去ログはこのブリッジでは取れない。bridgev2 の FetchMessages が直近の数十件しか
# 返さない実装 (上流 pkg/connector/sync.go) で、LINE のサーバーにも古い履歴は無い。
# backfill の値を大きくしても取れる量は増えない。深い過去は端末のバックアップから
# 別に取り込む。
import ./mk-matrix-bridgev2.nix {
  name = "matrix-line";
  id = "line";
  title = "LINE";
  package = pkgs: pkgs.callPackage ../pkgs/matrix-line.nix { };
  port = 29340;
}
