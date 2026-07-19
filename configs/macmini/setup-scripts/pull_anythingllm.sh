#!/bin/bash
eval "$(/opt/homebrew/bin/brew shellenv)"
IMG="docker.io/mintplexlabs/anythingllm:latest"
n=0
until container image list 2>/dev/null | grep -q "anythingllm"; do
  n=$((n+1)); echo "=== pull試行 $n $(date +%H:%M:%S) ==="
  container image pull "$IMG" 2>&1 | tail -3
  sleep 8
done
echo "=== ANYTHINGLLM IMAGE READY $(date +%H:%M:%S) ==="
container image list 2>&1 | grep anythingllm
