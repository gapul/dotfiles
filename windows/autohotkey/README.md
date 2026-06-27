# Windows 組合せキー remap (AutoHotkey)

SharpKeys / Scancode Map では実現できない **組合せ remap** を担当する。

| レイヤー | ファイル | できること |
|---|---|---|
| 物理キー単体 (永続) | `windows/sharpkeys/` | CapsLock → Ctrl 等の 1 対 1 |
| **組合せキー** (常駐) | `windows/autohotkey/keymap.ahk` | Ctrl+A → Home 等の Emacs ショートカット、コンテキスト依存 |

## 構成

```
windows/autohotkey/
├── README.md
└── keymap.ahk   # AHK v2 スクリプト
```

## 起動

`bootstrap.ps1` が `keymap.ahk` を `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\`
に symlink するため、ログイン時に自動起動する。

リロード:

```powershell
just win-keymap   # sharpkeys 適用 + AHK 再起動
```

手動:
- AHK が常駐していれば、`.ahk` ファイル右クリック → `Run Script` で再ロード
- またはタスクトレイ AHK アイコン右クリック → `Reload Script`

## 実装内容

### 1. Copilot キー → 右 Ctrl (scancode 単独 remap 不可な機種向け保険)

Win11 OEM の Copilot 専用キーは機種によって挙動が違う:

| 機種 | 送信内容 | 対処 |
|---|---|---|
| HP 一部 | scancode `0xE0 0x5C`(extended) | SharpKeys (Scancode Map) で完結 |
| Lenovo / 一部 24H2 | `LShift + LWin + F23`(キーシーケンス) | **scancode remap 不可 → AHK 担当** |

実機の挙動確認:
1. AHK 起動中にタスクトレイ右クリック → `Open` → `View` → `Key history`
2. Copilot キーを押す → ログから scancode を確認
3. `keymap.ahk` の Copilot 行を実機に合うものに切り替え

### 2. Emacs ショートカット復活

macOS は Cocoa text field 全般で Emacs キーバインドが標準で効く。Windows はデフォルトでは効かない。
AHK で emulate する。

| key | 動作 |
|---|---|
| `Ctrl+A` | 行頭(Home) |
| `Ctrl+E` | 行末(End) |
| `Ctrl+B` | 1 文字左 |
| `Ctrl+F` | 1 文字右 |
| `Ctrl+P` | 1 行上 |
| `Ctrl+N` | 1 行下 |
| `Ctrl+H` | 1 文字削除(前) |
| `Ctrl+D` | 1 文字削除(後) |
| `Ctrl+K` | 行末まで kill |

#### 除外コンテキスト

- ターミナル系: `ConsoleWindowClass` / `CASCADIA_HOSTING_WINDOW_CLASS` / `WezTermWindow` / `mintty`
- エディタ系: `Vim` / VS Code / Cursor / nvim / Hyper

これらでは Ctrl+A=全選択 等の元の意味を尊重。WinTitle Class または Process 名で判別。

### カスタマイズ

`EmacsExcludeClasses` / `EmacsExcludeProcesses` に追加してその app では Emacs binding を無効化:

```ahk
EmacsExcludeProcesses := "i)^(WezTerm|wt|alacritty|Code|MyApp)\.exe$"
```
