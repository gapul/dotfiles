# SKK 環境 (macSKK + skkeleton + azooKey skkserv)

## 構成

| 要素 | 場所 | 役割 |
|---|---|---|
| **macSKK** | InputMethod (Container sandboxed) | GUI アプリで日本語入力 |
| **skkeleton** | nvim plugin | エディタ内 SKK |
| **azooKey skkserv** | `/Applications/azooKey skkserv.app` | skkserv (localhost:1178) |
| **公開辞書** | `~/.skk/SKK-JISYO.{L,geo,jinmei,propernoun,station}` | skkeleton が直接読む |
| **公開辞書 (macSKK 用 copy)** | `~/Library/Containers/net.mtgto.../Documents/Dictionaries/` | macSKK が sandbox 内で読む |
| **user dict (macSKK)** | 同上の `skk-jisyo.utf8` | macSKK 専用学習 |
| **user dict (skkeleton)** | `~/.skk/skkeleton-user-dict` | skkeleton 専用学習 |

## 管理対象 (dotfiles)

- `macSKK.plist` — macSKK の workarounds (Ghostty/VSCode/Brave) + UI 設定 + skkserv 接続情報
- `azoo-key-skkserv.plist` — host/incomingCharset/startServerAtLaunch

両方とも home.nix の `home.activation.skkPlistImport` で `defaults import` され、`killall cfprefsd` で flush される。

## sandbox の制限事項

1. **辞書は symlink 不可**: macSKK sandbox は `~/.skk/` への symlink を読めない (NSPOSIX EPERM) → real file copy が必須。9MB 二重持ち。
2. **plist 直書きは効かない**: macSKK は `dictionaries[]` 配列を起動時に load せず、NSFilePresenter で実行時イベントから登録する設計。`defaults import` でも dict 一覧は再現されない。
3. **辞書登録は手動**: macSKK 起動中に「削除 → 配置」で NSFilePresenter イベントを発火させる必要あり。

## 初回セットアップ (新 Mac)

```bash
# 1. 公開辞書を ~/.skk/ に入れる (skkeleton 用)
bash ~/dotfiles/scripts/install-skk-dicts.sh

# 2. macSKK を一度起動(menubar から日本語入力切替)
#    Container ディレクトリが作成されるまで待つ

# 3. macSKK 用 Container にも辞書をコピー
#    (macSKK 起動中に削除→ditto で NSFilePresenter を発火)
bash ~/dotfiles/scripts/install-skk-dicts-macskk.sh

# 4. macSKK 設定画面 → Dictionaries で各辞書を Toggle ON

# 5. (オプション) skkserv を有効化
#    macSKK 設定 → Dictionaries → SKKServ Toggle ON
```

## 設定変更後の capture

GUI で macSKK / skkserv の設定を変えたら、dotfiles に反映するには:

```bash
# macSKK plist 抽出
cp ~/Library/Containers/net.mtgto.inputmethod.macSKK/Data/Library/Preferences/net.mtgto.inputmethod.macSKK.plist \
   ~/dotfiles/configs/ime/skk/macSKK.plist

# azooKey skkserv plist 抽出 (UI state 除外)
cp ~/Library/Containers/io.github.gitusp.azoo-key-skkserv/Data/Library/Preferences/io.github.gitusp.azoo-key-skkserv.plist \
   ~/dotfiles/configs/ime/skk/azoo-key-skkserv.plist
# UI state (NSWindow Frame) を除外
python3 -c "
import plistlib
p = '$HOME/dotfiles/configs/ime/skk/azoo-key-skkserv.plist'
with open(p, 'rb') as f: d = plistlib.load(f)
for k in list(d): 
    if k.startswith('NSWindow Frame'): del d[k]
with open(p, 'wb') as f: plistlib.dump(d, f)
"
```

## 共有していないもの

- **学習履歴 (user dict)**: macSKK と skkeleton で**別々**。同期は将来課題。
  - 同じファイルにすると race condition で消える可能性 + 書式互換性未保証
- **macSKK の Dictionary file 一覧**: GUI で都度 toggle 要(plist 経由では再現されない)
