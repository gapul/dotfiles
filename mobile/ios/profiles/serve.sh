#!/usr/bin/env bash
# nix/mobile/ios-profiles.nix から生成した .mobileconfig を LAN に出して、
# iPhone の Safari から開けるようにする。AirDrop でもいいが、Finder を
# 開かずに済むぶんこちらが速い。
#
#   ./serve.sh [port]
#
# Safari で URL を開く → ダウンロード → 設定アプリの「プロファイルがダウンロード
# されました」からインストール。Safari 以外のブラウザではこの導線に乗らない。
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
port=${1:-8000}

# 配るのは常に nix が生成したものだけ。手で置いたファイルを混ぜると、端末に
# 入っているプロファイルの出所が宣言から追えなくなる。
out=$(nix build "${repo}/nix#ios-profiles" --no-link --print-out-paths)

ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo localhost)
for f in "$out"/*.mobileconfig; do
  echo "  http://${ip}:${port}/$(basename "$f")"
done
echo "Ctrl-C で停止"

# .mobileconfig を text/plain で返すと Safari が中身を表示してしまい、
# インストールの導線に乗らない。拡張子に正しい MIME を割り当ててから配る。
cd "$out"
python3 -c '
import http.server, sys
h = http.server.SimpleHTTPRequestHandler
h.extensions_map[".mobileconfig"] = "application/x-apple-aspen-config"
http.server.test(HandlerClass=h, port=int(sys.argv[1]), bind="0.0.0.0")
' "$port"
