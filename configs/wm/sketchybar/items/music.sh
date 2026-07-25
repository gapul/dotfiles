#!/bin/bash

# 再生中の曲(mopidy優先)を表示。バークリックでタイトルの右に操作アイコンを展開。
# 右側バーは「後から追加した item ほど中央寄り(左)」に並ぶため、
# 操作ボタンを like→prev の逆順で先に追加し、music を最後に追加することで
# 左から [曲名][prev][-10s][再生停止][+10s][next][like] の並びにする。

mkbtn() { # name icon action
  sketchybar --add item "$1" right \
             --set "$1" icon="$2" icon.font="$FONT:Bold:$(scf 12.0)" \
                        icon.color=$WHITE label.drawing=off drawing=off \
                        icon.padding_left=1 icon.padding_right=1 \
                        background.padding_left=0 background.padding_right=0 \
                        click_script="$PLUGIN_DIR/music_click.sh $3"
}
mkbtn music.like     "􀊴"                    like
mkbtn music.next     "$SPOTIFY_NEXT"        next
mkbtn music.toggle   "$SPOTIFY_PLAY_PAUSE"  toggle
mkbtn music.prev     "$SPOTIFY_BACK"        prev

music=(
  icon=􀑪
  icon.color=$GREEN
  icon.font="$FONT:Bold:$(scf 14.0)"
  label.font="$FONT:Semibold:$(scf 13.0)"
  label.color=$LABEL_COLOR
  label.max_chars=20
  label.shadow.drawing=off
  label.scroll_duration=150
  label.drawing=on
  scroll_texts=on
  drawing=off
  updates=on
  update_freq=5
  script="$PLUGIN_DIR/music.sh"
  click_script="$PLUGIN_DIR/open_tui.sh music"
)
sketchybar --add item music right \
           --set music "${music[@]}"
