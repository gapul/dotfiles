# AdGuard Home 二重化 (A構成)

ローカル DNS を主系(Raspberry Pi 4)/ 副系(.65)で冗長化する。
**主系のラズパイは制作用途でいつでも停止でき、止めても副系が名前解決を継続する。**

## 構成

| 役割 | ホスト | DNS | 管理UI | 外部URL |
|---|---|---|---|---|
| 主系 | ラズパイ4 `192.168.116.53` | :53 | :3000 | `dns.gapul.net` |
| 副系 | Docker母艦 `192.168.116.65` | :53 | :3080 | `dns2.gapul.net` |
| 同期 | `.65` (adguardhome-sync) | — | — | 主系→副系 10分毎 |

```
クライアント DNS 設定:
  primary   = 192.168.116.53   ← 主系(Pi)。止めてもOK
  secondary = 192.168.116.65   ← 副系。常時稼働でフェイルオーバー
```

## セットアップ手順

### 1. ラズパイの準備
- Raspberry Pi OS Lite (64bit) を microSD に焼く
- 固定IP `192.168.116.53` を割当(ルーターのDHCP予約 or dhcpcd 設定)
- Docker + compose plugin を導入
- microSD延命: `log2ram` 導入、`zram` 有効化

### 2. 主系を起動 (ラズパイ上)
```bash
cd configs/homelab/adguard/primary-pi
docker compose up -d
# http://192.168.116.53:3000 で初期セットアップ → admin ログイン作成
```

### 3. 副系を起動 (.65 / Dockge から or CLI)
```bash
cd configs/homelab/adguard/secondary
docker compose up -d
# http://192.168.116.65:3080 で初期セットアップ → 同じ admin で作成
```

### 4. 同期を起動 (.65)
```bash
cd configs/homelab/adguard/sync
cp .env.example .env   # 主系/副系の admin パスワードを記入 (sops管理推奨)
docker compose up -d
```
以後、主系で編集したフィルタ・書換ルール・設定が副系へ自動複製される。

### 5. クライアントへ配布
ルーターの DHCP 配布 DNS を `192.168.116.53` / `192.168.116.65` の2つに設定。
(Tailscale 経由は既存の Split DNS `gapul.net→Cloudflare` 設定と併用)

## 制作用途でラズパイを止める / 戻す

```bash
# 止める (ラズパイ上) — 副系(.65)が自動でDNSを引き継ぐ
docker compose -f primary-pi/compose.yaml down
sudo systemctl disable docker   # 制作中はDockerごと止めてリソース解放する場合

# 制作 ... CPU/メモリ/IO がフルに使える

# 戻す
sudo systemctl enable --now docker
docker compose -f primary-pi/compose.yaml up -d
# 復帰後、次の sync サイクルで副系との差分が再同期される
```

`conf/` は volume に残るので、停止しても設定・ログイン情報は失われない。

## 注意
- `work/` `conf/` `.env` は Git 管理外(`.gitignore` 済み)。設定実体と秘密情報はコミットしない
- 主系/副系で **DHCPサーバー機能は使わない**(同期対象外。ルーターのDHCPを継続利用)
- Tailscale は制作中も起動したままで可(軽量・リモート用)
