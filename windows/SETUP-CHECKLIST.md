# Windows 実機セットアップ チェックリスト

macOS 上で前段階(設定ファイル整備)は済んでいる。実機ではこの順で進める。
各ステップの「確認」を満たしてから次へ。

---

## 0. 前提・準備

- [ ] Windows 11 (PowerShell 7 = `pwsh` が使えること。無ければ後述の winget で入る)
- [ ] BitLocker が有効か確認 (`manage-bde -status C:`)。秘密鍵を置くので**ディスク暗号化は必須**
- [ ] Bitwarden 等に age 秘密鍵 / SSH 秘密鍵を準備しておく

## 1. clone

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # ローカルスクリプト許可
git clone https://github.com/gapul/dotfiles.git $env:USERPROFILE\dotfiles
```

- 確認: `%USERPROFILE%\dotfiles\windows\bootstrap.ps1` が存在
- 注意: Windows ネイティブの clone 先は **`%USERPROFILE%\dotfiles`(ドット無し)**。
  macOS/WSL の `~/.dotfiles` とは非対称(プラットフォーム慣習による意図的なもの)

## 2. winget パッケージ ID の実在確認 ★最重要

`windows/winget/apps.json` の ID は macOS から書いた**下書き**。import 前に実在を確認:

```powershell
# 1件ずつ確認する例
winget search Git.Git
# まとめて確認したい場合 (存在しない ID は "見つかりません" になる)
(Get-Content $env:USERPROFILE\dotfiles\windows\winget\apps.json | ConvertFrom-Json).Sources[0].Packages.PackageIdentifier |
  ForEach-Object { "{0,-32} {1}" -f $_, (winget show $_ 2>&1 | Select-String -Quiet 'Found') }
```

- [ ] 存在しない ID は apps.json から削除 or 正しい ID に修正
- 要確認(macOS から ID 不確実)の候補と、apps.json に**未収録**で必要なら手で足すもの:
  - `sops` (getsops) … winget ID 要確認。無ければ scoop / 手動
  - `gitleaks`, `typst`, `bottom`(btm), `mpv` … ID 要確認
  - **Nerd Font** (JetBrainsMono NF) … winget に確実な公式が無い。
    [ryanoasis/nerd-fonts] の手動 install か scoop `nerd-fonts` bucket を使う。
    Terminal の `fontFace` がこのフォント前提なので、入れないと豆腐になる
  - Tor Browser / Zen / Beeper / Affinity 等 GUI は実機で要否を判断して追加

## 3. bootstrap 実行 (管理者 PowerShell 推奨)

```powershell
# 既定 (WSL=Ubuntu / ユーザー=Windows の $env:USERNAME)
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1
# 別ユーザー/distro の場合
& $env:USERPROFILE\dotfiles\windows\bootstrap.ps1 -WslUser alice -WslDistro Debian
```

bootstrap がやること:
1. winget 確認 → `apps.json` を `winget import`
2. `$PROFILE` を symlink
3. Windows Terminal `settings.json` を**生成**(`__WSL_USER__`/`__WSL_DISTRO__` 置換)
4. age/SSH 鍵が在れば `icacls` で本人のみに ACL 制限
5. git global config

- [ ] symlink 作成に失敗する場合 → 管理者で実行 or 開発者モードを有効化
      (設定 → プライバシーとセキュリティ → 開発者向け)
- [ ] 既存の `$PROFILE` / WT settings は `.bak-<日時>` に退避される

## 4. 鍵配置 + 権限確認

- [ ] age 秘密鍵を `%USERPROFILE%\.config\sops\age\keys.txt` に配置
- [ ] SSH 秘密鍵を `%USERPROFILE%\.ssh\id_ed25519` に配置
- [ ] bootstrap を**再実行** → `icacls` で ACL が本人のみに絞られる
- 確認: `icacls $env:USERPROFILE\.ssh\id_ed25519` が現在ユーザーのみ
       (これをやらないと OpenSSH が "bad permissions" で鍵を拒否)
- [ ] 署名/push する場合は GitHub に公開鍵を登録 (`gh ssh-key add` 等)

## 5. WSL2 (Linux 環境)

```powershell
wsl --install -d Ubuntu        # 管理者。再起動が要る場合あり
```

WSL に入ってから:
```bash
git clone https://github.com/gapul/dotfiles.git ~/.dotfiles
~/.dotfiles/scripts/bootstrap-wsl.sh
```

- [ ] `bootstrap-wsl.sh` が home-manager(`#homeConfigurations.<user>-wsl`)を switch
- 確認: `wslview` / `pbcopy`(clip.exe) / `explorer` 関数が動く
- 注意: Terminal の WSL プロファイルの `startingDirectory` は bootstrap で
        `//wsl$/<distro>/home/<user>` に展開済み。distro/user が違うと開けないので
        `-WslDistro`/`-WslUser` を合わせること

## 6. 動作確認

- [ ] 新しい PowerShell: `starship` プロンプトが macOS と同じ見た目か
      (`$env:STARSHIP_CONFIG` が `...\dotfiles\configs\shell\starship.toml` を指す)
- [ ] `v` / `vim` で nvim が開く
- [ ] `zoxide` (`z`) が動く
- [ ] Windows Terminal: 既定が WSL(Ubuntu) プロファイル、フォントが Nerd Font
- [ ] `g`/`gs`/`ga` 等 git エイリアス

---

## まだ未対応 / 実機で詰める論点

- **SOPS 復号のネイティブ導線が無い**: Windows ネイティブ側は age 鍵を置くだけで、
  secrets を復号して使う仕組みは未定義。当面は **WSL 側(sops-nix)で復号**して使う想定。
  ネイティブで必要になったら `sops -d` を叩くラッパーを profile に足す
- **フォント自動化**: Nerd Font の winget 公式が無いため手動 or scoop。自動化したいなら
  bootstrap に scoop + nerd-fonts bucket 導入を足す
- **winget の宣言的運用の限界**: import は入れるだけで「宣言外を消す」機能が無い
  (Nix の `cleanup="uninstall"` 相当が無い)。不要 app は手動 uninstall
- **profile の高度化** (oh-my-posh / PSFzf / Terminal-Icons) は実機で描画確認しながら
