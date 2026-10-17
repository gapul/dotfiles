#!/usr/bin/env bash
# Check that the declarations still match the pinned upstream scripts in upstream.psd1:
# - both downloads match their SHA256
# - every argument in win11debloat-args.txt is a parameter of that Win11Debloat.ps1
# - every ID in winutil-config.json is a tweak, toggle or feature that WinUtil knows
# WinUtil's headless run refuses an unknown ID, and Win11Debloat refuses an unknown
# argument, so a stale declaration fails the whole apply. Catch it here instead.
set -euo pipefail

dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sha() {
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}
# upstream.psd1 field of a section: field Win11Debloat Url
field() {
  sed -n "/^    $1 = @{/,/^    }/p" "$dir/upstream.psd1" | sed -n "s/^ *$2 *= *'\(.*\)'.*/\1/p"
}

fail=0
fetch() { # name url sha out
  curl -fsSL -o "$4" "$2"
  local got
  got=$(sha "$4")
  if [ "$got" != "$3" ]; then
    echo "FAIL $1: sha256 $got, pinned $3" >&2
    fail=1
    return 1
  fi
  echo "OK   $1: sha256 matches"
}

if fetch Win11Debloat "$(field Win11Debloat Url)" "$(field Win11Debloat Sha256)" "$tmp/w11d.zip"; then
  unzip -q "$tmp/w11d.zip" -d "$tmp/w11d"
  script=$(find "$tmp/w11d" -maxdepth 2 -name Win11Debloat.ps1 | head -1)
  # The param() block runs from the top of the file to the first line that is just ")"
  params=$(sed -n '1,/^)/p' "$script" | grep -o '\$[A-Za-z0-9]*' | tr -d '$' | sort -u)
  while read -r arg; do
    name=${arg#-}
    if grep -qxF "$name" <<<"$params"; then
      echo "OK   Win11Debloat -$name"
    else
      echo "FAIL Win11Debloat -$name: not a parameter of $(field Win11Debloat Version)" >&2
      fail=1
    fi
  done < <(sed -e 's/\r$//' -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    "$dir/win11debloat-args.txt" | grep -v '^$')
fi

if fetch WinUtil "$(field WinUtil Url)" "$(field WinUtil Sha256)" "$tmp/winutil.ps1"; then
  while read -r id; do
    if grep -qF "\"$id\": {" "$tmp/winutil.ps1"; then
      echo "OK   WinUtil $id"
    else
      echo "FAIL WinUtil $id: unknown to $(field WinUtil Version)" >&2
      fail=1
    fi
  done < <(grep -o '"WPF[A-Za-z0-9]*"' "$dir/winutil-config.json" | tr -d '"')
fi

exit "$fail"
