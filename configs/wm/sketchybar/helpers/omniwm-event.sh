#!/bin/bash
#
# omniwmctl watch --exec から 1 イベントごとに起動されるハンドラ。
# stdin にイベント JSON が渡るが、ペイロード形はチャンネルごとに違うので
# ここでは読み捨てて「現在のフォーカス」を query で取り直す (レース回避にもなる)。
#
# prev は /tmp の状態ファイルで自前管理し、aerospace 互換の環境変数名で
# aerospace_workspace_change を発火する (理由は omniwm-bridge.sh 冒頭コメント)。

SB=/opt/homebrew/bin/sketchybar
STATE=/tmp/sketchybar-omniwm-ws.state

cat >/dev/null # stdin を消費 (書かないと watch 側の write が詰まりうる)

export WM_BACKEND=omniwm
source "$HOME/.config/sketchybar/helpers/wm.sh"

focused=$(wm_focused_workspace)
[ -z "$focused" ] && exit 0

prev=$(cat "$STATE" 2>/dev/null)
printf '%s\n' "$focused" > "$STATE"

# 壁紙 (configs/wallpaper/*.html) を現在ワークスペースに連動させる。
# HTML は同階層の state.js を 300ms ごとにポーリングして window.__ws を読み、
# applyWorkspace() で配色/模様を変える。壁紙自体は切り替えないのでフラッシュしない。
# (旧 aerospace.toml の exec-on-workspace-change を omniwm へ移植したもの)。
# Puddle が読むのは常にメインツリー側の HTML なのでパスは ~/.dotfiles 固定。
# ワークスペースが実際に変わったときだけ atomic (temp+mv) に書く。
if [ "$focused" != "$prev" ]; then
  ws_state="$HOME/.dotfiles/configs/wallpaper/state.js"
  ws_tmp="$ws_state.tmp.$$"
  printf 'window.__ws="%s";' "$focused" > "$ws_tmp" && mv -f "$ws_tmp" "$ws_state"
fi

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
wp_dir="$HOME/.dotfiles/configs/wallpaper"
"$OMNIWMCTL" query workspaces --visible --format json 2>/dev/null |
  "$JQ" -r '.result.payload.workspaces[] |
    [(.display.name // "unknown"), .rawName, (if (.counts.tiled // 0) > 0 then 1 else 0 end), (.isFocused // false)] | @tsv' 2>/dev/null |
  while IFS=$(printf '\t') read -r dname ws cov focused_flag; do
    slug=$(printf '%s' "$dname" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-*$//;s/^-*//')
    [ -n "$slug" ] || continue
    tmp="$wp_dir/inputs.$slug.tmp.$$"
    printf '%s\n%s\n' "$ws" "$cov" > "$tmp" && mv -f "$tmp" "$wp_dir/inputs.$slug"
    if [ "$focused_flag" = "true" ]; then
      tmp="$wp_dir/inputs.tmp.$$"
      printf '%s\n%s\n' "$ws" "$cov" > "$tmp" && mv -f "$tmp" "$wp_dir/inputs"
    fi
  done

# 同一 workspace のままのイベント (windows-changed) でも発火する:
# space_windows.sh が prev/focused のアイコン列を引き直すことで増減が反映される。
"$SB" --trigger aerospace_workspace_change \
  AEROSPACE_FOCUSED_WORKSPACE="$focused" \
  AEROSPACE_PREV_WORKSPACE="$prev"
