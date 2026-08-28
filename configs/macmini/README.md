# macmini ローカルAIスタック

M4 Mac mini(24GB, ヘッドレス)上のローカルAI一式。gapul.net 経由でスマホから操作。

## 層構成(nix宣言 vs imperative)

| 層 | 管理 | 場所 |
|---|---|---|
| brew(ffmpeg/uv/aria2/socat/container/tailscale) | **nix宣言** | `nix/hosts/macmini.nix` の `homebrew.brews` |
| ラッパーCLI(transcribe/tts/describe等) | 本リポ管理 | `configs/macmini/bin/` → `~/.local/bin/` |
| サービス/スクリプト(ai-stack.sh 等) | 本リポ管理 | `configs/macmini/services/` → `~/` |
| launchd supervisor | 本リポ管理 | `configs/macmini/launchd/` → `~/Library/LaunchAgents/` |
| Python venv(ML) | **imperative** | `bootstrap.sh` で uv 再構築(torch/mlx/pyannote等はnix化困難) |
| モデル(重い) | **imperative** | `models.txt` manifest + `bootstrap.sh`(hf-mirror/GitHub直DL) |

## 再現手順(まっさら macmini から)

1. `darwin-rebuild switch`(brew群・SSH/sleep設定が入る)
2. `bash configs/macmini/bootstrap.sh`(venv再構築 → モデル取得 → スクリプト配置 → コンテナ起動 → launchd登録)
3. Caddy(別ホスト `caddy`)に tools のブロック追記(`docs/`参照)

## サービス一覧(全てLAN 192.168.116.91)

- 埋め込み+リランク(Ruri)サーバー :8900 / AIツールWebパネル :8901
- コンテナ: Minecraft :25565(apple container、socatでhost公開)
  - Open WebUI と AnythingLLM は 2026-08-12 に homeserver へ移し、2026-08-20 に廃止した。AIパネル(:8901)と用途が重なっていたため。
  - Ollama(:11434)と `ask` は 2026-08-28 に撤去。独自 blob ストアに 47GB を抱えたまま、推論の実体は MLX 系と claude-bridge に移っていたため。

## 重要な運用上の罠(詳細は各スクリプトのコメント / Claudeメモ参照)

- **モデルDLは母艦を経由せず macmini 直**。HF Xetは絞られる(2.9KB/s〜)ので **hf-mirror.com**(8MB/s)or **GitHub**(TRvlvr等)を優先。aria2 self-healing + zip検証。
- **量子化×日本語**: VLMの4bitは日本語生成を壊しうる(EMNLP2024で査読済)。Ruri は日本語堅牢。
- **apple container**: 初回 `container system start` + `container system kernel set --recommended`。DNS死ぬので `--dns 1.1.1.1`。**ホストポート公開(-p)がHTTPで壊れる → socatで host→containerIP 転送**。
- **SSH**: macminiはBitwardenエージェントがrefuseしがち → `ControlMaster` 多重化必須。
