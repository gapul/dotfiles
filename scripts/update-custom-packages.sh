#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
slk_file="$repo/nix/pkgs/slk.nix"
unity_file="$repo/nix/pkgs/unity-cli.nix"
paper_file="$repo/nix/pkgs/paper-server.nix"
macmini_file="$repo/nix/hosts/macmini.nix"
protocol_map_url="https://raw.githubusercontent.com/PrismarineJS/minecraft-data/master/data/pc/common/protocolVersions.json"
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

# --- Paper (Minecraft server) ---------------------------------------------------------------
# 追うのは「いちばん新しい MC バージョンの、いちばん新しい STABLE ビルド」。実験ビルドは拾わない。
# 配布 URL に sha256 が埋まっている API なので、jar を落とさずにハッシュを確定できる。
pinned_paper_version=$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$paper_file" | head -1)
pinned_paper_build=$(sed -n 's/^[[:space:]]*build = "\([^"]*\)";/\1/p' "$paper_file" | head -1)

paper_latest=$(curl -fsS --max-time 30 https://fill.papermc.io/v3/projects/paper | python3 -c '
import json, sys
versions = json.load(sys.stdin)["versions"]
newest_series = next(iter(versions))
print(versions[newest_series][0])
')

paper_build=$(curl -fsS --max-time 30 "https://fill.papermc.io/v3/projects/paper/versions/${paper_latest}/builds" | python3 -c '
import json, sys
for b in json.load(sys.stdin):
    if b.get("channel") == "STABLE":
        print(b["id"], b["downloads"]["server:default"]["checksums"]["sha256"])
        break
')

if [[ -n $paper_build ]]; then
  latest_build=${paper_build%% *}
  latest_sha=${paper_build##* }
  if [[ $pinned_paper_version != "$paper_latest" || $pinned_paper_build != "$latest_build" ]]; then
    awk -v version="$paper_latest" -v build="$latest_build" -v sha="$latest_sha" '
      /^[[:space:]]*version = "/ && !v { sub(/"[^"]+"/, "\"" version "\""); v=1 }
      /^[[:space:]]*build = "/ && !b { sub(/"[^"]+"/, "\"" build "\""); b=1 }
      /^[[:space:]]*sha256 = "/ && !s { sub(/"[^"]+"/, "\"" sha "\""); s=1 }
      { print }
    ' "$paper_file" > "$tmp/paper.nix"
    mv "$tmp/paper.nix" "$paper_file"
    echo "paper: $pinned_paper_version-$pinned_paper_build -> $paper_latest-$latest_build"

    # サーバーが寝ている間の status は lazymc が代わりに返すので、そこに書く版も一緒に動かす。
    # 置き去りにすると、更新した翌朝からサーバー一覧に「非対応」の×が出る(繋がりはするが、
    # 友人からは入れない場所に見える)。protocol 番号は Paper の API に無いので外から引く。
    paper_proto=$(curl -fsS --max-time 30 "$protocol_map_url" | python3 -c '
import json, sys
want = sys.argv[1]
print(next((e["version"] for e in json.load(sys.stdin) if e["minecraftVersion"] == want), ""))
' "$paper_latest")
    if [[ -n $paper_proto ]]; then
      awk -v version="$paper_latest" -v proto="$paper_proto" '
        /^[[:space:]]*paperMcVersion = "/ { sub(/"[^"]+"/, "\"" version "\"") }
        /^[[:space:]]*paperProtocol = / { sub(/= [0-9]+/, "= " proto) }
        { print }
      ' "$macmini_file" > "$tmp/macmini.nix"
      mv "$tmp/macmini.nix" "$macmini_file"
      echo "paper (lazymc の表示): $paper_latest / protocol $paper_proto"
    else
      # 出たばかりの版はまだ載っていないことがある。間違った番号を書くより据え置く。
      echo "paper: $paper_latest の protocol 番号が引けなかったので lazymc の表示は据え置き" >&2
    fi
  fi
fi
