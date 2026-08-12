#!/usr/bin/env bash
# apply.sh の自己チェック。偽の adb を PATH に置いて --dry-run を回し、
# settings.conf の宣言行がひとつ残らず差分として出ることを確かめる。
#
# 見張っているのは主にループの stdin: ループ内の adb から </dev/null を外すと
# adb が宣言ファイルを読み尽くし、1 行目しか処理されずにここが落ちる。
set -euo pipefail

cd "$(dirname "$0")"
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT

cat >"$stub/adb" <<'EOF'
#!/usr/bin/env bash
# 本物の adb shell は stdin を読み切るので、そこも真似る (これが無いと
# </dev/null の有無で挙動が変わらず、テストが素通りする)。
case "$*" in
  devices) printf 'List of devices attached\nemulator-5554\tdevice\n' ;;
  "shell settings get "*)
    cat >/dev/null
    echo null
    ;;
  "shell pm list packages --user 0")
    cat >/dev/null
    echo "package:com.example.absent"
    ;;
  *) cat >/dev/null ;;
esac
EOF
chmod +x "$stub/adb"

# apply.sh 自体の stdin は閉じておく。ループの外の adb が端末の入力を待って
# 止まらないようにするためで、ループの中の stdin (宣言ファイル) には影響しない。
out=$(PATH="$stub:$PATH" ./apply.sh --dry-run </dev/null)
got=$(grep -c -- '->' <<<"$out" || true)
want=$(grep -cvE '^\s*(#|$)' settings.conf)

if [[ $got -ne $want ]]; then
  echo "$out"
  echo "FAIL: settings.conf の宣言 ${want} 行に対し差分は ${got} 行しか出ていない" >&2
  exit 1
fi
echo "ok: settings ${got} 行"
