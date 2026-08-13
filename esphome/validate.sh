#!/usr/bin/env bash
# ESPHome の設定が構文として通るかを実機なしで確かめる。
#
# 実物の secrets.yaml は repo に無いので、雛形を使って一時ディレクトリで検証する。
# 手元の secrets.yaml があればそちらを優先する (本物の値でも通ることを見るため)。
set -euo pipefail

cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

cp -R ./common ./*.yaml "$tmp/"
if [[ -f secrets.yaml ]]; then
  cp secrets.yaml "$tmp/"
else
  cp secrets.example.yaml "$tmp/secrets.yaml"
fi

for f in "$tmp"/*.yaml; do
  case "$(basename "$f")" in
  secrets.yaml | secrets.example.yaml) continue ;;
  esac
  echo "━━━ $(basename "$f") ━━━"
  # esphome は検証エラーを stdout に出す。捨てると黙って失敗するので、
  # 一度受けてから失敗したときだけ見せる。
  if out=$(cd "$tmp" && esphome config "$(basename "$f")" 2>&1); then
    echo "  ok"
  else
    echo "$out" | tail -30
    fail=1
  fi
done

exit "$fail"
