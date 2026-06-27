# Windows フォント declarative install

`configs/fonts/` 配下の `.ttf` / `.otf` を Windows に user-scope install する。
Mac の home-manager で `font-*` cask を入れるのと同じ精神で declarative 化。

## 構成

```
windows/fonts/
├── README.md
└── apply.ps1   # configs/fonts/*.ttf|.otf を user-scope install
```

## 実行

```powershell
just win-fonts            # 本番
just win-fonts -DryRun    # 副作用確認
just win-fonts -Force     # 既存も強制上書き
```

bootstrap.ps1 でも自動実行(`-SkipFonts` で省略可)。

## install 場所

- ファイル: `%LOCALAPPDATA%\Microsoft\Windows\Fonts\`
- レジストリ: `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts`
- 管理者権限不要(Windows 10 1809 以降 user-scope サポート)

## 主な用途

- **sketchybar-app-font.ttf**: Zebar bar.html で focused app icon を
  process 名 → `:app_name:` ligature 変換するための専用フォント
  (Mac SketchyBar と同じ icon mapping を再現)

## HackGen Console NF について

apps.json / scoop どちらにも未収録のため、yuru7/HackGen の GitHub Release
から `.zip` を DL → 解凍 → `configs/fonts/` に置けば apply.ps1 で install。

```powershell
# 例: HackGen_NF release を取得
$url = (gh release view --repo yuru7/HackGen --json assets --jq '.assets[] | select(.name | contains("NF")) | .url' | Select-Object -First 1)
# 手動 DL → 解凍 → configs/fonts/ にコピー
```
