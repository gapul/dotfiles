# 自宅サーバー運用ガイド (Homelab Operations)

自宅 Proxmox ベースのセルフホスト基盤の構成・運用手順をまとめたドキュメント。
設定の実体は `configs/homelab/<service>/`、ホスト構成は本書を参照。

- LAN: `192.168.116.0/24` / ゲートウェイ: `192.168.116.254`
- ハイパーバイザ: **Proxmox VE 9.1**（`pve` = `192.168.116.100`）
- tailnet: `tail079f44.ts.net`（MagicDNS 有効）

---

## 1. 構成（CT / VM 一覧）

| ID | 名前 | LAN IP | tailnet | 役割 |
|----|------|--------|---------|------|
| pve | pve | `.100` | `100.101.225.43` | Proxmox ホスト |
| CT101 | dockge | `.65` | — | Docker 母艦。Dockge(:5001)管理。スタックは `/opt/stacks/<name>/` |
| CT102 | tailscale-router | (dhcp) | `100.107.201.72` | subnet router（`192.168.116.0/24` 広告・承認済） |
| CT103 | caddy | `.119` | `100.64.125.107` | リバースプロキシ（Caddy / Tailscale 限定待受） |
| CT104 | hermes | `.120` | — | Discord×Claude エージェント |
| VM100 | haos | `.88` | — | Home Assistant OS |
| — | rpi4 | `.53` | `100.69.79.75` | サブサーバー（AdGuard 主系）※**制作で停止する前提のノード** |

---

## 2. アクセス早見表

| 目的 | コマンド / URL |
|------|----------------|
| Proxmox | `ssh root@192.168.116.100` / `https://pve.gapul.net` |
| CT へ入る | pve から `pct enter <id>` または `pct exec <id> -- <cmd>` |
| ラズパイ | `ssh pi@192.168.116.53` |
| Home Assistant SSH | `ssh hassio@192.168.116.88`（add-on / ed25519 鍵） |
| HA Web | `https://home.gapul.net` |
| Dockge | `https://dockge.gapul.net`（= `.65:5001`） |
| Git (Forgejo) | `https://git.gapul.net`（= `.65:3003`）。GitHub のセルフホスト・ミラー |
| AdGuard 主系/副系 | `https://dns.gapul.net` / `https://dns2.gapul.net` |
| 監視 | `https://status.gapul.net`（Uptime Kuma） |

- SSH 認証は **Bitwarden agent の ed25519 鍵**（`SHA256:2WG8EZOQ47X+XFzjXtuoytt8e3K8qsJd7r/FdbFKmM4`）。
- CT(.65/caddy 等)へは Mac から直接 SSH 不可 → **pve 経由（`pct`）**で操作する。
- `*.gapul.net` は **Tailscale 接続時のみ**到達可（Caddy が tailnet 限定待受のため）。

### アカウント / 認証情報

> ⚠️ **パスワードはこのリポジトリに書かない**（git 管理のため）。実パスワードは **Bitwarden** で管理し、ここには「ユーザー名」と「保管場所」のみ記載する。

| サービス | ユーザー名 | 認証方法 / パスワード保管 |
|----------|-----------|---------------------------|
| Proxmox (SSH) | `root` | ed25519 鍵(Bitwarden agent) |
| Proxmox (Web `pve.gapul.net`) | `root@pam` | パスワード → Bitwarden |
| ラズパイ rpi4 | `pi` | ed25519 鍵（焼き込み時に投入）+ 緊急用パスワード(Bitwarden) |
| Home Assistant (Web) | `gapul` | パスワード → Bitwarden |
| Home Assistant (SSH add-on) | `hassio` | ed25519 鍵 / passwordless sudo |
| AdGuard 主系・副系 | `gapul` | パスワード → Bitwarden（同期 `adguardhome-sync` も同一資格を使用。実体は CT101 `/opt/stacks/adguardhome-sync/compose.yaml` の env にのみ存在） |
| Dockge (`.65:5001`) | （要確認） | パスワード → Bitwarden。忘失時は CT101 で `docker exec -it dockge npm run reset-password` |
| Uptime Kuma (`status.gapul.net`) | （初回設定で作成） | パスワード → Bitwarden |
| Forgejo (`git.gapul.net`) | `gapul` | admin。パスワード + API token → Bitwarden |
| Cloudflare API (Caddy DNS-01) | — | トークンは CT103 `/etc/caddy/cf.env`（git 管理外） |

- 秘密情報を dotfiles に入れる場合は **SOPS**（`.sops.yaml`）で暗号化し、平文でコミットしない。`work/ conf/ .env` は `.gitignore` 済み。

### SSH 鍵

秘密鍵は **Bitwarden Desktop の SSH agent** が保持（Mac にファイルとして秘密鍵は置かない。`~/.ssh/*.bak` はバックアップ）。agent は 2 鍵を提供:

| ラベル | 種別 | フィンガープリント | 用途 |
|--------|------|--------------------|------|
| `GitHub` | ed25519 | `SHA256:2WG8EZOQ47X+XFzjXtuoytt8e3K8qsJd7r/FdbFKmM4` | **homelab 標準**。下記すべてに登録 |
| `mvrx-dev` | RSA | `SHA256:4WQSmfgnETVJxL6I7R13l5b8Qu6mGpx65FTs7ELov0U` | 別途（業務系）。homelab では未使用 |

**登録に使う公開鍵（ed25519）**:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBLeOb9XOJPsmuTRf708qYoNckWk+/fhuWkpTWtTSu41 yuk8337@gmail.com
```

**この公開鍵の登録先**:

| ホスト | ユーザー | 登録方法 |
|--------|---------|---------|
| pve `.100` | `root` | 既存（`~/.ssh/authorized_keys`） |
| rpi4 `.53` | `pi` | Raspberry Pi Imager の焼き込み時に投入 |
| HA `.88` | `hassio` | add-on Configuration の `ssh.authorized_keys` |
| CT102 tailscale-router | `root` | 既存 |

- CT101(dockge) / CT103(caddy) / CT104(hermes) には **この鍵は未登録** → pve から `pct enter/exec` でアクセスする。
- 新ホストに登録する1行:
  ```bash
  mkdir -p ~/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBLeOb9XOJPsmuTRf708qYoNckWk+/fhuWkpTWtTSu41 yuk8337@gmail.com" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
  ```

**参考: 各ホストのサーバ公開鍵（known_hosts 検証用）**
- HA add-on `.88`: `SHA256:AxGmsu9vVDDMjp9+xKcZtIwTq7fePBlx3ruPUOgNzho`（add-on 再作成で変わることがある→ `ssh-keygen -R 192.168.116.88` で更新）

---

## 3. DNS（AdGuard 二重化 + Tailscale 配布）

ローカル DNS を主系（ラズパイ）／副系（CT101）で冗長化し、広告ブロックを全 tailnet 端末へ配布する。

```
全 tailnet 端末
   │ DNS(Tailscale Global nameservers / Override ON, 上から優先):
   │   1. 100.69.79.75    (主系 Pi)        ← 通常
   │   2. 192.168.116.65  (副系 CT101)     ← 主系停止時のフェイルオーバー（CT102 subnet router 経由で外からも到達）
   │   3. Quad9 9.9.9.9    (最終保険)       ← 両系ダウン時のみ
   ▼
 AdGuard 主系(.53) ──[adguardhome-sync 10分毎]──▶ AdGuard 副系(.65)
   └ gapul.net だけ Split DNS → Cloudflare(1.1.1.1) → Caddy(tailnet IP)
```

- 主系: `configs/homelab/adguard/primary-pi/`（ラズパイ上 `~/adguard/primary-pi/`）
- 副系・同期: CT101 `/opt/stacks/adguard-secondary/`、`/opt/stacks/adguardhome-sync/`（Dockge 管理）
- AdGuard 管理ユーザー: `gapul`
- **`gapul.net` の Split DNS（→Cloudflare）は必須**。消すと他端末で `*.gapul.net` が解決不能になる（公開DNSが CGNAT(100.64.x) を rebinding 保護で弾くため）。
- **公開 DNS をグローバルに常設しない**こと。LAN内IP（.65）を入れると外出端末でタイムアウト→激遅になる（→ subnet router 経由で到達させる現構成が正解）。
- Tailscale DNS 設定は管理コンソール `https://login.tailscale.com/admin/dns`。

---

## 4. 運用手順：ラズパイの停止 / 復帰（制作モード）

ラズパイは「制作（TouchDesigner 等）で一時的に止める」前提のノード。止めても副系(.65)が DNS を継続する。

**止める**（SDカード保護のため必ず graceful に）:
```bash
ssh pi@192.168.116.53 'sudo poweroff'
# 緑LED(ACT)が消えたら電源を抜いてOK（赤LED=給電中の表示なので点いたままで正常）
# Uptime Kuma の「AdGuard Primary Pi (.53)」モニターは Pause しておくと誤報が出ない
```

**戻す**:
```bash
# 電源を挿すだけ → 自動起動。AdGuard 主系も restart:unless-stopped で自動復帰
ssh pi@192.168.116.53 'docker ps'   # 復帰確認
# Kuma のモニターを Resume
```

停止中の挙動（検証済み）: 副系(.65)で名前解決・広告ブロック継続、`gapul.net` も Cloudflare split で生存。

---

## 5. リバースプロキシ（Caddy / CT103）

- Caddy は CT103 で **native systemd** 稼働。設定: `/etc/caddy/Caddyfile`（dotfiles: `configs/homelab/caddy/Caddyfile`）。
- **Tailscale 限定待受**（LAN の 80/443 は閉）。TLS は Cloudflare DNS-01（`CF_API_TOKEN` は `/etc/caddy/cf.env`）。

**新サービスを公開する手順**:
1. CT103 の Caddyfile にブロックを追加:
   ```
   newsvc.gapul.net {
       tls { dns cloudflare {env.CF_API_TOKEN} }
       reverse_proxy 192.168.116.65:PORT
   }
   ```
2. Cloudflare に A レコード追加（`newsvc.gapul.net` → `100.64.125.107`、proxied=false, ttl=60）。
   既存サブドメインと同形式。Caddy の CF トークンで API 追加も可。
3. `pct exec 103 -- systemctl reload caddy`

---

## 6. 監視（Uptime Kuma / status.gapul.net）

- CT101 の `/opt/stacks/uptime-kuma/`。`status.gapul.net` で UI。
- モニター（DNS 監視 = 実際に解決できるかを毎分チェック）:
  - **AdGuard Secondary (.65)** … 常時稼働前提＝**本気でアラート**
  - **AdGuard Primary Pi (.53)** … 制作で止めるので**情報用**。停止前に Pause
  - **Home Assistant (.88)** … HTTP 監視
- ⚠️ **通知が未設定**。Discord webhook を登録すると実アラートが飛ぶ（既存の Discord 連携と相性◎）。

---

## 7. Home Assistant（VM100 / .88）

- **SSH**: `ssh hassio@192.168.116.88`（Advanced SSH & Web Terminal add-on、ed25519 鍵承認済、非rootだが passwordless sudo 可）。
  - add-on は `ssh.password` / `ssh.authorized_keys` のどちらか未設定だと**起動拒否→再起動ループ**するので注意。
  - 弾かれる時: ユーザー名は `hassio`（自分のMacユーザーではない）。ホスト鍵変更時は `ssh-keygen -R 192.168.116.88`。
- **リバプロ整合**: Caddy 配下なので `configuration.yaml` に設定済み:
  ```yaml
  http:
    use_x_forwarded_for: true
    trusted_proxies:
      - 192.168.116.119   # Caddy(CT103)
  ```
  （Caddy 側の `header_up -X-Forwarded-For` ハックは撤去済み＝実クライアントIPが記録される）
- ⚠️ **HA Core の再起動は「設定 → システム」の電源アイコンから**行う。Developer Tools 経由の再起動は失敗して設定が読み込まれないことがあった。

---

## 8. 運用上のハマりどころ（既知）

| 事象 | 対処 |
|------|------|
| Docker Hub の pull 上限（自宅公開IP） | `docker pull --platform linux/amd64 mirror.gcr.io/<repo>:<tag>` → `docker tag` で元名に。デーモン再起動不要 |
| 別アーキのイメージ流用で `exec format error` | arm64(Pi)↔amd64(CT) は混在不可。アーキを合わせて pull |
| pve への SSH が時々 `Permission denied` | 経路が flap する。数秒おいて再試行で繋がる |
| zram が二重化して `failed`（Pi/trixie） | OS標準 `systemd-zram-generator` に一本化（zram-tools は撤去）。`bootstrap.sh` 反映済み |
| この Mac で広告ブロックが効かない | Mac の Tailscale クライアントが古いDNSを固着 → **Mac再起動**で解消 |

---

## 9. Git ホスト（Forgejo / git.gapul.net）

GitHub 以外の git リモート。GitHub 障害・アカウント凍結時にもコードが自宅に残る冗長化。

- CT101 の Docker スタック（`/opt/stacks/forgejo/`、dotfiles: `configs/homelab/forgejo/`）。`.65:3003` → `git.gapul.net`。
- git は **HTTPS のみ**（`DISABLE_SSH=true`）。push/pull は token 認証。admin = `gapul`。SQLite。
- `INSTALL_LOCK=true`（compose env）で Web インストーラを飛ばし、admin は CLI で作成
  （`docker exec -u git forgejo forgejo admin user create --admin ...`）。

**運用は Pull Mirror 方式**: Forgejo が GitHub から定期 pull（15分毎）。Mac の git 操作は変えず、
push 先は GitHub のまま自宅へ複製され続ける。**外向き pull なので Caddy 無しでも冗長化は機能**
（Caddy は Web UI / clone / push 用）。

**状態**:
- ✅ `dotfiles`（public）を Pull Mirror 登録済・稼働中。
- ⏳ `obsidian-vault`（private）は GitHub の read token が必要 → Forgejo UI の Migration で token を貼って追加。
- ⏳ Caddy 公開: Caddyfile に `git.gapul.net → .65:3003` 追加済。§5 の手順で Cloudflare A レコード追加 +
  `pct exec 103 -- systemctl reload caddy` が必要（未実施でもミラーは動く）。

**ミラー追加手順**（UI）: ＋ → New Migration → GitHub → repo URL → **「This repository will be a mirror」** に
チェック → Migrate（private repo は GitHub token を入力）。

---

## 10. バックアップ（TODO）

- HA 自動バックアップ: スケジュール/保持/暗号化パスワード/保存先（ローカル or restic オフサイト）を要決定。

---

## 関連
- 各サービス設定: `configs/homelab/{adguard,caddy,forgejo,raspberrypi}/`
- ラズパイ初期化: `configs/homelab/raspberrypi/bootstrap.sh`
- 汎用チートシート: `docs/CHEATSHEET.md`
