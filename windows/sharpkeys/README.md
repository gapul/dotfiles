# Windows 物理キー remap

Mac の Karabiner-Elements のキー remap 部分を Windows で再現。
SharpKeys と同じ仕組み(`HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout\Scancode Map`)を、
SharpKeys GUI に依存せず PowerShell で declarative に書き換える。

## 構成

```
windows/sharpkeys/
├── README.md
├── keymap.skl   # 人間可読の SharpKeys 形式 (参照用 — 実体は apply.ps1 内の $Mappings 配列)
└── apply.ps1    # Scancode Map を組み立ててレジストリに書き込む
```

## 実行

```powershell
# 適用 (管理者要、再起動で反映)
just win-keymap

# 副作用なし確認
just win-keymap -DryRun

# remap を全削除して standard layout に戻す
just win-keymap -Clear
```

bootstrap.ps1 の Step 8 として自動実行される。skip したい時:

```powershell
pwsh -File windows/bootstrap.ps1 -SkipKeymap
```

## 現状の remap

| 機能 | 状態 |
|---|---|
| CapsLock → Left Ctrl | ✅ 適用済 (scancode 0x3A → 0x1D) |
| Copilot key → Right Ctrl | ⏳ 実機 scancode 検証待ち |

## Copilot key の scancode 調査

Win11 OEM の Copilot 専用キーは機種により異なる:

- **HP の一部機種**: scancode `0xE0 0x5C`(extended)
- **Lenovo**: Win + Shift + F23 のシーケンス(scancode レベル remap 不可)
- **その他**: `vk89` / `F23` 等

調査方法(AutoHotkey の Key History を使う):

1. AHK スクリプトを起動した状態で Copilot キーを押す
2. AHK のタスクトレイ右クリック → `Open` → `View` → `Key history and script info`
3. ログから scancode を確認

scancode が `E0 5C` のようなら `apply.ps1` の `$Mappings` に有効化:

```powershell
@{ Source = 'E05C'; Dest = 'E01D'; Comment = 'Copilot -> Right Ctrl' }
```

`LSHIFT+LWIN+F23` のような **combination** だった場合は scancode 単独では remap 不可。
その場合は **AHK 側** で `+#F23::RControl` のように remap する。

## 組合せ remap (Ctrl+A → Home 等) は別レイヤー

SharpKeys / Scancode Map は **キー単体の 1 対 1 remap** のみ。
Emacs ショートカット(Ctrl+A → Home 等)は `windows/autohotkey/keymap.ahk` で実装。
