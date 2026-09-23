#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
karabiner_dir="$repo_root/configs/keyboard/karabiner"
check_tmp="$(mktemp -d)"
trap 'rm -rf "$check_tmp"' EXIT

echo "Checking karabiner.ts types and generated JSON..."
bun install --cwd "$karabiner_dir" --frozen-lockfile
bun run --cwd "$karabiner_dir" check
mkdir -p "$check_tmp/home/.config/karabiner"
cp "$karabiner_dir/karabiner.json" "$check_tmp/home/.config/karabiner/karabiner.json"
HOME="$check_tmp/home" bun run --cwd "$karabiner_dir" build
jq -S . "$karabiner_dir/karabiner.json" >"$check_tmp/karabiner.expected.json"
jq -S . "$check_tmp/home/.config/karabiner/karabiner.json" >"$check_tmp/karabiner.actual.json"
diff -u "$check_tmp/karabiner.expected.json" "$check_tmp/karabiner.actual.json"

echo "Checking local agent Skill metadata..."
skill="$repo_root/configs/agents/skills/dotfiles-maintenance/SKILL.md"
awk 'NR == 1 { next } /^---$/ { exit } { print }' "$skill" >"$check_tmp/skill.yaml"
yq -e '.name == "dotfiles-maintenance" and (.description | length > 0)' "$check_tmp/skill.yaml" >/dev/null

echo "Checking lazy2nix generated sets..."
lazy2nix_dir="$repo_root/configs/editors/nvim/lazy2nix"
nix eval --json --file "$lazy2nix_dir/nixpkgs-plugins.nix" |
  jq -r 'keys[]' | sort >"$check_tmp/nixpkgs.txt"
jq -r 'keys[]' "$lazy2nix_dir/pinned-plugins.json" | sort >"$check_tmp/pinned.txt"
jq -r '.exclude[]' "$lazy2nix_dir/config.json" | sort >"$check_tmp/excluded.txt"

if [ -s "$check_tmp/nixpkgs.txt" ] && grep -qx 'lazy.nvim' "$check_tmp/nixpkgs.txt"; then
  :
else
  echo "lazy2nix: lazy.nvim is missing from generated nixpkgs plugins" >&2
  exit 1
fi

if comm -12 "$check_tmp/nixpkgs.txt" "$check_tmp/pinned.txt" | grep -q .; then
  echo "lazy2nix: plugin appears in both nixpkgs and pinned sets" >&2
  exit 1
fi

cat "$check_tmp/nixpkgs.txt" "$check_tmp/pinned.txt" | sort -u >"$check_tmp/managed.txt"
if comm -12 "$check_tmp/managed.txt" "$check_tmp/excluded.txt" | grep -q .; then
  echo "lazy2nix: excluded plugin appears in a generated managed set" >&2
  exit 1
fi

echo "Checking generated lazygit configuration against the (vendored) schema..."
# 中身は eval で取る。母艦の homeConfiguration は aarch64-darwin なので、その生成物の
# derivation を x86_64-linux で realise すると "platform mismatch" で落ちる (cachix に
# 載っている間だけ substitute で通っていた。flake.lock を進めた #705 で露呈)。
lazygit_config="$check_tmp/lazygit-config.yml"
nix eval --raw "$repo_root/nix#homeConfigurations.gapul.config.xdg.configFile.\"lazygit/config.yml\".text" \
  >"$lazygit_config"
# schema は同梱 (nix/tests/lazygit-config.schema.json)。毎回 raw.githubusercontent.com
# から取ると CI がネットワークに依存して時々フレークするため vendor 化した。
# 更新は flake.lock 更新時などに手動で curl し直す。
check-jsonschema \
  --default-filetype yaml \
  --schemafile "$repo_root/nix/tests/lazygit-config.schema.json" \
  "$lazygit_config"

echo "Checking Claude Code managed settings against the workstation settings..."
python3 "$repo_root/scripts/check-claude-settings-drift.py"

echo "Checking generated tmux theme for home-manager-less hosts..."
python3 "$repo_root/scripts/gen-tmux-theme.py" --check

echo "Checking generated documentation blocks (README / CHEATSHEET)..."
python3 "$repo_root/scripts/gen-docs.py" --check

echo "Generated configuration checks passed."
