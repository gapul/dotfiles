# 重いレンダリングを macmini に寄せる。
#
# この機械に置く理由は「余っているから」ではなく、母艦を占有せずに済むから。編集や
# 執筆をしている最中に書き出しが走ると、その間ずっと使い物にならなくなる。
#
# 実測 (2026-09-01): メモリは 68% 空き、常時食っているのは まなび の next-server (22%)
# だけ。MLX 系は呼ばれたときだけ動くので、書き出しと食い合うのは同時に叩いたときだけ。
#
# ## 何が宣言でき、何ができないか
#
#   blender  — nixpkgs にあり darwin 対応。`blender -b file.blend -a` で画面なしで焼ける
#   ffmpeg   — 既に入っている。M4 の VideoToolbox でハードウェアエンコードが効く
#
#   DaVinci  — nixpkgs のパッケージは x86_64-linux 専用 (確認済み)。darwin で使うなら
#              Blackmagic の dmg を手で入れることになり、宣言の外に出る
#   Adobe    — Creative Cloud が自前で管理するので宣言できない。これは母艦でも同じで、
#              [[adobe-cc-undeclarable]] に「棚卸しで未宣言として再報告しない」と
#              決めてある
#
# Adobe は After Effects だけ入れる方針にした (2026-09-01)。狙いは aerender で、
# これは画面なしでコンポを焼けるコマンド。macmini に置く意味があるのはここだけ。
#
# Premiere は入れない。書き出しを外から叩く手が Media Encoder の監視フォルダしか
# 無く、あれはアプリが起動している前提なので画面の無いこの機械には向かない。
# DaVinci も同じ理由で入れない (加えて nixpkgs のパッケージが x86_64-linux 専用)。
#
# 導入は手作業になる。Creative Cloud が自前で管理するので宣言できず、サインインも
# GUI が要る。macmini は画面共有が有効なので、そこから入れられる:
#
#   1. 画面共有で macmini に繋ぐ
#   2. Creative Cloud を入れてサインイン
#   3. After Effects だけ入れる (Premiere は入れない)
#
# 入ると aerender はここに来る:
#   /Applications/Adobe After Effects <年>/aerender
#
# 母艦から投げるならこうなる:
#   ssh macmini '/Applications/Adobe\ After\ Effects\ 2026/aerender \
#     -project /path/to.aep -comp "Main" -output /path/out.mov'
#
# ラッパーはまだ書かない。AE が入っていない状態で書いても試せず、実物を見てから
# でないとパスも引数も決められない。入れたあとで足す。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Blender は nix ではなく brew の cask で入れる (hosts/macmini.nix)。理由はあちらの
    # コメント参照: nixpkgs 版は依存の manifold が macmini でテスト中に落ち、
    # aarch64-darwin のキャッシュも無いのでソースから建てることになる。
    #
    # 画面なしで焼くときは .app の中の実体を叩く:
    #   /Applications/Blender.app/Contents/MacOS/Blender -b scene.blend -a

    # 書き出し後の変換と作り直し。編集ソフトを持ち出さずに済む仕事はここで終わる。
    # M4 のハードウェアエンコーダを使うなら -c:v hevc_videotoolbox / h264_videotoolbox。
    # 素材が HLG の HDR なので、SDR に落とすときは色変換を明示しないと眠い絵になる。
    ffmpeg-full
  ];
}
