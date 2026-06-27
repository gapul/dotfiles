# Windows プライバシー / 標準機能 declarative 化

Mac の `nix/hosts/darwin.nix` の `system.defaults` 相当を Windows でも宣言的に管理する。
**WinUtil**(プライバシー + Service / Performance / Features)と
**Win11Debloat**(UWP プリイン削除)の併用。

## 構成

```
windows/privacy/
├── README.md
├── winutil-config.json     # ChrisTitusTech/winutil の export 設定
├── win11debloat-args.txt   # Raphire/Win11Debloat の CLI 引数(空行/`#` コメント可)
└── apply.ps1               # 両者を順に呼ぶ orchestrator
```

## 実行

```powershell
# DryRun(副作用なしで何が走るか確認)
just win-privacy -DryRun
pwsh -File windows/privacy/apply.ps1 -DryRun

# 本番(管理者要、UAC promp あり)
just win-privacy
```

実行内容:
1. `Win11Debloat`(`irm https://win11debloat.raphi.re/ | iex`)を一時取得 →
   `win11debloat-args.txt` の引数で **自動実行**(`-Silent -RunDefaults` 等)
2. `WinUtil`(`irm https://christitus.com/win | iex`)を一時取得 →
   `winutil-config.json` を引数で渡して **GUI 起動**。GUI で **Import → Apply**

WinUtil の CLI 自動 apply は version によって挙動が変わるため、本リポは GUI 経由の
半自動運用(設定は declarative、最終 Apply はユーザー操作)を採用。

## 設定の変更

### Win11Debloat
`win11debloat-args.txt` を編集。1 行 1 引数(空行と `#` コメント可)。
利用可能な引数は <https://github.com/Raphire/Win11Debloat#options> を参照。

現状の引数(19 個):

- 必須: `-Silent`
- UWP 削除: `-RemoveApps` / `-RemoveCommApps`(Mail/Calendar/People)/ `-RemoveDevApps`(3D Builder/MR)/ `-RemoveW11Outlook`(新 Outlook)/ `-RemoveGamingApps`(Xbox 一式)
- テレメトリ/AI: `-DisableTelemetry` / `-DisableBing` / `-DisableCopilot` / `-DisableRecall`
- 通知/誘導: `-DisableLockscreenTips` / `-DisableSuggestions` / `-DisableSticky` / `-DisableWidgets`
- ストレージ: `-DisableOnedrive`(Syncthing 代替前提)
- エクスプローラ: `-ShowHiddenFolders` / `-ShowKnownFileExt` / `-HideHome` / `-HideGallery`

### WinUtil
1. 実機で WinUtil を起動: `irm https://christitus.com/win | iex`
2. GUI でチェックを入れて選択
3. `Settings → Export Config` で JSON 保存
4. 保存先を `windows/privacy/winutil-config.json` に置き換え → commit

## bootstrap への組み込み

`bootstrap.ps1` のステップ 7 として自動実行される。skip したい時は:

```powershell
pwsh -File windows/bootstrap.ps1 -SkipPrivacy
# or
just win-bootstrap -SkipPrivacy
```

後から個別に適用:

```powershell
just win-privacy           # 本番
just win-privacy -DryRun   # 副作用確認
```

`apply.ps1` は `-SkipWinUtil` / `-SkipWin11Debloat` で片方だけ実行も可能。

## 補完できないもの

- 個別レジストリ書き換えで両ツールに含まれない tweak は別途 `apply.ps1` の
  `$ExtraRegistry` 配列に追加(declarative 拡張ポイント)
- macOS の `CustomUserPreferences` 相当の細かい設定は、各アプリ専用ポリシー
  (Chrome の Enterprise Policy 等)で対応
