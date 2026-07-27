# GUI アプリ plist 管理

menubar / 入力系ユーティリティの設定を home-manager activation で復元する。
AltTab / Mos は `defaults import`(ドメイン全置換)、Plash は websites(壁紙)と
security-scoped bookmark を壊さないよう enforce したいキーのみ `defaults write`(surgical)。

## 管理対象

| App | 方式 | 説明 |
|---|---|---|
| **AltTab** | import `com.lwouis.alt-tab-macos.plist` | Cmd+Tab 代替の Window switcher。外見系設定のみ(キーバインドは secureData blob) |
| **Mos** | import `com.caldis.Mos.plist` | スクロール挙動 (smooth/reverse/speed)、menubar アイコン非表示 |
| **Plash** | surgical write (`nix/home/darwin.nix`) | 動的壁紙。websites/bookmark はライブ保持し全置換しない。behavior 3 キー(deactivateOnBattery / extendPlashBelowMenuBar / showOnAllSpaces)のみ enforce |

## menubar アイコンの表示/非表示

`NSStatusItem VisibleCC Item-*` = false で「アイコンを隠す」状態を管理対象に含める
(Maccy/Mos)。rebuild の import で隠し状態が表示に戻らないよう明示保持する。
位置キー `NSStatusItem Preferred Position*` は端末固有なので除外する。

## 除外したもの(個人情報 / 端末固有 / UI 状態 / テレメトリ)

| パターン | 理由 |
|---|---|
| `MS*` | Microsoft AppCenter テレメトリ (AltTab) |
| `SU*` | Sparkle 自動更新の state |
| `NSWindow Frame*`, `NSStatusItem Preferred Position*` | UI 位置 (端末固有) |
| `NSNavPanel*`, `NSOSPLast*` | Open ダイアログの最後の path |
| `SS_*`, `com_apple_SwiftUI*`, `welcomeDisplayed` | Sindre 系の launch count / 初回フラグ |

## 新 Mac での復元

`just rebuild`(home-manager activation)で AltTab/Mos が `defaults import`、
Plash は behavior 3 キーが `defaults write` される。以下は GUI で手動:

### Plash
- 壁紙 website(`file:///Users/<ユーザー名>/.dotfiles/configs/wallpaper/*.html`)は端末固有の
  security-scoped bookmark が要るため、初回のみ Browse から追加する。
  以降の rebuild は surgical write なので websites/bookmark を壊さない(再追加不要)。

### 権限(手動・SIP 保護のため CLI 不可)
- AltTab: アクセシビリティ + 画面収録
- Mos: アクセシビリティ + 入力監視
- ※ cask 更新で cdhash がずれると権限が stale 化して黙って効かなくなることがある。
  その場合は System Settings > Privacy & Security で対象アプリをオフ→オンし直す。

## 設定変更後の capture

GUI で設定を変えたら dotfiles に反映:

```bash
# AltTab (Container 外)
~/.dotfiles/scripts/capture-app-plist.py \
  ~/Library/Preferences/com.lwouis.alt-tab-macos.plist \
  ~/.dotfiles/configs/apps/com.lwouis.alt-tab-macos.plist \
  "MS*" "NSWindow Frame*" "SU*" "settingsWindowShownOnFirstLaunch"

# Mos (menubar 非表示 VisibleCC は残す。位置のみ除外)
~/.dotfiles/scripts/capture-app-plist.py \
  ~/Library/Preferences/com.caldis.Mos.plist \
  ~/.dotfiles/configs/apps/com.caldis.Mos.plist \
  "NSStatusItem Preferred Position*"

# Plash は plist を持たない(surgical write)。behavior を変えたら
# nix/home/darwin.nix の guiAppsPlistImport 内 defaults write を直接編集する。
```
