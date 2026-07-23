#!/usr/bin/env bash
# 解像度可変(ディスプレイ別=per-monitor)の aerospace gaps を生成する。
# 各ディスプレイを「自分の論理縦解像度」で個別にスケールし、aerospace のモニタ別 gap 配列
#   key = [{ monitor.main = <mainをmain解像度でスケール> }, <その他=外部解像度でスケール> ]
# として ~/.config/aerospace/aerospace.toml に書き出す。基準は sketchybar/ghostty と同じ縦 REF_H pt。
#
# aerospace は gap をモニタ別に持てる数少ない設定なので、ここだけ真のマルチディスプレイ対応が可能。
# (sketchybar のバー高さは全画面共通の1値しか持てず per-display 不可)
#
# accordion-padding はモニタ別を持てないスカラーなので main の係数でスケール。
# nh home switch の home.activation から `aerospace-config.sh <source-toml>` で呼ばれる。
# 生成後 aerospace 起動中なら reload-config --dry-run で検証し、失敗時は等倍にフォールバック。
set -eu

REF_H=1112
SRC="${1:?source aerospace.toml path required}"
OUT_DIR="$HOME/.config/aerospace"
OUT="$OUT_DIR/aerospace.toml"
AS=/opt/homebrew/bin/aerospace

# gap のベース値(基準 REF_H pt=1112 のときの px)。source toml と一致させておく。
B_INNER=8      # inner.horizontal / inner.vertical
B_SIDE=6       # outer.left / outer.right / outer.bottom
B_TOP_MAIN=6   # outer.top のメインディスプレイ側
B_TOP_EXT=40   # outer.top のその他(外部)ディスプレイ側
B_ACCORDION=30 # accordion-padding (スカラー)

# メインと外部代表の論理縦(pt)を取得。外部が複数なら最小(=一番小さい画面で大きくなりすぎない)を代表に。
read -r MAIN_H EXT_H < <(/usr/bin/swift - <<'SWIFT' 2>/dev/null || true
import CoreGraphics
var n: UInt32 = 0
CGGetActiveDisplayList(0, nil, &n)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
CGGetActiveDisplayList(n, &ids, &n)
var mainH = 0
var ext: [Int] = []
for id in ids.prefix(Int(n)) {
  let h = Int(CGDisplayBounds(id).height)
  if CGDisplayIsMain(id) != 0 { mainH = h } else if h > 0 { ext.append(h) }
}
let extH = ext.min() ?? mainH
print("\(mainH) \(extH)")
SWIFT
)
case "${MAIN_H:-}" in ''|*[!0-9]*) MAIN_H=$REF_H ;; esac
[ "${MAIN_H:-0}" -gt 0 ] 2>/dev/null || MAIN_H=$REF_H
case "${EXT_H:-}" in ''|*[!0-9]*) EXT_H=$MAIN_H ;; esac
[ "${EXT_H:-0}" -gt 0 ] 2>/dev/null || EXT_H=$MAIN_H

# round(base * height / REF_H)
r() { /usr/bin/awk -v b="$1" -v h="$2" -v r="$REF_H" 'BEGIN{printf "%.0f", b*h/r}'; }

INNER_M=$(r "$B_INNER" "$MAIN_H");   INNER_E=$(r "$B_INNER" "$EXT_H")
SIDE_M=$(r "$B_SIDE" "$MAIN_H");     SIDE_E=$(r "$B_SIDE" "$EXT_H")
TOP_M=$(r "$B_TOP_MAIN" "$MAIN_H");  TOP_E=$(r "$B_TOP_EXT" "$EXT_H")
ACCORDION=$(r "$B_ACCORDION" "$MAIN_H")

/bin/mkdir -p "$OUT_DIR"
# 旧 home-manager symlink (read-only store 向き) が残っていると書き込みが Permission denied に
# なるため、先に除去して通常ファイルとして書き出す。$OUT は nix 管理外なので削除して安全。
/bin/rm -f "$OUT"

# 1) @DOTFILES@ を現在のホーム配下の checkout に展開
# 2) accordion-padding をスカラーで main 係数スケール
# 3) [gaps] ブロックの inner.*/outer.* を per-monitor 配列に差し替え
/usr/bin/awk \
  -v dotfiles="$HOME/.dotfiles" \
  -v accordion="$ACCORDION" \
  -v im="$INNER_M" -v ie="$INNER_E" \
  -v sm="$SIDE_M" -v se="$SIDE_E" \
  -v tm="$TOP_M" -v te="$TOP_E" '
  { gsub(/@DOTFILES@/, dotfiles) }
  # accordion-padding (スカラー)
  /^[[:space:]]*accordion-padding[[:space:]]*=/ { print "accordion-padding = " accordion; next }
  # [gaps] セクション: ヘッダの直後に生成ブロックを注入し、元の inner./outer. 行は捨てる
  /^\[gaps\][[:space:]]*$/ {
    print
    printf "    inner.horizontal = [{ monitor.main = %s }, %s]\n", im, ie
    printf "    inner.vertical   = [{ monitor.main = %s }, %s]\n", im, ie
    printf "    outer.left       = [{ monitor.main = %s }, %s]\n", sm, se
    printf "    outer.right      = [{ monitor.main = %s }, %s]\n", sm, se
    printf "    outer.bottom     = [{ monitor.main = %s }, %s]\n", sm, se
    printf "    outer.top        = [{ monitor.main = %s }, %s]\n", tm, te
    ingaps = 1
    next
  }
  ingaps && /^[[:space:]]*(inner|outer)\./ { next }   # 元の gap 行を捨てる
  ingaps { ingaps = 0 }                                # ブロック終端(空行など)で解除
  { print }
' "$SRC" > "$OUT"

echo "aerospace per-monitor gaps: main(H=$MAIN_H) inner=$INNER_M side=$SIDE_M top=$TOP_M / ext(H=$EXT_H) inner=$INNER_E side=$SIDE_E top=$TOP_E / accordion=$ACCORDION"

# aerospace 起動中なら検証して反映。ダメなら等倍(=ソースそのまま)にフォールバック。
if [ -x "$AS" ] && "$AS" list-workspaces --focused >/dev/null 2>&1; then
  if ! "$AS" reload-config --dry-run >/dev/null 2>&1; then
    echo "aerospace: generated config failed dry-run -> fallback to source (unscaled)" >&2
    /bin/cp -f "$SRC" "$OUT"
  fi
  "$AS" reload-config >/dev/null 2>&1 || true
fi
