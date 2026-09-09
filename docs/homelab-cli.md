# HomelabをコードとCLIから操作する

`hs` を母艦の共通入口にする。Web UI は閲覧・人間向け入力として残してよいが、
起動・停止・調査・バックアップは UI を正本にしない。

```sh
hs list
hs status                          # 全体
hs status paperless                # コンテナ単体
hs logs paperless -f
hs restart paperless
hs exec paperless sh

hs unit status blocky
hs unit logs restic-backups-homeserver -n 100
hs unit restart syncthing

hs api romm GET /openapi.json
hs openapi bambuddy
hs share create exhibition-files never /path/to/vertical.mp4 /path/to/horizontal.mp4
hs ytdl check
hs backup snapshots
hs backup run
hs backup restore-drill
```

API鍵は `/var/lib/secrets/homelab-cli.env` に置く。GitやNix storeには入れない。

```sh
HS_BAMBUDDY_TOKEN=...
HS_MINIFLUX_TOKEN=...
HS_PAPERLESS_TOKEN=...
HS_ROMM_TOKEN=...
HS_HOMEASSISTANT_TOKEN=...

# Cookie認証しか提供しないPingvin Share X用。実行時に短命Cookieへ交換する。
HS_PINGVIN_SHARE_EMAIL=...
HS_PINGVIN_SHARE_PASSWORD=...

# 上記以外のCookie型APIを直接扱う場合。
HS_SOME_APP_COOKIE='session=...'
```

## 操作経路

| 種類 | 対象 | コード/CLI経路 |
|---|---|---|
| 標準REST/OpenAPI | Bambuddy、Dawarich、Home Assistant、Jellyfin、Miniflux、Paperless、Readeck、RomM、Syncthing | `hs api`、各OpenAPI/REST API |
| 標準プロトコル | Anki、Attic、CouchDB、Forgejo、Matrix、Navidrome、ntfy、Radicale、Samba、Vaultwarden | それぞれの公式CLIまたはHTTP/CalDAV/SMBプロトコル |
| アプリ内CLI | ArchiveBox、Forgejo、Navidrome、Paperless、Pingvin Share X、ytdl-sub | `hs archivebox`、`hs forgejo`、`hs navidrome`、`hs paperless`、`hs share`、`hs ytdl` |
| ファイルが正本 | Fava/Beancount、Homepage、SearXNG、Blocky、Authelia、cloudflared、Filestash、Pingvin Share X | Git管理設定 + `hs unit`。Filestashの秘密鍵だけは `/var/lib/secrets` |
| 内部HTTP API | Calnode、Gameyfin、Hauk、Pingvin Share X、Spliit | `hs api`または`hs exec`。日次の契約チェックで入口の破壊を検知 |
| ホスト運用 | Podman全コンテナ、systemd全サービス、Restic | `hs status/logs/restart/exec/unit/backup` |

Ralllyのセルフホスト版はOpenAPI文書を配る一方、APIキー発行を上流が機能制限して
いる。ライセンス制限を迂回する改造は行わない。現状は構成・DB・ライフサイクルを
CLI管理し、投票の作成・編集だけをWeb UIに残す。代替候補は次の条件をすべて満たした
時点で並行導入し、データ移行後に切り替える。

- 活発に保守され、ローリングタグか継続的なコンテナ配布がある
- ゲスト投票を維持できる
- 投票の作成・更新・取得・削除に公開APIがある
- 既存Ralllyデータを失わず移行または並行保管できる

Crab Fitは公開APIを持つが最終更新が2023年で、現行Ralllyより保守性が落ちるため
置換しない。新しいGUIだけを理由に停止中のソフトへ戻すこともしない。

## 置き換え方針

- Pinchflatは、購読をYAMLで管理できる`ytdl-sub`へ置換する。
- File Browserの役割は、Google Driveと読み取り専用Resticを同時に見せられる
  Filestashへ寄せる。Driveのデータ自体は移動しない。
- Pingvin Share旧版は、ローリング配布されるPingvin Share Xへ置換する。
- Web UIだけでしか主要操作を再現できない新規ソフトは、原則として増やさない。

APIの到達性は`api-contract-check.timer`が毎日確認し、破壊的な上流変更はntfyへ
通知する。永続DBは日次バックアップ前に整合したダンプを作り、月次の
`restore-drill.timer`が別DBへ本当に復元する。
