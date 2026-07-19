#!/bin/bash
export PATH="$HOME/.opencode/bin:$HOME/.local/bin:/opt/homebrew/bin:$PATH"
n=0
until command -v opencode >/dev/null 2>&1; do
  n=$((n+1)); echo "opencode install試行 $n $(date +%H:%M:%S)"
  curl -fsSL https://opencode.ai/install | bash 2>&1 | tail -3
  sleep 8
done
echo "OPENCODE READY: $(opencode --version 2>&1 | head -1)" > /tmp/opencode_ready
