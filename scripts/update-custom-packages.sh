#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
slk_file="$repo/nix/pkgs/slk.nix"
unity_file="$repo/nix/pkgs/unity-cli.nix"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pinned_slk=$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$slk_file" | head -1)
latest_slk=$(gh api repos/gammons/slk/releases/latest --jq '.tag_name | ltrimstr("v")')
if [[ $pinned_slk != "$latest_slk" ]]; then
  for arch in arm64 x86_64; do
    curl -fsSL "https://github.com/gammons/slk/releases/download/v${latest_slk}/slk_${latest_slk}_darwin_${arch}.tar.gz" -o "$tmp/slk-$arch.tar.gz"
  done
  slk_arm=$(nix hash file --type sha256 "$tmp/slk-arm64.tar.gz")
  slk_x64=$(nix hash file --type sha256 "$tmp/slk-x86_64.tar.gz")
  awk -v version="$latest_slk" -v arm="$slk_arm" -v x64="$slk_x64" '
    /version = "/ && !done { sub(/"[^"]+"/, "\"" version "\""); done=1 }
    /aarch64-darwin =/ { platform="arm" }
    /x86_64-darwin =/ { platform="x64" }
    /hash = "/ && platform=="arm" { sub(/"[^"]+"/, "\"" arm "\""); platform="" }
    /hash = "/ && platform=="x64" { sub(/"[^"]+"/, "\"" x64 "\""); platform="" }
    { print }
  ' "$slk_file" > "$tmp/slk.nix"
  mv "$tmp/slk.nix" "$slk_file"
  echo "slk: $pinned_slk -> $latest_slk"
fi

manifest=$(curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/latest-beta.json)
latest_unity=$(jq -r '.version' <<<"$manifest")
pinned_unity=$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$unity_file" | head -1)
if [[ $pinned_unity != "$latest_unity" ]]; then
  unity_darwin_arm64=''
  unity_darwin_x64=''
  unity_linux_arm64=''
  unity_linux_x64=''
  for platform in darwin-arm64 darwin-x64 linux-arm64 linux-x64; do
    hex=$(jq -r --arg p "$platform" '.binaries[$p].sha256' <<<"$manifest")
    printf -v "unity_${platform//-/_}" '%s' "$(nix hash convert --hash-algo sha256 --to sri "$hex")"
  done
  awk -v version="$latest_unity" \
    -v da="$unity_darwin_arm64" -v dx="$unity_darwin_x64" \
    -v la="$unity_linux_arm64" -v lx="$unity_linux_x64" '
    /version = "/ && !done { sub(/"[^"]+"/, "\"" version "\""); done=1 }
    /platform = "darwin-arm64"/ { hash=da }
    /platform = "darwin-x64"/ { hash=dx }
    /platform = "linux-arm64"/ { hash=la }
    /platform = "linux-x64"/ { hash=lx }
    /hash = "/ && hash!="" { sub(/"[^"]+"/, "\"" hash "\""); hash="" }
    { print }
  ' "$unity_file" > "$tmp/unity-cli.nix"
  mv "$tmp/unity-cli.nix" "$unity_file"
  echo "unity-cli: $pinned_unity -> $latest_unity"
fi
