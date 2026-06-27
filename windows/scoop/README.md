# Scoop (winget サブセット)

`winget` で取得できない MS Store 専用 app を sideload する目的で Scoop を併用する。
GUI / 公式 CLI は `windows/winget/apps.json`、それ以外で必要なものを `scoop.json` に置く。

## 方針

| 入れる先 | 対象 |
|---|---|
| `winget` (apps.json) | GUI app / 公式 CLI / system 統合 / 認証重視 |
| `scoop` (scoop.json) | MS Store 専用 (Files 等) / portable / nonportable bucket |

## 構成

```
windows/scoop/
├── README.md
├── scoop.json   # bucket + app の declarative 定義
└── apply.ps1    # scoop 未導入なら install → bucket add → app install
```

## 実行

```powershell
# DryRun (副作用なし)
just win-scoop -DryRun

# 本番
just win-scoop
```

bootstrap.ps1 の Step 2.5 として自動実行される。skip したい時:

```powershell
pwsh -File windows/bootstrap.ps1 -SkipScoop
```

`apply.ps1` には `-SkipBuckets` / `-SkipApps` もある。

## scoop.json の書式

```json
{
  "buckets": ["nonportable", "extras"],
  "apps": ["files-np", "another-app"]
}
```

- `buckets`: `scoop bucket add` で登録する追加 bucket
- `apps`: `scoop install` で入れる app。bucket 名のプレフィクスは scoop が自動解決

## 何故 MS Store を避けるか

- MSIX は `C:\Program Files\WindowsApps\` の TrustedInstaller 領域に入って設定 symlink できない
- インストール履歴が MS アカウントに紐付く (テレメトリ方針と矛盾)
- オフラインで再現できない (Store ログイン必須)
- 配布チャネル次第で有料化や撤去のリスクあり (Files は Store だと有料、GitHub MSIX は無料、という非対称)

`nonportable` bucket は GitHub Release から MSIX を取得して sideload するため、これらの問題を回避できる。
