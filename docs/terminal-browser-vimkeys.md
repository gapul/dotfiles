# terminal-browser の Vim 風キー操作 (Surfingkeys 代替)

terminal-browser は拡張機能を読み込めない。Electron の `session.loadExtension` を露出していないので、
Surfingkeys を入れる経路そのものが存在しない。代わりに同等のものを二層で書いた。

| | 置き場所 | 対応するもの |
| --- | --- | --- |
| `configs/cli/terminal-browser/vimkeys.js` | `--preload` (ページの隔離ワールド) | content script |
| `configs/cli/terminal-browser/main.js` | `--main-script` (Electron メインプロセス) | background script |

`--main-script` は `createRequire(file)(file)` として読まれるので素の CommonJS で、`require("electron")`
がそのまま使える。ページ側は `ipcRenderer` を持っているので、ページから手の届かない操作だけを
メイン側へ投げている。

配線は `nix/pkgs/terminal-browser.nix` の bin ラッパーが持つ。`open` と `new-tab` のときだけ 2 つの
フラグを足す (`--preload` はこの 2 つしか受け付けず、`shutdown` や `ls` に渡すと落ちる)。
**どちらのファイルも、無ければ何も足さない。**挙動が邪魔になったら消せば素の terminal-browser に戻る。

## 実装したもの

Surfingkeys の既定マッピング (`src/content_scripts/common/default.js`, 145 件) と、`normal.js` の
スクロール系を突き合わせて実装した。

スクロール: `j` `k` `h` `l` `d` `u` `gg` `G` `0` `$` `;fs`
ヒント: `f` `af` `gf` `cf` `q` `ya` `yma` `yv` `ymv` `yc` `yq` `yi` `i` `gi` `O`
履歴と URL: `S` `D` `r` `gu` `gU` `g?` `g#` `[[` `]]`
yank: `yy` `yh` `yl` `ys` `yf` `yp` `gs`
visual と検索: `v` `V` `zv` `n` `N` `*` `/`、visual 中の `h` `j` `k` `l` `w` `b` `0` `$` `y`
マーク: `m<文字>` `'<文字>`
zoom: `zi` `zo` `zr`
タブ (main.js 経由): `x` `X` `on` `t` `go` `yt` `yT` `gxx` `gxt` `gxT`
その他: `.` `?` `Esc`

`?` でこの一覧が画面に出る。

## 再現していないもの

### 対応物が存在しない (構造的に不可能)

Chrome という製品固有の面を叩くもの。terminal-browser にはブックマークも履歴 DB もダウンロード
シェルフも拡張機構もセッション復元もプロキシ設定もないので、繋ぐ先が無い。

- ブックマーク: `b` `ab` `;db` `gb`
- 履歴: `oh` `ox` `;dh` `;yh` `;ph` `gh`
- ダウンロード: `yd` `;di` `;j` `gd`
- `chrome://` を開くもの: `ga` `gc` `gk` `ge` `gn` `;i`
- 拡張一覧: `ge`
- プロキシ: `cp` `;cp` `;ap`
- セッション: `ZZ` `ZR`
- コンテナタブ: `;cl`、シークレット: `oi`
- ウィンドウ操作: `W` `;gt` `;gw` (terminal-browser のウィンドウはペイン)

### 公開経路が無い

terminal-browser のタブ模型は内部クラスが持っていて外から順序を触れない。新規タブは CLI
(`terminal-browser new-tab`) が唯一の公開経路なので、増やす・閉じる・複製はそこを通している。
選択と並べ替えは terminal-browser 自身のタブキーとパレットが持っているので、嘘の実装を置かずに
その旨を返すだけにした。

- `gt` `gT` `<<` `>>` `T` `<Ctrl-6>` `gp` `B` `F` `;x` `gx0` `gx$` `gxp`

### 外部サービス / 別プロセスが要る

- 翻訳と LLM: `Q` `;t` `A` `<Space>t` `cq` `gr`
- vim/neovim 連携: `<Ctrl-i>` `<Ctrl-Alt-i>` `;v` `;u` `;U` `I`
- PDF ビューア: `;s`
- markdown プレビュー: `;pm`
- 設定編集と設定の yank/put: `;e` `yj` `;pj` `yQ`

### 意図的に省いた

- `w` (フレーム切り替え) と `;w` (最上位フレームへ): 端末の中の 1 ペインという使い方で iframe を
  跨ぐ場面が想定しにくい
- `<Ctrl-h>` / `<Ctrl-j>` (mouseover/mouseout の発火): 修飾キー付きは terminal-browser 自身の
  ショートカットと食い合うので単独キーだけを見る方針にした
- `;pp` / `cc` / `;ap` などクリップボードから読む系: `--allow-clipboard-read` を渡さない限り読めない。
  既定で無効なのは意図した設定なので、そちらを優先した

## 拡張したいとき

`~/.config/terminal-browser/vimkeys.js` の `CMD` に 1 行足すだけで増える。rebuild は要らない
(次に開いたときから効く)。定着したら `configs/cli/terminal-browser/vimkeys.js` に持っていく。
