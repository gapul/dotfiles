# ターミナルセッション永続化ガイド

> **ターミナルを閉じてもプロセスを継続実行する方法**

ターミナルのタブやウィンドウを誤って閉じてしまっても、作業を継続できる方法を説明します。

## 🎯 方法の選択

| 方法 | 用途 | 難易度 | 推奨度 |
|------|------|--------|--------|
| **tmux** | 長時間作業・セッション管理 | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **nohup** | 単発コマンド実行 | ⭐ | ⭐⭐⭐ |
| **disown** | 既存プロセスの切り離し | ⭐ | ⭐⭐ |
| **screen** | 軽量な永続化 | ⭐⭐ | ⭐⭐ |

## 🔄 tmux（推奨）

**Yabai環境向けに最適化された設定**

### 基本操作

```bash
# tmuxセッション作成
tmux new-session -s work

# セッションからデタッチ（Ctrl+A, D）
# ターミナルを閉じても安全

# セッションに再接続
tmux attach-session -t work

# セッション一覧確認
tmux list-sessions
```

### 実用的な使用例

```bash
# プロジェクト別セッション管理
tmux new-session -s dotfiles -c ~/dotfiles
tmux new-session -s development -c ~/projects

# Claude Code作業用セッション
tmux new-session -s claude-work -c ~/dotfiles
# この中でClaude Codeを使用
# セッションを切り離してもClaude Codeは継続
```

### 主要キーバインド（Ctrl+A がプレフィックス）

| キー | 機能 |
|------|------|
| `Ctrl+A, D` | セッションからデタッチ |
| `Ctrl+A, C` | 新しいウィンドウ作成 |
| `Ctrl+A, S` | セッション選択 |
| `Ctrl+A, W` | ウィンドウ選択 |
| `Ctrl+A, R` | 設定リロード |
| `Ctrl+A, X` | セッション終了 |

## 🚀 nohup（シンプル実行）

**単発コマンドの永続実行**

### 基本構文

```bash
# バックグラウンドで実行
nohup command &

# 出力をファイルに保存
nohup long-running-script.sh > output.log 2>&1 &

# プロセスID確認
echo $!
```

### 実用例

```bash
# 大きなファイルのダウンロード
nohup wget https://example.com/large-file.zip &

# ビルドプロセス
nohup npm run build > build.log 2>&1 &

# データ処理スクリプト
nohup python3 data_processing.py > process.log 2>&1 &

# プロセス確認
jobs
ps aux | grep python3
```

## ⚡ disown（既存プロセス切り離し）

**実行中プロセスの永続化**

### 使用手順

```bash
# コマンドを開始（まだフォアグラウンド）
long-running-command

# Ctrl+Z で一時停止
# バックグラウンドに移動
bg

# プロセスをシェルから切り離し
disown %1

# または最新のバックグラウンドジョブを切り離し
disown
```

### 実用例

```bash
# 開発サーバーを誤ってフォアグラウンドで開始
npm run dev

# Ctrl+Z で停止
# バックグラウンドに移動して永続化
bg
disown

# ターミナルを閉じても開発サーバーは継続
```

## 📺 screen（軽量）

**軽量なターミナルマルチプレクサー**

### 基本操作

```bash
# screenセッション開始
screen -S mysession

# セッションから切り離し: Ctrl+A, D
# セッション一覧: screen -list
# 再接続: screen -r mysession
```

## 🎯 実際の使用シナリオ

### Claude Code での作業

```bash
# 1. tmuxセッション作成
tmux new-session -s claude-work -c ~/dotfiles

# 2. Claude Codeで作業開始
claude code

# 3. 作業中にセッションをデタッチ（Ctrl+A, D）
# ターミナルを閉じても安全

# 4. 後で再接続
tmux attach-session -t claude-work
# 作業を継続
```

### 長時間実行コマンド

```bash
# 大容量データの処理
nohup python3 process_large_dataset.py > processing.log 2>&1 &

# ビルドとテスト
nohup ./build-and-test.sh > build.log 2>&1 &

# プロセス確認
tail -f processing.log
ps aux | grep python3
```

### 複数プロジェクトの管理

```bash
# プロジェクト別tmuxセッション
tmux new-session -s project1 -c ~/projects/project1
tmux new-session -s project2 -c ~/projects/project2
tmux new-session -s dotfiles -c ~/dotfiles

# セッション間の移動
tmux list-sessions
tmux attach-session -t project1
```

## 🛠️ トラブルシューティング

### セッションが見つからない

```bash
# セッション一覧確認
tmux list-sessions

# 強制終了されたセッションの復旧
tmux has-session -t mysession || tmux new-session -s mysession
```

### プロセスが見つからない

```bash
# 実行中プロセス確認
ps aux | grep your-command
jobs

# ログファイル確認
tail -f nohup.out
tail -f your-log-file.log
```

### 設定が反映されない

```bash
# tmux設定リロード
tmux source-file ~/.tmux.conf

# または tmux内で: Ctrl+A, R
```

## 📋 ベストプラクティス

1. **長時間作業**: tmux使用
2. **単発コマンド**: nohup使用
3. **重要な作業**: 必ずログファイル出力
4. **プロジェクト管理**: セッション名を明確に
5. **定期確認**: セッション・プロセス状況の確認

これらの方法を使用することで、ターミナルを誤って閉じてしまっても安心して作業を継続できます。