#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
slk_file="$repo/nix/pkgs/slk.nix"
unity_file="$repo/nix/pkgs/unity-cli.nix"
fabric_file="$repo/nix/pkgs/fabric-server.nix"
mods_file="$repo/nix/pkgs/fabric-mods.nix"
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

# --- Fabric (Minecraft servers) -------------------------------------------------------------
# 追うのは「宣言してある mod が全部揃っている、いちばん新しい安定版の MC バージョン」。
# 新しい版が出た直後は mod が追いつくまで数日〜数週間あり、その間は前の版に留まる。
# 同じ版の中でも loader と mod の新しいリリースは拾う。
# mod のハッシュは Modrinth が公開している sha512 をそのまま使う (jar を落とさない)。
# Fabric の起動 jar だけはハッシュが公開されていないので、落として計る。
pinned_mc=$(sed -n 's/^[[:space:]]*mcVersion = "\([^"]*\)";/\1/p' "$fabric_file" | head -1)
pinned_loader=$(sed -n 's/^[[:space:]]*loader = "\([^"]*\)";/\1/p' "$fabric_file" | head -1)
pinned_installer=$(sed -n 's/^[[:space:]]*installer = "\([^"]*\)";/\1/p' "$fabric_file" | head -1)

# 出力: 1 行目 "mc loader installer"、以降 1 mod につき "project slug name url sha512"。
# 揃う版が無ければ何も出さない。
fabric_pick=$(python3 - "$mods_file" <<'PY'
import json, re, sys, urllib.parse, urllib.request

def get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)

mods = re.findall(r"^\s*# modrinth:(\S+) (\S+)$", open(sys.argv[1]).read(), re.M)
games = [g["version"] for g in get("https://meta.fabricmc.net/v2/versions/game") if g["stable"]]
installer = get("https://meta.fabricmc.net/v2/versions/installer")[0]["version"]
for mc in games:
    loaders = [l for l in get(f"https://meta.fabricmc.net/v2/versions/loader/{mc}") if l["loader"]["stable"]]
    if not loaders:
        continue
    picks = []
    for project, slug in mods:
        q = urllib.parse.urlencode({"loaders": '["fabric"]', "game_versions": f'["{mc}"]'})
        vs = get(f"https://api.modrinth.com/v2/project/{project}/version?{q}")
        if not vs:
            break
        f = next(x for x in vs[0]["files"] if x["primary"])
        picks.append((project, slug, f["filename"], f["url"], f["hashes"]["sha512"]))
    else:
        print(mc, loaders[0]["loader"]["version"], installer)
        for p in picks:
            print(*p)
        break
PY
)

if [[ -n $fabric_pick ]]; then
  read -r mc loader installer <<<"$(head -1 <<<"$fabric_pick")"
  if [[ $pinned_mc != "$mc" || $pinned_loader != "$loader" || $pinned_installer != "$installer" ]]; then
    curl -fsSL "https://meta.fabricmc.net/v2/versions/loader/${mc}/${loader}/${installer}/server/jar" -o "$tmp/fabric.jar"
    fabric_hash=$(nix hash file --type sha256 "$tmp/fabric.jar")
    awk -v mc="$mc" -v loader="$loader" -v installer="$installer" -v hash="$fabric_hash" '
      /^[[:space:]]*mcVersion = "/ { sub(/"[^"]+"/, "\"" mc "\"") }
      /^[[:space:]]*loader = "/ { sub(/"[^"]+"/, "\"" loader "\"") }
      /^[[:space:]]*installer = "/ { sub(/"[^"]+"/, "\"" installer "\"") }
      /^[[:space:]]*hash = "/ { sub(/"[^"]+"/, "\"" hash "\"") }
      { print }
    ' "$fabric_file" > "$tmp/fabric-server.nix"
    mv "$tmp/fabric-server.nix" "$fabric_file"
    echo "fabric: $pinned_mc/$pinned_loader/$pinned_installer -> $mc/$loader/$installer"
  fi

  # mod 一覧はヘッダ (= 最初の `[` まで) を残して丸ごと作り直す。
  {
    sed -n '1,/^\[$/p' "$mods_file"
    tail -n +2 <<<"$fabric_pick" | while read -r project slug name url sha512; do
      sri=$(nix hash convert --hash-algo sha512 --to sri "$sha512")
      printf '  # modrinth:%s %s\n  (fetchurl {\n    name = "%s";\n    url = "%s";\n    hash = "%s";\n  })\n' \
        "$project" "$slug" "$name" "$url" "$sri"
    done
    echo "]"
  } > "$tmp/fabric-mods.nix"
  if ! cmp -s "$tmp/fabric-mods.nix" "$mods_file"; then
    mv "$tmp/fabric-mods.nix" "$mods_file"
    echo "fabric mods: 更新あり ($mc 向け)"
  fi

  # サーバーが寝ている間の status は lazymc が代わりに返すので、そこに書く protocol も一緒に動かす。
  # 置き去りにすると、更新した翌朝からサーバー一覧に「非対応」の×が出る。番号は Fabric の API に
  # 無いので外から引く。出たばかりの版はまだ載っていないことがあり、その時は据え置く。
  if [[ $pinned_mc != "$mc" ]]; then
    proto=$(curl -fsS --max-time 30 "$protocol_map_url" | python3 -c '
import json, sys
want = sys.argv[1]
print(next((e["version"] for e in json.load(sys.stdin) if e["minecraftVersion"] == want), ""))
' "$mc")
    if [[ -n $proto ]]; then
      awk -v proto="$proto" '
        /^[[:space:]]*mcProtocol = / { sub(/= [0-9]+/, "= " proto) }
        { print }
      ' "$macmini_file" > "$tmp/macmini.nix"
      mv "$tmp/macmini.nix" "$macmini_file"
      echo "fabric (lazymc の表示): $mc / protocol $proto"
    else
      echo "fabric: $mc の protocol 番号が引けなかったので lazymc の表示は据え置き" >&2
    fi
  fi
fi
