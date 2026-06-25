# Windows ネイティブ環境(WSL 外)

Windows 上で動く部分(PowerShell, winget, Windows Terminal 等)の dotfiles。
WSL2 側の Linux 環境は `~/.dotfiles/nix/home/wsl.nix` で別管理。

## 構成

```
windows/
├── README.md
├── bootstrap.ps1                              # 0→1 セットアップ
├── profile/
│   └── Microsoft.PowerShell_profile.ps1       # $PROFILE
├── winget/
│   └── apps.json                              # winget 宣言的 import 形式
└── terminal/
    └── settings.json                          # Windows Terminal
```

## 初回セットアップ

PowerShell 7 (`pwsh.exe`) を管理者で開いて:

```powershell
# 実行ポリシーを ローカルスクリプト許可に
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# dotfiles を clone (git は winget で別途入れるか手動)
git clone https://github.com/gapul/dotfiles.git $env:USERPROFILE\dotfiles

# bootstrap 実行
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1
```

## bootstrap.ps1 が何をするか

1. **winget** が無ければ Microsoft Store 経由で install を促す
2. `winget/apps.json` を `winget import` で一括 install
3. PowerShell `$PROFILE` を symlink (`profile/Microsoft.PowerShell_profile.ps1`)
4. Windows Terminal の `settings.json` を生成 (`__WSL_USER__`/`__WSL_DISTRO__` を実値へ置換。
   既定は `-WslUser $env:USERNAME -WslDistro Ubuntu`、別ユーザー/distro は引数で上書き)
5. age 鍵 / SSH 鍵が在れば ACL を本人のみに制限 (icacls)。無ければ警告
6. git の global config 設定

## 何が含まれない

- 具体的にどの app を入れるか — `winget/apps.json` に追記して決める
- WSL の install — Windows 機能を有効化するのは Windows 側手動
  - PowerShell: `wsl --install -d Ubuntu`
  - WSL 側で `~/.dotfiles/scripts/bootstrap-wsl.sh` を走らせる

## 設定変更後の反映

PowerShell プロファイル: ファイル編集後 `. $PROFILE` で再読込

Windows Terminal: 設定ファイル変更後 Terminal を再起動
