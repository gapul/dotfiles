# Windows ロケール / 言語設定

英語 UI で動かしつつ、SJIS 由来の文字化け (`\` が `¥` で表示される等) を解消する。

## 構成

```
windows/locale/
├── README.md
└── apply.ps1   # 3 段階で declarative に適用
```

## 適用内容(3 段階)

### A. User Language List = `ja-JP` 1 個 / IME = CorvusSKK のみ / UI = en-US Override

- `en-US` 言語を削除 → **英語キーボードレイアウト (0409:00000409) が消える**
- `ja-JP` の `InputMethodTips` を CorvusSKK 1 個に → MS-IME が消える
- 結果: タスクバーの言語インジケーターは SKK 1 個のみ、`Win+Space` 切替表示なし
- 英語入力は **CorvusSKK の直接入力モード** (`l` キーで切替) で行う
- UI Display は `Set-WinUILanguageOverride en-US` で英語に固定
- **再ログイン**で完全反映

CorvusSKK の TIP は install 時に固定 CLSID で登録される(ユーザー間で共通):
- ProfileGUID: `{956F14B3-5310-4CEF-9651-26710EB72F3A}`
- CLSID: `{EAEA0E29-AA1E-48EF-B2DF-46F4E24C6265}`

### B. System Locale = `en-US` + CodePage 65001 (UTF-8)

- 非 Unicode プログラムを SJIS (CP932) から UTF-8 (CP65001) に切替
- **`\` が `¥` で表示される根本原因の SJIS 解消**
- cmd / PowerShell の console code page も 65001 化
- Win10 の "Use Unicode UTF-8 for worldwide language support" Beta 機能と同等
- **再起動必須**(CodePage は OS 起動時にしか効かない)

### C. Home Location = United States (GeoId 244)

- Region を US 化
- 時計 / 通貨 / 天気 app 等が英語表記
- 日本在住で時刻 / 通貨は日本のままがいい場合は `-SkipHomeLocation`

## 実行

```powershell
# DryRun (副作用なし)
just win-locale -DryRun

# 本番 (自動 UAC、B 適用後は要再起動)
just win-locale

# 部分適用
just win-locale -SkipSystemLocale   # 言語順序と Home だけ (再起動不要)
just win-locale -SkipHomeLocation   # 言語順序と System Locale (日本地域は残す)
```

bootstrap.ps1 の Step 9 として自動実行される。skip したい時:

```powershell
just win-bootstrap -SkipLocale
```

## 元に戻したい時

Settings → Time & Language → Language で個別変更、または:

```powershell
Set-WinUserLanguageList -LanguageList 'ja', 'en-US' -Force
Set-WinSystemLocale -SystemLocale ja-JP
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' 'ACP' '932'
Set-WinHomeLocation -GeoId 122
```
