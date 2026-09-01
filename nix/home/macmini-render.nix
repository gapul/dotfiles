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
# Adobe を macmini に入れると、あの機械で唯一の手動管理物になる。入れる価値は
# aerender (AE をコマンドで焼ける) にあるので、実際に「AE の書き出しを投げたい」場面が
# 来てから判断する。Premiere 側は Media Encoder の監視フォルダしか手が無く、あれは
# アプリが起動している前提なので画面の無いこの機械には向かない。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # 3D。CLI で完結するので画面が無くてよい。
    #   blender -b scene.blend -a              全フレーム
    #   blender -b scene.blend -f 120          特定フレーム
    #   blender -b scene.blend -o /tmp/out_ -a 出力先を指定
    #
    # GPU を使うかは blend 側の設定次第。M4 は Metal で回るが、シーンによっては
    # CPU の方が速いことがあるので、重いものは両方測ってから決めること。
    blender

    # 書き出し後の変換と作り直し。編集ソフトを持ち出さずに済む仕事はここで終わる。
    # M4 のハードウェアエンコーダを使うなら -c:v hevc_videotoolbox / h264_videotoolbox。
    # 素材が HLG の HDR なので、SDR に落とすときは色変換を明示しないと眠い絵になる。
    ffmpeg-full
  ];
}
