#!/usr/bin/env bash
# nix/mobile/ios-profiles.nix のメール用プロファイル (sakura-mail / homelab-mail) に sops から
# パスワードを差し込んで端末に入れる。生成物はパスワード無しのまま store に置き、平文入りの
# ものは一時ディレクトリにだけ作って、終わったら消す。
#
#   ./mail.sh mac          この Mac で開く → システム設定「プライバシーとセキュリティ」→
#                          「プロファイル」で承認すると Mail.app に口座が入る
#   ./mail.sh serve [port] iPhone / iPad 向けに tailnet 上で配る。Safari で URL を開く →
#                          設定アプリの「プロファイルがダウンロードされました」から承認
#
# serve は serve.sh と違って LAN には出さない。中身がパスワードなので tailnet の IP にだけ
# bind し、推測できないパスの下に置く (ルートの一覧も塞ぐ)。
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
mode=${1:-}
port=${2:-8000}
case $mode in
  mac | serve) ;;
  *)
    echo "usage: $0 mac | serve [port]" >&2
    exit 2
    ;;
esac

out=$(nix build "${repo}/nix#ios-profiles" --no-link --print-out-paths)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
token=$(openssl rand -hex 16)
mkdir -p "$work/$token"
: > "$work/index.html"

# 口座はプロファイル側の IncomingMailServerUsername で見分ける。パスワードは argv に
# 載せない (ps で見える) ため、差し込みは python の中で sops を呼んで済ませる。
python3 -I - "$repo" "$out" "$work/$token" <<'EOF'
import plistlib, subprocess, sys
repo, src, dst = sys.argv[1:]

def secret(file, path):
    return subprocess.run(
        ["sops", "-d", "--extract", path, f"{repo}/secrets/{file}"],
        check=True, capture_output=True, text=True,
    ).stdout

def password(user):
    if user in ("gmail", "work", "school"):
        return secret("mail.yaml", f'["stalwart"]["{user}"]')
    if user == "gapul@gapul.sakura.ne.jp":
        return secret("common.yaml", '["sakura"]["mail_password"]')
    sys.exit(f"mail.sh: {user} のパスワードの在処を知らない (mail.sh に足す)")

for name in ("sakura-mail", "homelab-mail"):
    with open(f"{src}/{name}.mobileconfig", "rb") as f:
        profile = plistlib.load(f)
    for payload in profile["PayloadContent"]:
        pw = password(payload["IncomingMailServerUsername"])
        payload["IncomingPassword"] = pw
        payload["OutgoingPassword"] = pw
    with open(f"{dst}/{name}.mobileconfig", "wb") as f:
        plistlib.dump(profile, f)
EOF

if [ "$mode" = mac ]; then
  for f in "$work/$token"/*.mobileconfig; do
    open "$f"
  done
  echo "システム設定 → プライバシーとセキュリティ → プロファイル で承認する。"
  read -r -p "承認が済んだら Enter (一時ファイルを消す) "
  exit 0
fi

ip=$(tailscale ip -4 2>/dev/null | head -1)
if [ -z "$ip" ]; then
  echo "tailscale の IP が取れない。tailnet に入ってから再実行する。" >&2
  exit 1
fi
for f in "$work/$token"/*.mobileconfig; do
  echo "  http://${ip}:${port}/${token}/$(basename "$f")"
done
echo "Ctrl-C で停止 (一時ファイルも消える)"

# .mobileconfig を text/plain で返すと Safari が中身を表示してしまい、
# インストールの導線に乗らない。拡張子に正しい MIME を割り当ててから配る。
cd "$work"
python3 -I -c '
import http.server, sys
h = http.server.SimpleHTTPRequestHandler
h.extensions_map[".mobileconfig"] = "application/x-apple-aspen-config"
http.server.test(HandlerClass=h, port=int(sys.argv[1]), bind=sys.argv[2])
' "$port" "$ip"
