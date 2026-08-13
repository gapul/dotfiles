#!/usr/bin/env bash
# apps.sh status の自己チェック。偽の ideviceinstaller を PATH に置くので実機は要らない。
# verify は本物の App Store を叩くのでここでは回さない (ネットワークに依存させない)。
set -euo pipefail

cd "$(dirname "$0")"
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
fail=0

kept=$(grep -vE '^[[:space:]]*(#|$)' apps.tsv | head -1 | cut -f1)
declared_count=$(grep -cvE '^[[:space:]]*(#|$)' apps.tsv)

# 本物の出力は 1 行目がヘッダの CSV。ヘッダを落とし損ねると EXTRA に化けるので、
# そこも含めて真似る。
cat >"$stub/ideviceinstaller" <<EOF
#!/usr/bin/env bash
echo "CFBundleIdentifier, CFBundleVersion, CFBundleDisplayName"
echo "${kept}, \"1.0\", \"Kept\""
echo "com.example.undeclared, \"1.0\", \"Undeclared\""
EOF
chmod +x "$stub/ideviceinstaller"
export PATH="$stub:$PATH"

check() {
  local name=$1 want=$2 got=$3
  if [[ $want == "$got" ]]; then
    echo "ok: $name ($got)"
  else
    echo "FAIL: $name — 期待 $want / 実際 $got" >&2
    fail=1
  fi
}

out=$(./apps.sh status) && rc=0 || rc=$?
check "MISSING 数" "$((declared_count - 1))" "$(grep -c MISSING <<<"$out" || true)"
check "EXTRA 数" "1" "$(grep -c EXTRA <<<"$out" || true)"
check "MISSING があれば exit 1" "1" "$rc"

exit "$fail"
