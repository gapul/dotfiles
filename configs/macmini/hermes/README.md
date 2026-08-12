# hermes

macmini の Hermes エージェント（専用ユーザー `hermes`、サンドボックスは `hsandbox`）のうち、
**自分で書いたコードだけ**をここに置く。設定と秘密は置かない。

## claude-acp

Hermes の `copilot-acp` プロバイダは、外部プロセスを spawn して stdio 上で
JSON-RPC 2.0 を話す。`claude-acp` はその相手役を最小限だけ実装したアダプタで、
`session/prompt` を受けるとサブスクの `claude -p` を呼び、返答をそのまま流し返す。
これで Anthropic の API 課金なしに Claude を推論バックエンドにできる。

内側の `claude` はツールを無効にして走らせる。ツール実行は Hermes の仕事で、
Hermes が返答中の `<tool_call>` ブロックを自分のツール層で処理する。

`.env` の `HERMES_COPILOT_ACP_COMMAND` がこのファイルを指す。配置は
`nix/hosts/macmini.nix` の activation が `/Users/hermes/.local/bin/claude-acp` へ
敷く（別ユーザーのホームなので home-manager では届かない）。Hermes 側が書き換える
ファイルではないので、宣言側を常に正として上書きする。

**壊れやすさ**: 実装が合わせているのは Hermes 内部の `agent/copilot_acp_client.py`
の契約で、公開 API ではない。Hermes を上げたら会話が通ることを必ず確かめること。

## ここに無いもの

- `config.yaml`（`/Users/hermes/.hermes/` と `/Users/hermes/imouto-home/.hermes/`）は
  Hermes 自身が実行中に書き換える。git に置くと常に差分が出るうえ、まなび側は
  Discord のチャンネル ID と本人の学習状況が入るので公開リポジトリには置かない。
- `.env`（トークン類）も同じ理由で置かない。

## 撤去したもの

`claude-bridge`（OpenAI 互換 :9180 経由で `claude -p` を叩く旧経路）は 2026-08-12 に
撤去した。`model.provider` が `copilot-acp` に移ってから一度も使われておらず、最後に
推論を捌いたのは 2026-07-17。gapul のホームの claude バイナリに依存していたのも、
ユーザー分離を締められない理由になっていた。戻すなら niski84/claude-bridge を入れ直し、
`model-providers/claude-cli` プラグインを有効化して `model.provider: claude-cli` に戻す。
