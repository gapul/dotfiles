#!/usr/bin/env bash
# Raspberry Pi 4 サブサーバー ブートストラップ
# Raspberry Pi OS Lite (64bit / Bookworm) 起動後に1回実行する。
# 冪等: 再実行しても安全。Docker / log2ram / zram / Tailscale / SD延命を構成する。
#
# 使い方 (Pi上で):
#   scp configs/homelab/raspberrypi/bootstrap.sh pi@192.168.116.53:~/
#   ssh pi@192.168.116.53 'bash ~/bootstrap.sh'
set -euo pipefail

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -m)" == "aarch64" ]] || die "64bit OS (aarch64) で実行してください"
[[ -f /etc/debian_version ]]     || die "Debian系 (Raspberry Pi OS) を想定しています"
[[ $EUID -ne 0 ]]                || die "root ではなく一般ユーザーで実行してください (内部で sudo を使用)"

# ---------------------------------------------------------------------------
log "APT 更新"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

log "基本ツール導入"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  ca-certificates curl git rsync htop

# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Docker 導入 (公式スクリプト)"
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  warn "docker グループ反映には再ログインが必要です"
else
  log "Docker は導入済み (skip)"
fi
sudo systemctl enable --now docker

# ---------------------------------------------------------------------------
# zram: 圧縮RAMスワップ。microSDへの物理スワップ書込みを避ける
# 近年の Pi OS (trixie~) は systemd-zram-generator が標準で zram0 を管理する。
# zram-tools を入れると zram0 を奪い合って衝突(Device busy)するため、
# 標準があればそちらを設定し、無い場合のみ zram-tools にフォールバックする。
if [[ -f /usr/lib/systemd/zram-generator.conf ]] || command -v /usr/lib/systemd/system-generators/zram-generator >/dev/null 2>&1; then
  log "zram 構成 (OS標準 systemd-zram-generator を使用)"
  # 競合する zram-tools が過去に入っていれば撤去
  if dpkg -l zram-tools 2>/dev/null | grep -q '^ii'; then
    sudo systemctl disable --now zramswap 2>/dev/null || true
    sudo systemctl reset-failed zramswap 2>/dev/null || true
    sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq zram-tools >/dev/null 2>&1 || true
    sudo rm -f /etc/default/zramswap
  fi
  sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
else
  log "zram 構成 (zram-tools)"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zram-tools
  sudo tee /etc/default/zramswap >/dev/null <<'EOF'
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF
  sudo systemctl restart zramswap.service || sudo systemctl restart zramswap || true
fi

# dphys 物理スワップは無効化 (zramに一本化してSD摩耗を回避)
if systemctl list-unit-files | grep -q dphys-swapfile; then
  log "物理スワップ(dphys)を無効化"
  sudo systemctl disable --now dphys-swapfile || true
  sudo dphys-swapfile swapoff 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# log2ram: /var/log をRAM上に置き、定期的にSDへ書き戻す
if [[ ! -d /etc/log2ram.conf.d ]] && ! command -v log2ram >/dev/null 2>&1 && [[ ! -f /etc/log2ram.conf ]]; then
  log "log2ram 導入"
  echo "deb [signed-by=/usr/share/keyrings/azlux.gpg] http://packages.azlux.fr/debian/ stable main" \
    | sudo tee /etc/apt/sources.list.d/azlux.list >/dev/null
  sudo curl -fsSL https://azlux.fr/repo.gpg.key -o /usr/share/keyrings/azlux.gpg
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq log2ram
  warn "log2ram は再起動後に有効化されます"
else
  log "log2ram は導入済み (skip)"
fi

# ---------------------------------------------------------------------------
# journald: 揮発化してSD書込み削減
log "journald を揮発(RAM)化"
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/volatile.conf >/dev/null <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=32M
EOF
sudo systemctl restart systemd-journald

# ---------------------------------------------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
  log "Tailscale 導入"
  curl -fsSL https://tailscale.com/install.sh | sudo sh
  warn "認証は手動で: sudo tailscale up"
else
  log "Tailscale は導入済み (skip)"
fi

# ---------------------------------------------------------------------------
log "完了"
cat <<'EOF'

次の手順:
  1. 一度再ログイン (docker グループ反映 / log2ram 有効化のため sudo reboot 推奨)
  2. sudo tailscale up           # tailnet 参加
  3. AdGuard 主系を起動:
       cd configs/homelab/adguard/primary-pi && docker compose up -d
       → http://192.168.116.53:3000 で初期セットアップ
EOF
