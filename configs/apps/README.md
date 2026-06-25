# GUI アプリ plist 管理

主に menubar / 入力系ユーティリティの設定を `defaults import` で復元する。

## 管理対象

| App | plist | 説明 |
|---|---|---|
| **AltTab** | `com.lwouis.alt-tab-macos.plist` | Cmd+Tab 代替の Window switcher。外見系設定のみ管理(キーバインドは secureData blob で含まれる) |
| **Mos** | `com.caldis.Mos.plist` | スクロール挙動 (smooth/reverse/speed)、menubar 非表示 |
| **Plash** | `com.sindresorhus.Plash.plist` | 動的壁紙。**website 設定は含まれない**(security-scoped bookmark が必須で各 Mac で再追加要)、behavior 系のみ管理 |
| **Shortcat** | `com.sproutcube.Shortcat.plist` | キーボードでマウス操作。keybindings + continuousMode |

## 除外したもの(個人情報 / 端末固有 / UI 状態 / テレメトリ)

| パターン | 理由 |
|---|---|
| `MS*` | Microsoft AppCenter テレメトリ (AltTab) |
| `SU*` | Sparkle 自動更新の state |
| `NSWindow Frame*`, `NSStatusItem*` | UI 位置 (端末固有) |
| `NSNavPanel*`, `NSOSPLast*` | Open ダイアログの最後の path |
| `SecurityScopedBookmarkManager*`, `__securityScopedBookmarks__` | Plash の Bookmark blob (端末固有・file:// path 込) |
| `display` | Plash の Display UUID (Mac 固有) |
| `SS_*`, `com_apple_SwiftUI*`, `welcomeDisplayed` | Sindre 系の launch count / 初回フラグ |
| `telemetryIdentifier` | Shortcat の telemetry ID |
| `websites` (Plash) | bookmark なしでは無意味なので除外 |

## 新 Mac での復元

`just rebuild`(home-manager activation)で 4 つの plist が `defaults import` される。
ただし以下は **GUI で手動再設定** が必要:

### Plash
1. 設定 → Display を選択
2. Website を追加 → `file:///Users/<ユーザー名>/.dotfiles/configs/wallpaper/aurora.html` を指定
   (Browse ボタンから選択しないと security-scoped bookmark が取れない)

### AltTab
- キーバインドは plist の secureData blob に含まれてるので import で復元される
- ただし system 設定で「アクセシビリティ権限」「画面収録権限」付与は手動

### Shortcat
- アクセシビリティ権限付与は手動

### Mos
- アクセシビリティ権限 + 入力監視権限付与は手動

## 設定変更後の capture

GUI で設定を変えたら dotfiles に反映するには:

```bash
# AltTab (Container 外)
~/.dotfiles/scripts/capture-app-plist.py \
  ~/Library/Preferences/com.lwouis.alt-tab-macos.plist \
  ~/.dotfiles/configs/apps/com.lwouis.alt-tab-macos.plist \
  "MS*" "NSWindow Frame*" "SU*" "settingsWindowShownOnFirstLaunch"

# Mos
~/.dotfiles/scripts/capture-app-plist.py \
  ~/Library/Preferences/com.caldis.Mos.plist \
  ~/.dotfiles/configs/apps/com.caldis.Mos.plist \
  "NSStatusItem*"

# Plash (sandboxed, Container 内)
~/.dotfiles/scripts/capture-app-plist.py \
  ~/Library/Containers/com.sindresorhus.Plash/Data/Library/Preferences/com.sindresorhus.Plash.plist \
  ~/.dotfiles/configs/apps/com.sindresorhus.Plash.plist \
  "__securityScopedBookmarks__" "display" "NSWindow*" "NSNavPanel*" "NSOSPLast*" \
  "SecurityScopedBookmarkManager*" "SS_*" "com_apple_SwiftUI*" "websites"

# Shortcat
~/.dotfiles/scripts/capture-app-plist.py \
  ~/Library/Preferences/com.sproutcube.Shortcat.plist \
  ~/.dotfiles/configs/apps/com.sproutcube.Shortcat.plist \
  "telemetryIdentifier" "NSStatusItem*" "NSWindow*" "SU*" "welcomeDisplayed"
```
