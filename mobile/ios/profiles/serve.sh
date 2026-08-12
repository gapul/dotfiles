#!/usr/bin/env bash
# このディレクトリの .mobileconfig を LAN に出して、iPhone の Safari から
# 開けるようにする。AirDrop でもいいが、Finder を開かずに済むぶんこちらが速い。
#
#   ./serve.sh [port]
#
# Safari で URL を開く → ダウンロード → 設定アプリの「プロファイルがダウンロード
# されました」からインストール。Safari 以外のブラウザではこの導線に乗らない。
set -euo pipefail

cd "$(dirname "$0")"
port=${1:-8000}

# 自分の LAN アドレス。tailnet 経由 (100.x) だと iPhone 側も tailnet に
# 入っている必要があるので、Wi-Fi のアドレスを優先して拾う。
ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo localhost)

shopt -s nullglob
profiles=(*.mobileconfig)
if [[ ${#profiles[@]} -eq 0 ]]; then
  echo "配る .mobileconfig がここに無い (README を参照)" >&2
  exit 1
fi

for f in "${profiles[@]}"; do
  echo "  http://${ip}:${port}/${f}"
done
echo "Ctrl-C で停止"

# .mobileconfig を text/plain で返されると Safari が中身を表示してしまうので、
# 拡張子に正しい MIME を割り当ててからサーブする。
python3 -c '
import http.server, sys
h = http.server.SimpleHTTPRequestHandler
h.extensions_map[".mobileconfig"] = "application/x-apple-aspen-config"
http.server.test(HandlerClass=h, port=int(sys.argv[1]), bind="0.0.0.0")
' "$port"
