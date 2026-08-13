# hermes

macmini の Hermes エージェント（専用ユーザー `hermes`、サンドボックスは `hsandbox`）のうち、
**自分で書いたコードだけ**をここに置く。設定と秘密は置かない。

## claude-acp（別リポジトリへ移動）

Hermes の `copilot-acp` プロバイダは、外部プロセスを spawn して stdio 上で
JSON-RPC 2.0 を話す。`claude-acp` はその相手役を最小限だけ実装したアダプタで、
`session/prompt` を受けるとサブスクの `claude -p` を呼び、返答をそのまま流し返す。
これで Anthropic の API 課金なしに Claude を推論バックエンドにできる。

内側の `claude` はツールを無効にして走らせる。ツール実行は Hermes の仕事で、
Hermes が返答中の `<tool_call>` ブロックを自分のツール層で処理する。

実体は **[gapul/claude-acp](https://github.com/gapul/claude-acp)** に移した。マシンの設定では
なく Hermes を動かすための部品なので、dotfiles が持つ理由が無い。ここは flake input として
参照し、`nix/hosts/macmini.nix` の activation が store から
`/Users/hermes/.local/bin/claude-acp` へ敷く（別ユーザーのホームなので home-manager では
届かない）。`.env` の `HERMES_COPILOT_ACP_COMMAND` がそのパスを指す。

### まなび側だけの上乗せ（HOME が `manabi-home` のとき）

- **毎ターン先頭に日時を付ける**。内側の `claude` には日付しか渡らず、時刻を
  聞かれると推測で答える（実測で1時間半ずれた）。曜日も渡して数え違えを防ぐ。
- **やり取りのあとにサンドボックスの `~/study/after_turn.py` を呼ぶ**。向こうで
  学習記録を git にコミットし、計画が変わったのに画像が無ければ作って `MEDIA:` を返す。
  返信に `MEDIA:` が無いときだけ貼る（コミットは毎回したいので呼び出し自体は毎回）。
  スクリプトが無くても黙って何もしないだけなので、片方だけ古くても壊れない。

**壊れやすさ**: 実装が合わせているのは Hermes 内部の `agent/copilot_acp_client.py`
の契約で、公開 API ではない。Hermes を上げたら会話が通ることを必ず確かめること。

## まなび（別リポジトリへ移動）

学習チューターの一式は **[gapul/manabi](https://github.com/gapul/manabi)**（private）に移した。
gateway の起動シム、ダッシュボード、サンドボックスのスクリプト、SOUL とチャンネルプロンプト。
この機械には `/Users/Shared/manabi` に clone してあり、launchd のユニットはそこを exec する。
private なので flake input にはできない（CI が fetch できない）から、パス参照になっている。
サービス側の更新は向こうで `git pull` すれば済み、dotfiles の rebuild は要らない。

## ここに無いもの

- `config.yaml`（`/Users/hermes/.hermes/` と `/Users/hermes/manabi-home/.hermes/`）は
  Hermes 自身が実行中に書き換える。git に置くと常に差分が出るうえ、まなび側は
  Discord のチャンネル ID と本人の学習状況が入るので公開リポジトリには置かない。
- `.env`（トークン類）も同じ理由で置かない。

## 撤去したもの

`claude-bridge`（OpenAI 互換 :9180 経由で `claude -p` を叩く旧経路）は 2026-08-12 に
撤去した。`model.provider` が `copilot-acp` に移ってから一度も使われておらず、最後に
推論を捌いたのは 2026-07-17。gapul のホームの claude バイナリに依存していたのも、
ユーザー分離を締められない理由になっていた。戻すなら niski84/claude-bridge を入れ直し、
`model-providers/claude-cli` プラグインを有効化して `model.provider: claude-cli` に戻す。
