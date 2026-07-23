#!/bin/bash
eval "$(/opt/homebrew/bin/brew shellenv)"
IMG="docker.io/itzg/minecraft-server:latest"
mkdir -p ~/mc-data
n=0
until container image list 2>/dev/null | grep -q "minecraft-server"; do
  n=$((n+1)); echo "=== MCイメージ pull試行 $n $(date +%H:%M:%S) ==="
  container image pull "$IMG" 2>&1 | tail -2
  sleep 8
done
echo "=== MC IMAGE READY $(date +%H:%M:%S) ==="
# 既存があれば消してから起動
container stop mc-server 2>/dev/null; container rm mc-server 2>/dev/null
container run -d --name mc-server \
  -e EULA=TRUE -e TYPE=PAPER -e VERSION=LATEST -e MEMORY=4G -e ONLINE_MODE=TRUE \
  -p 25565:25565 -v "$HOME/mc-data:/data" \
  "$IMG"
echo "=== MC SERVER STARTED $(date +%H:%M:%S) ==="
sleep 5
container list 2>&1 | grep mc-server
