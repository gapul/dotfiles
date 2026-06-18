# dotfiles ゼロから再構築ガイド

## このドキュメントの目的

現状の `~/dotfiles` は機能豊富だが、自分が完全に理解していない部分がある。
**「自分が理解していないものを使いたくない」**という方針のもと、ゼロから作り直す。

このドキュメントは、初心者の自分でも迷わず進められるように、
**何を・なぜ・どの順で**やるかを段階的にまとめたもの。

---

## 大方針

### 1. 理解優先
- 各行・各ファイルが「なぜ必要か」説明できるまで進まない
- コピペで動かすことを目的にしない
- 動かない方が学べる、と割り切る

### 2. 最小から積み上げ
- 最初は「Nix が動く」だけで十分
- 一度に1つずつ機能を足す
- 完成形を最初から目指さない

### 3. 動くものを常に保つ
- 各ステップ終了時点で `darwin-rebuild switch` が通る状態を維持
- 壊れたら直してから次へ

### 4. 旧 dotfiles は捨てない
- 参照用に `~/dotfiles-archive/` として残す
- 移植時のリファレンスに使う
- ただし新リポジトリで直接importはしない（コピペ禁止）

---

## 事前準備

### Step 0: Nix を綺麗にインストールし直す

`NIX_REINSTALL.md` の手順で Nix を再インストール（暗号化なし）。
インストール時は `--determinate` を**外す**:

```bash
curl -fsSL https://install.determinate.systems/nix | sh -s -- install \
  --no-confirm --encrypt false
```

理由:
- `determinate-nixd` の常駐は個人用途では不要
- 上流 Nix の方が nix-darwin/home-manager との整合性が良い
- `nix-installer` 自体は使う（macOS APFS ボリューム管理の恩恵）

### Step 0.5: 旧 dotfiles をアーカイブ

```bash
mv ~/dotfiles ~/dotfiles-archive
mkdir ~/dotfiles
cd ~/dotfiles
git init
```

旧リポジトリは消さない。「あの設定どうやってたっけ」と参照する。

### Step 0.7: Flakes を有効化

`~/.config/nix/nix.conf` を作る:

```
experimental-features = nix-command flakes
```

確認:
```bash
nix --version              # 動くこと
nix flake --help           # flake サブコマンドが見えること
```

---

## フェーズ1: Flake の最小理解（Day 1）

### ゴール
`flake.nix` 1ファイルだけで `nix run` が動くようになる。

### 学ぶこと
- `flake.nix` とは何か
- `inputs` / `outputs` とは
- `nix run` の意味

### やること

1. `~/dotfiles/flake.nix` を作る:

```nix
{
  description = "yuki's dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    packages.aarch64-darwin.hello = nixpkgs.legacyPackages.aarch64-darwin.hello;
  };
}
```

2. 試す:
```bash
cd ~/dotfiles
git add flake.nix
nix run .#hello              # "Hello, world!" が出る
```

3. 各行が何をしているか、自分の言葉で説明できるか確認:
   - `description` は何か？
   - `inputs.nixpkgs.url` は何を指定している？
   - `aarch64-darwin` とは？（自分のマシンのアーキ）
   - `nixpkgs.legacyPackages` は何？
   - `nix run .#hello` の `.` と `#hello` の意味は？

### 完了条件
- 全ての行の意味を自分で説明できる
- `flake.lock` が生成されたこと、その役割を理解した

---

## フェーズ2: devShell（Day 2）

### ゴール
`nix develop` でプロジェクト固有の開発環境に入れる。

### 学ぶこと
- `devShell` の意味と使いどころ
- `mkShell` の役割
- なぜプロジェクトごとに devShell を作るのか

### やること

`flake.nix` に追加:

```nix
outputs = { self, nixpkgs }:
  let
    system = "aarch64-darwin";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [ pkgs.git pkgs.jq ];
    };
  };
```

試す:
```bash
nix develop                  # git と jq だけある最小shellに入る
which git jq                 # /nix/store/... のパスになる
exit
```

### 完了条件
- なぜ `let ... in` を使ったか説明できる
- `buildInputs` に1つ自分が使うツールを足してみる（例: `ripgrep`）

---

## フェーズ3: home-manager 最小（Day 3-4）

### ゴール
**ユーザー環境**（dotfiles, シェル設定, パッケージ）を home-manager で管理。

### 学ぶこと
- home-manager とは何か（vs nix-darwin）
- 「ユーザー」と「システム」の管理範囲の違い
- module とは何か

### やること

1. `flake.nix` に home-manager を input として追加:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

2. `home.nix` を作る（最小）:

```nix
{ pkgs, ... }: {
  home.username = "yuki";
  home.homeDirectory = "/Users/yuki";
  home.stateVersion = "24.05";

  home.packages = [
    pkgs.ripgrep
  ];

  programs.home-manager.enable = true;
}
```

3. `flake.nix` の outputs に追加:

```nix
homeConfigurations."yuki" = home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.aarch64-darwin;
  modules = [ ./home.nix ];
};
```

4. 適用:

```bash
nix run home-manager/master -- switch --flake .#yuki
which rg                     # home-manager 管理下の ripgrep
```

### 完了条件
- `home.stateVersion` の意味を理解する
- パッケージを1つ追加して再 switch できる
- なぜ `inputs.nixpkgs.follows = "nixpkgs"` を書くか説明できる

---

## フェーズ4: nix-darwin 最小（Day 5-6）

### ゴール
**システム設定**（macOS defaults, brew, システムパッケージ）を nix-darwin で管理。

### 学ぶこと
- nix-darwin とは
- home-manager との役割分担
- macOS 固有の設定をどう書くか

### やること

1. `flake.nix` に追加:

```nix
inputs.nix-darwin.url = "github:LnL7/nix-darwin";
inputs.nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
```

2. `darwin.nix` 作成（最小）:

```nix
{ pkgs, ... }: {
  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";

  environment.systemPackages = [ pkgs.coreutils ];

  # nix を nix-darwin 配下にする
  services.nix-daemon.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
```

3. outputs に追加:

```nix
darwinConfigurations."<your-hostname>" = nix-darwin.lib.darwinSystem {
  modules = [ ./darwin.nix ];
};
```

`<your-hostname>` は `scutil --get LocalHostName` で確認。

4. 初回適用:

```bash
nix run nix-darwin -- switch --flake .#<your-hostname>
```

以降:
```bash
darwin-rebuild switch --flake .
```

### 完了条件
- `system.stateVersion` の意味
- `environment.systemPackages` と `home.packages` の違いを説明できる

---

## フェーズ5: 統合と整理（Day 7〜）

### ゴール
flake.nix がモジュール分割され、見通しが良くなる。

### やること（順次）

1. `home.nix` の中身をテーマ別にファイル分割
   - `home/shell.nix`: zsh, starship
   - `home/editor.nix`: neovim
   - `home/git.nix`: git設定
   - `home/terminal.nix`: wezterm, ghostty

2. `darwin.nix` 同様
   - `darwin/system.nix`: defaults
   - `darwin/homebrew.nix`: brew bundle 相当

3. `flake.nix` 自身も整理（`lib/` で重複削減など）

### 重要な原則
- **必要になったら分割する**。最初から分けない
- ファイルが200行超えたら分割を検討
- 「これは何のため？」が分かりにくくなったら分割

---

## フェーズ6: 旧 dotfiles からの移植（Day 7〜随時）

### やり方

1. 旧 `~/dotfiles-archive/` から**移植したい機能を1つ選ぶ**
2. その機能のコードを読み、**何をしているか自分の言葉で説明**
3. 新 dotfiles に**自分で書き直す**（コピペしない）
4. 動作確認
5. コミット
6. 次の機能へ

### 移植優先度の目安

| 優先度 | 機能 |
|---|---|
| 高 | zsh/starship、git設定、neovim、よく使うCLIツール |
| 中 | wezterm/ghostty設定、aerospace、yazi |
| 低 | あまり使っていないツール、複雑な自動化スクリプト |
| 後回し | マルチプラットフォーム対応、CI/CD |

**マルチプラットフォームと CI/CD は最後**。まず macOS 単体で完璧に動くものを作る。

---

## フェーズ7: マルチプラットフォーム（必要になったら）

Linux/WSL/Android は実際にそのマシンを使い始めてから対応する。
「いつか必要」では入れない。

---

## 日々の運用

### 設定変更時
```bash
cd ~/dotfiles
# ファイル編集
darwin-rebuild switch --flake .       # システム反映
home-manager switch --flake .#yuki    # ユーザー設定反映（必要なら）
git add -A && git commit -m "..."
```

### 最新追従
```bash
nix flake update              # 全input更新
darwin-rebuild switch --flake .
# 問題なければ commit
```

### 巻き戻し
```bash
git checkout HEAD~1 -- flake.lock
darwin-rebuild switch --flake .
```

---

## アンチパターン（避けること）

### ❌ Phase 4で旧 dotfiles をまるごとコピー
理解せずにコピペすると、また同じ「ぐちゃぐちゃ」になる

### ❌ 最初からマルチプラットフォーム対応
複雑度が跳ね上がる。macOS 単体で動かしてから

### ❌ ChatGPT/Claude に「全部書いて」と頼む
今回の方針に反する。**説明と検証**には使うが、**生成して使う**のは禁止

### ❌ 動かないまま次のフェーズに進む
壊れた状態で積み上げると原因特定が困難になる

### ❌ stateVersion を後から変える
home-manager や nix-darwin の `stateVersion` は **初回設定のまま固定**。
これはバージョン番号ではなく「いつ書き始めたか」のマーカー

---

## 各フェーズの完了チェックリスト

- [ ] フェーズ1: `nix run .#hello` が動く / flake.nix の全行を説明できる
- [ ] フェーズ2: `nix develop` で開発shellに入れる / mkShell の役割を理解
- [ ] フェーズ3: `home-manager switch` で1つパッケージが入る
- [ ] フェーズ4: `darwin-rebuild switch` でシステム反映できる
- [ ] フェーズ5: ファイル構成がテーマ別に分かれている
- [ ] フェーズ6: 旧 dotfiles の主要機能が移植済み
- [ ] フェーズ7: 必要に応じてマルチプラットフォーム対応

---

## 困った時の指針

### エラーが出た
1. メッセージを**全部読む**（流し読みしない）
2. 関連ファイルを Read で確認
3. それでも分からなければ Claude に「このエラーは何を意味する？」と聞く（**修正コードはもらわず説明だけ**）
4. 自分で直す

### 詰まった
- 一度フェーズを戻して動く状態に戻す
- 「動く最小」と「壊れた状態」の差分を見る

### モチベ低下
- 旧 dotfiles-archive を眺める → 自分が以前は動かせていたことを思い出す
- 完了したフェーズの数を見る → 確実に前進している

---

## 参考リソース

- Nix公式: https://nix.dev/
- home-manager manual: https://nix-community.github.io/home-manager/
- nix-darwin: https://github.com/LnL7/nix-darwin
- nixpkgs検索: https://search.nixos.org/packages
- 旧dotfiles: `~/dotfiles-archive/`（参照用）

---

## このドキュメント自体の運用

- 各フェーズ終わったらチェックを入れる
- 詰まったポイントは「困った時の指針」に追記
- 完了したらこのドキュメントを `docs/HISTORY.md` などにリネームして記念に残す
