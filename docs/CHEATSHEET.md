# Daily-Use Cheatsheet

このマシンで現代モダン CLI 環境を回すためのコマンド集。
詳細な背景は [README.md](../README.md) を参照。

---

## 🎯 まず覚えるショートカット 6 つ

| キー / コマンド | 何 |
|---|---|
| **Ctrl+G** | fzf で全 ghq repo から fuzzy 選択 → cd |
| **Ctrl+R** | atuin で履歴 fuzzy 検索 |
| **`<TAB>`** | fzf-tab で fuzzy 補完(全コマンドで効く) |
| `just rebuild` | 設定変えたら呼ぶ |
| `gita ll` | 全 repo の brunch + dirty 状態を 1 画面 |
| `tldr <cmd>` | 分からない時の即席 man page |

これだけ覚えれば日常はだいたい回る。

---

## 🔄 システム管理 (Justfile)

| コマンド | 何 |
|---|---|
| `just` | レシピ一覧 |
| `just rebuild` | nh darwin switch + nh home switch |
| `just update` | flake input 更新 → rebuild |
| `just upgrade` | brew + cask(`--greedy`)+ mas + Nix 全部最新化 |
| `just gc` | 古い世代削除 + nix store gc(`--keep 5 --keep-since 7d`) |
| `just check` | 構文/型チェック(ビルドはしない) |
| `just diff` | 現在のシステムと flake の差分 |
| `just doctor` | 環境ヘルスチェック(再起動後 / Determinate upgrade 後) |

---

## 📂 ファイル操作

eza / bat が ls / cat を置き換え済(home-manager が auto-alias)。

| 入力 | 中身 |
|---|---|
| `cat <file>` | bat — シンタックスハイライト + line number |
| `ls` | eza --icons=auto --git |
| `ll` | eza -l --icons=auto --git |
| `la` | eza -a --icons=auto --git |
| `lt` | eza tree |
| `bottom` / `btm` | システムモニタ TUI(top 置換) |
| `gdu` / `dust` / `diskonaut` | ディスク使用量可視化 |
| `yazi` | ファイラ TUI |

---

## 🚀 移動

| キー / コマンド | 何 |
|---|---|
| **Ctrl+G** | fzf で repo 横断選択(ghq + 自作 widget) |
| `cd <TAB>` | fzf-tab で fuzzy + preview(eza が出る) |
| `z <name>` | zoxide(履歴頻度で cd) |
| `ghq look <repo>` | 該当 repo の subshell に移動 |

---

## 🌳 git repo 管理(ghq + gita)

### ghq(配置)

| コマンド | 何 |
|---|---|
| `ghq get owner/repo` | `~/ghq/<host>/<owner>/<repo>` に clone |
| `ghq get <https or ssh URL>` | URL 渡しても OK |
| `ghq list` | 管理下の全 repo を相対パスで一覧 |
| `ghq list -p` | フルパスで一覧(スクリプト用) |
| `ghq look <name>` | 該当 repo に subshell で移動 |
| `ghq root` | ghq.root の値 (~/ghq) |

### gita(横断操作)

| コマンド | 何 |
|---|---|
| `gita ll` | 全 repo の brunch / dirty / 最終 commit |
| `gita ls` | repo 名一覧 |
| `gita add <path>` | 個別追加 |
| `gita-sync` | ghq list の全 repo を gita に再登録 |
| `gita super pull` | 全 repo まとめて pull |
| `gita super -- repoA repoB pull` | 一部のみ |
| `gita super exec ls` | 任意コマンドを横断実行 |
| `gita group add -n work repoA repoB` | グループ作成 |
| `gita super -g work pull` | グループだけ操作 |
| `gita info <repo>` | 該当 repo のパス |

---

## 🔍 検索 / 補完

| コマンド | 何 |
|---|---|
| `<TAB>` | fzf-tab 起動(git/cd/kill/checkout 等は preview 付き) |
| **Ctrl+R** | atuin 履歴 fuzzy 検索(複数端末同期、global がデフォルト) |
| **Ctrl+R(検索中もう一度)** | filter mode 切替: global → host → session → directory → workspace |
| **Ctrl+S(検索中)** | search mode 切替: fuzzy → prefix → fulltext |
| **Tab(検索中)** | 候補を確定して shell に挿入(編集モード、誤爆防止) |
| **Enter(検索中)** | 候補を即実行 |
| `fd <pattern>` | 高速ファイル名検索 |
| `rg <pattern>` | 高速 grep(ripgrep) |
| `fzf` | 標準入力から fuzzy 選択 |

---

## 🔧 git 体験

| コマンド | 何 |
|---|---|
| `git diff` | delta で side-by-side + line-number(自動 pager) |
| `g status` / `gs` | エイリアス |
| `ga` `gc` `gp` `gl` | add/commit/push/pull のエイリアス |
| `lazygit` | git TUI |
| `lazyjj` | jj(jujutsu) TUI |
| `just dev install` | pre-commit hook を `.git/hooks/pre-commit` に (新 Mac 初回) |
| `just dev` | devShell に入る (shellcheck/statix 使用可) |

---

## 📝 知りたい時

| コマンド | 何 |
|---|---|
| `tldr <command>` | 1 画面の使用例(`tldr tar`、`tldr ffmpeg`) |
| `man <command>` | 詳細マニュアル |
| `nh search <pkg>` | nixpkgs から package 検索 |
| `, <unknown-cmd>` | install せず試す(`, asciinema rec`) |

---

## 🔒 機密管理 (SOPS)

| コマンド | 何 |
|---|---|
| `just secrets-edit` | sops で `secrets/secrets.yaml` を透過的に編集 |
| `just secrets-rekey` | `.sops.yaml` を変更後の再暗号化 |

`~/.config/sops/age/keys.txt` が age 秘密鍵。Bitwarden に backup 推奨。

---

## 🛰 リモート

remote の種類別に 4 つの戦略を使い分け:

| シチュエーション | コマンド | 何 |
|---|---|---|
| **計算ノード**(non-root、ephemeral) | `nssh user@host` | rootless Nix(`nix-portable`)で nvim/yazi/zellij、起動毎に展開 |
| **長期 Linux サーバー**(root、persistent) | リモートで `bash <(curl -sL ...bootstrap-linux.sh)` | full Nix install + dotfiles clone + home-manager(`.#<user>-linux`) |
| **WSL2 環境**(Windows + WSL) | WSL 内で `bash <(curl ...bootstrap-wsl.sh)` | Linux 共通 + WSL interop(clipboard, /mnt/c/) |
| **制限環境**(Nix 不可、append 程度) | local から `sync-configs-rsync.sh user@host [--full]` | nvim + zsh.local + git config を rsync、何も install しない |

ssh agent forwarding で private repo 取得対応済。

### 該当 home-manager attr
- `.#<user>` … macOS (= 現在 mac)
- `.#<user>-wsl` … WSL2
- `.#<user>-linux` … 純 Linux x86_64
- `.#<user>-linux-aarch64` … 純 Linux ARM (Raspberry Pi 等)

---

## 🧰 プロジェクト開発

### direnv + devenv

```bash
# 新プロジェクトに devenv.nix 雛形
cd my-project
devenv init

# devenv.nix を編集して使いたい言語/サービスを宣言
nvim devenv.nix
# 例:
# { pkgs, ... }: {
#   packages = [ pkgs.nodejs_22 pkgs.postgresql ];
#   languages.javascript.enable = true;
#   services.postgres.enable = true;
# }

# direnv で auto-load
echo "use devenv" > .envrc
direnv allow
# cd するだけで Node + postgres が起動、抜けると停止
```

### Nix-init(flake.nix 雛形生成)

```bash
# nixpkgs に無い OSS を Nix flake 化したい時
nix-init --url https://github.com/nosarthur/gita
# 対話で description / version / builder を入力
# → 動く flake.nix が生成される
```

---

## 🩺 探索 / トラブル

| コマンド | 何 |
|---|---|
| `just doctor` | 環境チェック |
| `nix-tree ~/.nix-profile` | 依存関係 TUI(「あれ何で入ってる?」) |
| `nix-tree /run/current-system` | システムレベルの依存関係 |
| `nh clean all` | 古い世代を一括削除 |

---

## 🐛 緊急復旧

| 症状 | コマンド |
|---|---|
| `/nix` が見えない | `sudo diskutil mount "Nix Store"` |
| 同上で直らない | `sudo determinate-nixd init` |
| `fstab` に `noauto` 戻った | `sudo sed -i '' 's/,noauto//' /etc/fstab` |
| Determinate 本体 update | `sudo determinate-nixd upgrade` |
| dotfiles 全部復元(新 Mac) | `bash scripts/bootstrap.sh` |

---

## 🎯 一日の流れ(典型例)

```bash
# 朝、ターミナル開く
Ctrl+R                    # atuin で前日の続き

# プロジェクト移動
Ctrl+G                    # fzf で repo 選択 → cd

# 状態確認
gita ll                   # 全 repo の brunch 状態俯瞰
gs                        # 今いる repo の status

# 編集
nvim src/<TAB>            # fzf-tab で fuzzy 補完
cat README.md             # bat で読む

# diff
git diff                  # delta で side-by-side

# commit
ga . && gc -m "feat: ..."
gp

# 別 repo へ
Ctrl+G                    # 別 repo

# 知らないコマンド試したい
, asciinema rec demo.cast # install せず実行
tldr ffmpeg               # 使い方確認

# 設定変えた
just rebuild

# 週末: 全 repo を最新化
gita super pull           # 横断 pull
just upgrade              # システム全体 update
```

---

## 🧬 内部実装メモ(future-self 向け)

- **eza/bat/delta/tealdeer**: `home-manager` の `programs.*` で declarative 管理
- **fzf-tab**: `programs.zsh.plugins` で `pkgs.zsh-fzf-tab` 投入
- **ghq.root**: `programs.git.extraConfig.ghq.root` で永続化
- **Ctrl+G widget**: `programs.zsh.initContent` 内の `ghq-fzf` 関数
- **gita-sync**: 同じく `initContent` の関数(`gita add` を ghq list で全件)
- **gita 本体**: `uv tool install gita`(`bootstrap.sh` で自動化)
- **nom 統合**: `nix build` の wrapper 関数で `--log-format internal-json -v |& nom --json` を挟む
- **nh**: 自前 TUI 持ってるので nom ラップしない(rev. `5d8bdac` で alias 撤回)

設定変更したい場合は `~/.dotfiles/nix/home/common.nix` を編集して `just rebuild`。
