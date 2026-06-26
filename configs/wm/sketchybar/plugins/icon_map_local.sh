# shellcheck shell=bash
# icon_map ローカル補正
# アプリの実名 (aerospace / front_app が返す名前) が sketchybar-app-font の
# 公式マップのキーと異なるものを、ここで上書きする。
# icon_map.sh の末尾から source される。再生成 (just sketchybar-font) でも
# この файл は触られないため、補正は維持される。
#
# 使い方: 実名 -> 既存グリフ(:xxx:) を case に追加するだけ。
# 既存グリフ名は公式 icon_map.sh の値 (例: :obsstudio:) を流用する。
case "$1" in
    "OBS Studio") icon_result=":obsstudio:" ;;  # 公式キーは "OBS" のみ
esac
