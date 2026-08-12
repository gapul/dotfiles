#!/bin/bash
#
# omniwmctl watch --exec から 1 イベントごとに起動されるハンドラ。
# stdin にイベント JSON が渡るが、ペイロード形はチャンネルごとに違うので
# ここでは読み捨てて「現在のフォーカス」を query で取り直す (レース回避にもなる)。
#
# prev は /tmp の状態ファイルで自前管理し、OMNIWM_* の環境変数名で
# omniwm_workspace_change を発火する (理由は omniwm-bridge.sh 冒頭コメント)。

# バーは 2 本 (内蔵用 / 外部モニタ用) 走っているので、イベントは両方に投げる。
SB="$HOME/.config/sketchybar/helpers/sb-all.sh"
STATE=/tmp/sketchybar-omniwm-ws.state

cat >/dev/null # stdin を消費 (書かないと watch 側の write が詰まりうる)

export WM_BACKEND=omniwm
source "$HOME/.config/sketchybar/helpers/wm.sh"

focused=$(wm_focused_workspace)
[ -z "$focused" ] && exit 0

prev=$(cat "$STATE" 2>/dev/null)
printf '%s\n' "$focused" > "$STATE"

# (HTML 壁紙とその state.js ポーリングは廃止。Puddle は .metal を直接レンダリングしていて、
#  ワークスペース連動は下の inputs ファイル経由に一本化されている。)

# 同一 workspace のままのイベント (windows-changed) でも発火する:
# space_windows.sh が prev/focused のアイコン列を引き直すことで増減が反映される。
"$SB" --trigger omniwm_workspace_change \
  OMNIWM_FOCUSED_WORKSPACE="$focused" \
  OMNIWM_PREV_WORKSPACE="$prev"

# Native (Puddle Metal) 壁紙用の入力ファイル (Puddle wallpaper-source contract の
# inputs 書式: 1 行 1 float・位置順で user[] へ)。
#   user[0] = workspace / user[1] = covered (タイル窓が1つでもあれば 1)
# covered は Puddle の品質ガバナー(reduced 段=低fps/低解像度)のヒント。
# windows-changed イベントでもここは更新したいので workspace 変更ガードの外に置く。
#
# omniwm はワークスペースがモニタ単位なので、ディスプレイごとに「そのモニタで
# 見えているワークスペース」を inputs.<ディスプレイ名スラグ> に書く
# (例: inputs.built-in-display / inputs.dell-p3225qe)。Puddle 側は instance ごとに
# 読むファイルを選ぶ (WallpaperInstance.inputs)。中身の並びは全ファイル共通
# [ws, covered] なのでシェーダは無変更で済む。
# 互換のため従来の inputs (グローバルフォーカスのワークスペース) も書き続ける。
# ディスプレイの現在WSは displays[].activeWorkspace で取る。workspaces --visible の
# isFocused/isVisible は「フォーカスされた窓」基準で、空ワークスペースに切り替えると
# 前のWSを報告し続ける (空WSで壁紙が変わらない原因だった)。
wp_dir="$HOME/.dotfiles/configs/wallpaper"

# 連続切替ではイベント毎に本スクリプトが並走し、古い状態を読んだ遅いインスタンスが
# 最後に書いて inputs が stale で固まることがある (query→write が非アトミック)。
# mkdir ロックで直列化する: 後から始まった方が後にクエリして後に書く=最新で収束。
# ロック待ちは最大 ~3秒、超えたら (前任者が死んでいるとみなして) 奪う。
_wp_lock="$wp_dir/.inputs.lock"
_wp_waited=0
until mkdir "$_wp_lock" 2>/dev/null; do
  _wp_waited=$((_wp_waited + 1))
  if [ "$_wp_waited" -ge 30 ]; then rm -rf "$_wp_lock"; fi
  sleep 0.1
done
trap 'rmdir "$_wp_lock" 2>/dev/null || true' EXIT

DISPLAYS_JSON=$("$OMNIWMCTL" query displays --format json 2>/dev/null)
WORKSPACES_JSON=$("$OMNIWMCTL" query workspaces --format json 2>/dev/null)
export DISPLAYS_JSON WORKSPACES_JSON wp_dir
python3 - <<'PY' 2>/dev/null
import json, os, re, tempfile
try:
    displays = json.loads(os.environ["DISPLAYS_JSON"])["result"]["payload"]["displays"]
    workspaces = json.loads(os.environ["WORKSPACES_JSON"])["result"]["payload"]["workspaces"]
except Exception:
    raise SystemExit
tiled = {w["rawName"]: (w.get("counts") or {}).get("tiled", 0) for w in workspaces}
wp_dir = os.environ["wp_dir"]

def write(path, ws, covered):
    fd, tmp = tempfile.mkstemp(dir=wp_dir)
    with os.fdopen(fd, "w") as f:
        f.write(f"{ws}\n{covered}\n")
    os.replace(tmp, path)

for d in displays:
    ws = (d.get("activeWorkspace") or {}).get("rawName")
    if not ws:
        continue
    covered = 1 if tiled.get(ws, 0) > 0 else 0
    slug = re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", (d.get("name") or "unknown").lower()))
    if slug:
        write(f"{wp_dir}/inputs.{slug}", ws, covered)
    if d.get("isCurrent"):
        write(f"{wp_dir}/inputs", ws, covered)
PY

