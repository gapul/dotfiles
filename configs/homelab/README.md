# configs/homelab

> **注記(2026-08-09)**: この構成はハイパーバイザ無しの NixOS 1台へ置き換え中。
> 設定の実体は `nix/hosts/homeserver.nix` と `nix/homelab/` に移っている。
> 当日の手順は [HOMESERVER_MIGRATION.md](../../docs/HOMESERVER_MIGRATION.md)。
> 以下は移行元の記録。

自宅セルフホスト基盤の設定一式。

📖 **運用手順・構成・トラブルシュートは [`docs/HOMELAB.md`](../../docs/HOMELAB.md) を参照。**

## サービス別ディレクトリ
| ディレクトリ | 内容 |
|------|------|
| `adguard/` | AdGuard Home 二重化（主系 Pi / 副系 CT101 / 同期）+ runbook |
| `caddy/` | リバースプロキシ Caddyfile（CT103・Tailscale 限定） |
| `raspberrypi/` | ラズパイ初期化 `bootstrap.sh`（Docker/zram/log2ram/Tailscale・SD延命） |
| `forgejo/` | セルフホスト Git（GitHub ミラー・`git.gapul.net`・稼働中） |

## ホスト早見
- pve `.100` / dockge(CT101) `.65` / caddy(CT103) `.119` / hermes(CT104) `.120` / HA(VM100) `.88` / rpi4 `.53`
- CT へは pve から `pct exec <id> -- ...`
