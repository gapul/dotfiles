# Claude Code - User Memory

## 個人設定

### 言語・地域設定
- 日本語での応答を優先
- macOS環境での開発に特化
- UTCではなくJST（日本時間）を使用

### ブラウザ操作（Claude in Chrome + Playwright MCP）
Chromeは自動化専用（常用ブラウザはZen）。ユーザーに起動を頼まず自分で面倒を見る。
自動化はDefaultではなく専用プロファイル `~/Library/Application Support/Google/Chrome-automation`
を使う（Defaultのクローン。Cookie/Google login/拡張ごと引き継いでいるのでcaptcha耐性は同じ）。
- 起動:
  `open -gjn -a "Google Chrome" --args --user-data-dir="$HOME/Library/Application Support/Google/Chrome-automation" --no-startup-window --remote-debugging-port=9222`
  窓なし・背景起動でフォーカスを奪わない。拡張は自動で再接続するのでクリック不要。
  タブは `tabs_context_mcp {createIfEmpty: true}` が要るときだけ作る。
- 終了: `pkill -f "Chrome-automation"`。ユーザーがDockから開いたDefaultのChromeを巻き込まないよう、
  必ずこの形で撃つ（`tell application "Google Chrome" to quit` は両方落としうる）。
- 常駐させない（窓なしで実メモリ約370MB）。
- Playwright MCP(`playwright`)は同じChromeに9222でアタッチする。Chromeが落ちていても接続は遅延なので
  起動順は自由。フォーム入力・待機・`browser_evaluate`はこちら、複数手を1往復で流すのは
  claude-in-chromeの`browser_batch`が強い。両方とも同じ窓を見るので混ぜて使える。
- 9222はローカルに開いたポートなので、自動化していない間はChromeを落としておく。
- `--headless=new` は不可。2026-08-10に実測して拡張のnative hostが起動せず未接続になった（302MBまで減るが操作不能）。再挑戦しない。
- 速度は描画ではなく往復回数で決まる。2手先が読めるなら `browser_batch` に束ねる。
  画面を見る必要がない読み取りは `get_page_text` / `find` / `javascript_tool` を使い、
  `computer` のスクリーンショットは座標クリックが必要なときだけ。
- captcha/ログインが絡まない単なる情報取得はブラウザを起動せず WebFetch で済ませる。

### コーディングスタイル
- インデント: 2スペース（YAML, JSON, Lua, JavaScript, TypeScript）
- インデント: 4スペース（Python）
- 文字エンコーディング: UTF-8
- 改行コード: LF（Unix style）

### 開発環境
- ターミナル: Wezterm + Zsh + Starship
- エディター: Neovim (主), VSCode, Zed
- プラットフォーム: macOS (Apple Silicon)
- パッケージマネージャー: Homebrew, npm, pip, cargo

## コミュニケーション設定

### 応答スタイル
- 簡潔で実践的な回答を重視
- コードは動作確認済みのものを提供
- セキュリティとベストプラクティスを考慮
- 日本語と英語を適切に使い分け

### 技術的嗜好
- 設定ファイルはシンプルで保守しやすいものを好む
- 自動化とスクリプトを重視
- エラーハンドリングを徹底
- ドキュメント化を重要視

## よく使用する技術スタック

### フロントエンド
- React + TypeScript
- Next.js
- Tailwind CSS

### バックエンド  
- Node.js + Express
- Python + FastAPI
- Go

### データベース
- PostgreSQL
- Redis
- SQLite

### インフラ・ツール
- Docker + Docker Compose
- GitHub Actions
- AWS

## 作業パターン

### ファイル管理
- dotfilesでの設定管理を重視
- .gitignoreでの機密情報除外を徹底
- バックアップの自動化を好む

### 品質管理
- CI/CDでの自動テストを重視
- リンターとフォーマッターの活用
- コードレビューの実施

### ドキュメント
- README.mdの充実
- コメントは日本語で詳細に
- 使用例とトラブルシューティングを含む

---

この個人設定により、すべてのプロジェクトで一貫した開発体験を提供します。