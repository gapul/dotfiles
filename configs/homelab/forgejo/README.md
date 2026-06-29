# Forgejo (GitHub 以外の自宅 git ホスト)

GitHub の代替/冗長リモート。GitHub 障害・アカウント凍結時にも dotfiles やコードが自宅に残る。

- 公開: `https://git.gapul.net/` (Caddy・**Tailscale 限定**・Cloudflare DNS-01 TLS)
- git は **HTTPS のみ**(SSH 無効)。push/pull は token 認証

## デプロイ (CT101 = dockge / .65)

```bash
ssh proxmox            # root@192.168.116.100 (flap したら再試行)
pct enter 101
mkdir -p /opt/stacks/forgejo/data && cd /opt/stacks/forgejo
# compose.yaml を配置 (dotfiles の configs/homelab/forgejo/compose.yaml)。Dockge UI 推奨
docker compose up -d
docker compose logs -f          # "Starting new Web server" を確認
```

## Caddy ルート反映 (CT103 = caddy)

dotfiles の `configs/homelab/caddy/Caddyfile` に `git.gapul.net → .65:3003` を追加済み。
caddy CT に配ってリロード:

```bash
ssh proxmox 'pct exec 103 -- caddy reload --config /etc/caddy/Caddyfile'
```

## 初期設定 (ブラウザ)

1. `https://git.gapul.net/` を開く → 初回セットアップ画面
2. admin ユーザー(gapul)を作成。DB は内蔵 SQLite で十分
3. 設定 → Applications → **Generate New Token**(scope: repo)。token を控える(Bitwarden へ)

## リポジトリを冗長化する 2 方式

### 方式1: Pull Mirror (推奨・Mac の操作を変えない)

Forgejo が GitHub から定期的に pull して自宅へ複製し続ける。Mac 側は一切変更不要。

1. Forgejo 右上 ＋ → **New Migration** → **GitHub**
2. URL に GitHub repo (例 `https://github.com/gapul/dotfiles`)
3. **「This repository will be a mirror」にチェック** → Migrate
4. (private repo の場合のみ) GitHub の token を入力欄に
5. 以後、設定した間隔で自動同期。`git.gapul.net/gapul/dotfiles` に常に最新の複製

→ dotfiles・notes 等をこの方式で登録すれば、push 先は GitHub のままで自宅にも残る。

### 方式2: 両方へ push (自宅をライブの相互リモートに)

Mac の repo で push 先を GitHub と Forgejo の両方にする:

```bash
cd ~/.dotfiles
# まず Forgejo 側に空 repo を作成 (UI の New Repository) してから:
git remote set-url --add --push origin https://git.gapul.net/gapul/dotfiles.git
git remote set-url --add --push origin https://github.com/gapul/dotfiles.git   # 既存分も再追加
# 以後 `git push` で両方へ飛ぶ。token は git credential helper / .netrc に保存
git config credential.https://git.gapul.net.username gapul
```

## メンテ
- バックアップ: `./data`(SQLite + リポジトリ実体) を別途保全。Mac の restic 対象には無いので、
  homelab 側で `./data` を定期 dump するか、重要 repo は GitHub が原本なので Forgejo 側は再構築可。
- 更新: wud が新バージョンを通知 → Dockge で pull & redeploy。
