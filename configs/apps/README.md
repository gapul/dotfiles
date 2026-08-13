# GUI アプリ plist 管理

menubar / 入力系ユーティリティの設定を home-manager activation で復元する。
Puddle は websites(壁紙)と security-scoped bookmark を壊さないよう、
enforce したいキーのみ `defaults write`(surgical)。

## 管理対象

| App | 方式 | 説明 |
|---|---|---|
| **Puddle** | surgical write (`nix/home/darwin.nix`) | 動的壁紙。websites/bookmark はライブ保持し全置換しない。behavior 3 キー(deactivateOnBattery / extendPuddleBelowMenuBar / showOnAllSpaces)のみ enforce |

## menubar アイコンの表示/非表示

`NSStatusItem VisibleCC Item-*` = false で「アイコンを隠す」状態を管理対象に含める
(Maccy)。rebuild の import で隠し状態が表示に戻らないよう明示保持する。
位置キー `NSStatusItem Preferred Position*` は端末固有なので除外する。

## 新 Mac での復元

`just rebuild`(home-manager activation)で Puddle の behavior 3 キーが
`defaults write` される。以下は GUI で手動:

### Puddle
- 壁紙は `puddle apply` で入る(`~/.config/puddle/install.toml` の `wallpapers`)。
  シェーダ本体は dotfiles ではなく gapul/puddle-shaders にあり、
  `~/Library/Application Support/Puddle/Wallpapers/` へ展開される。
  ここに残るのはワークスペース連動の inputs(実行時状態)だけ。

## 設定変更後の capture

Puddle は plist を持たない(surgical write)。behavior を変えたら
`nix/modules/home/darwin-apps.nix` の puddlePrefs 内 `defaults write` を直接編集する。
