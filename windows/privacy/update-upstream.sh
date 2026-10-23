#!/usr/bin/env bash
# Pin Win11Debloat and WinUtil in upstream.psd1 to their latest GitHub releases.
# Runs on macOS or Linux (needs gh, curl, shasum). Review the diff before committing:
# a new WinUtil can rename tweak IDs (winutil-config.json) and a new Win11Debloat can
# drop arguments (win11debloat-args.txt); check-upstream.sh verifies both.
set -euo pipefail

dir=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

w_tag=$(gh api repos/Raphire/Win11Debloat/releases/latest -q .tag_name)
w_commit=$(gh api "repos/Raphire/Win11Debloat/commits/$w_tag" -q .sha)
w_url="https://github.com/Raphire/Win11Debloat/archive/$w_commit.zip"
curl -fsSL -o "$tmp/w11d.zip" "$w_url"
w_sha=$(sha "$tmp/w11d.zip")

u_tag=$(gh api repos/ChrisTitusTech/winutil/releases/latest -q .tag_name)
u_url="https://github.com/ChrisTitusTech/winutil/releases/download/$u_tag/winutil.ps1"
curl -fsSL -o "$tmp/winutil.ps1" "$u_url"
u_sha=$(sha "$tmp/winutil.ps1")
# GitHub records a digest for release assets; refuse a download that does not match it
u_digest=$(gh api repos/ChrisTitusTech/winutil/releases/latest \
  -q '.assets[] | select(.name == "winutil.ps1") | .digest')
if [ "$u_digest" != "sha256:$u_sha" ]; then
  echo "winutil.ps1: downloaded $u_sha, GitHub says $u_digest" >&2
  exit 1
fi

# Keep the header comment, regenerate the data
header=$(sed -n '/^@{/q;p' "$dir/upstream.psd1" | tr -d '\r')
{
  printf '%s\n' "$header"
  cat <<EOF
@{
    Win11Debloat = @{
        Version = '$w_tag'
        Commit  = '$w_commit'
        Url     = '$w_url'
        Sha256  = '$w_sha'
    }
    WinUtil = @{
        Version = '$u_tag'
        Url     = '$u_url'
        Sha256  = '$u_sha'
    }
}
EOF
} >"$dir/upstream.psd1.new"
mv "$dir/upstream.psd1.new" "$dir/upstream.psd1"

echo "Win11Debloat $w_tag ($w_commit), WinUtil $u_tag"
"$dir/check-upstream.sh"
