#!/usr/bin/env bash
# nix-darwin switch wrapper to avoid HOME ownership warnings
set -euo pipefail

echo "🔄 nix-darwin switch with warning suppression"
echo "============================================="

# Store original HOME
ORIGINAL_HOME="$HOME"

# Run nix-darwin switch with proper environment
sudo env HOME="$ORIGINAL_HOME" USER="$USER" \
  nix run nix-darwin -- switch --flake . --impure "$@"

echo ""
echo "✅ nix-darwin switch completed successfully!"
echo "📁 HOME preserved: $ORIGINAL_HOME"