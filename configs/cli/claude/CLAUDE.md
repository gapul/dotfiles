# Claude Code - User Memory

## 個人設定

### 言語・地域設定
- 日本語での応答を優先
- macOS環境での開発に特化
- UTCではなくJST（日本時間）を使用

### ブラウザ操作
常用ブラウザはZen。自動化は3つで、まず1、足りなければ2、見せる必要があれば3。
Chromeは2026-08-30に撤去した（Claude in Chrome拡張ごと）。拡張ができることはPlaywrightで
全部できたうえ、拡張は`--remote-debugging-port`を開けている間ずっと、localhostの誰にでも
ブラウザを明け渡す状態を作っていた。

1. **WebFetch** — captcha/ログインが絡まない単なる情報取得。ブラウザを起こさない。
2. **Lightpanda**（常駐、CDP=9223 / Playwright MCP=`http://localhost:8932/mcp`）
   裏で回す既定。実測14MB。見えないし軽いので常駐させたままでよい。
   ただし実装していないAPIに触るSPAは**エラーではなく空で返る**。取れた内容が
   空だったらここを疑い、3へ落とす。
3. **terminal-browser** — 実Chromium（Electron同梱）なので描画の穴がない。
   `terminal-browser open --split right <url>` で会話の隣に並び、操作は
   `terminal-browser action -- snapshot|click|fill|eval`。ssh越しも可
   （`open --ssh user@host <url>`）。終わったら`terminal-browser shutdown`。
   **必ず見えるペインを開く**（TTYが無くても右に分割する）ので、ユーザーの
   目視が要らない場面では2で粘る。
   Playwrightからは掴めない: CDPは出しているが**ポートが毎回変わる**
   （実測 53218 → 53337）ので、固定の`--cdp-endpoint`にできない。`action`で操作する。

- 速度は描画ではなく往復回数で決まる。読み取りだけなら1と2で足りる。
- Heliumはこの動線には出てこない。ヘッドレスでWebGL/スクリーンショットが要る
  検証（vrma-lab の`scripts/chrome-lab.sh`）専用に残してある。Lightpandaは
  レンダラを持たないのでそこは代われず、terminal-browserは必ず見えてしまう。
- ポートの確認は`netstat -an | grep LISTEN`で。**この機械に`/usr/bin/lsof`は無い**ので、
  lsofは黙って空を返し、空きポートに見えてしまう（9333で実際に踏んだ）。

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