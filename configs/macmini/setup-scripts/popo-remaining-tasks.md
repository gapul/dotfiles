# popo-agent chat-provider 作業の引き継ぎ（2026-07-13）

別マシン（gapul mac + Windows実機 ispc）で進めた作業の残タスクです。可能なものから進めてください。
リポジトリ: github.com/post-urban/popo-agent（デフォルト/統合ブランチは main のみ、GitHub Flow）。

## 完了済み（origin にある状態）
5 本の feature ブランチを origin/main(#401) に rebase 済み。各 PR に provider 固有の制限・マイグレーション注意を明記済み。
- Chatwork **PR #403 Open**（markdown変換 + ファイル送受信 + 5 migrations）
- Telegram **PR #404 Open**（Bot API full + 5 migrations）
- Windows(runtime) **PR #364 Open**（Windowsネイティブ互換 + fcntl修正 + CI Windows matrix）
- LINE **PR #405 Closed（保留）** — ブランチ feat/chat-line は rebase済み(5e883bed)、再開は `gh pr reopen 405`
- teams（feat/chat-teams, 5commits）— 未 rebase / 未 PR

## 残タスク
1. **teams ブランチ**: origin/main へ rebase → 検証（typecheck/vitest）→ PR。他 provider 同様、共有ファイル（chat-egress.ts / inbound.ts / identity.ts / route.ts）で加算的衝突、`buildChatLinkReassignedEmail`・`resolveSeatForSlackSender` の provider 拡張が必要になる想定。
2. **マージ順の衝突対応**: chatwork/telegram/line/teams は同じ共有ファイルを触るため、1本マージ後に残りは main 追従 rebase（軽微な衝突解決）が必要。
3. **token 解決の DRY 化**（任意）: 各 provider egress の「apiToken解決 → resolveRuntimeSecret → http_401 なら refresh して1回リトライ」が複数箇所に重複。`resolveXxxToken` に集約可能。
4. **provider diff の深い監査**（任意）: 過剰実装/dead code。chatwork の未配線 interactivity-handler は削除済み。line/teams は未監査。

## 実機（ispc / Windows, ssh ispc）依存で保留中のもの
- **Chatwork ファイル送受信**: 既存 install に OAuth scope `rooms.files:read/write` の**再認可**が必要（再認可まで API が 400、実機 E2E 未検証）。scopes.ts には追加済み。
- **LINE 実機 E2E 未実施**: LINE の DB は空。LINE Messaging API チャネル作成 + channel token/secret + webhook(line-test.mugen404.com) + tenant/install/連携 + LINE アプリからの送信、が必要。ispc の line worktree は古い commit(39d1893a) で未同期、.env の ENTITLEMENT_ISSUER が host.docker.internal:3000 に誤設定。
- **Windows 追従リスク**: 今後 main に fcntl/OS固有の新規コードが増えたら Windows-guard 追従が必要（追加した Windows CI matrix が検出想定）。

## 注意
- data/ や .env を git に add しない。vault ノートを直接削除しない。.claude/plans/ に書かない。
- 実機 ispc は Windows。認証情報の入力やアカウント作成は人間側の操作。
