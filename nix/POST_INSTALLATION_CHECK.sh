#!/usr/bin/env bash
# Phase 5 Modern CLI Integration - Post Installation Check

echo "🚀 Phase 5 Modern CLI Integration - インストール確認"
echo "=================================================="
echo ""

# 1. Modern CLI Tools 確認
echo "📦 Modern CLI Tools:"
tools=("eza" "bat" "rg" "fd" "zoxide" "lazygit" "yazi" "btm")
for tool in "${tools[@]}"; do
  if command -v "$tool" &> /dev/null; then
    version=$(eval "$tool --version 2>/dev/null | head -1" || echo "version check failed")
    echo "  ✅ $tool: $version"
  else
    echo "  ❌ $tool: Not found"
  fi
done

echo ""

# 2. エイリアス確認
echo "🔗 Shell Aliases:"
aliases=("ls" "cat" "grep" "find")
for alias_name in "${aliases[@]}"; do
  alias_def=$(alias "$alias_name" 2>/dev/null || echo "not set")
  echo "  🔧 $alias_name: $alias_def"
done

echo ""

# 3. 環境変数確認
echo "🌍 Environment Variables:"
if [ -n "$ZOXIDE_DATA_DIR" ]; then
  echo "  ✅ ZOXIDE_DATA_DIR: $ZOXIDE_DATA_DIR"
else
  echo "  ⚠️  ZOXIDE_DATA_DIR: Not set"
fi

echo ""

# 4. 機能テスト
echo "🧪 Functionality Tests:"

# eza test
if command -v eza &> /dev/null; then
  echo "  📁 eza file listing test:"
  eza --icons -l | head -3
  echo ""
fi

# zoxide test
if command -v zoxide &> /dev/null; then
  echo "  🧭 zoxide database:"
  zoxide_count=$(zoxide query --list 2>/dev/null | wc -l || echo "0")
  echo "  📊 Tracked directories: $zoxide_count"
  echo ""
fi

# 5. Neovim統合確認
echo "🎯 Neovim Integration:"
if [ -f "$HOME/.config/nvim/lua/modern-cli-integration.lua" ]; then
  echo "  ✅ Neovim modern CLI integration file exists"
else
  echo "  ⚠️  Neovim integration file not found"
fi

echo ""

# 6. 設定ファイル確認
echo "⚙️  Configuration Files:"
config_files=(
  "$HOME/.config/bat/config"
  "$HOME/.config/bottom/bottom.toml"
  "$HOME/.config/yazi/theme.toml"
  "$HOME/.config/ripgrep/config"
)

for config_file in "${config_files[@]}"; do
  if [ -f "$config_file" ]; then
    echo "  ✅ $(basename "$config_file"): Found"
  else
    echo "  ⚠️  $(basename "$config_file"): Not found"
  fi
done

echo ""

# 7. 推奨次のステップ
echo "🎉 Next Steps:"
echo "  1. 新しいコマンドを試してみる:"
echo "     ls -la        # ezaでカラフル表示"
echo "     cat README.md # batでシンタックスハイライト"
echo "     rg 'pattern' . # 高速テキスト検索"
echo "     fd filename   # 高速ファイル検索"
echo ""
echo "  2. TUIツールを起動:"
echo "     lazygit       # Git TUI"
echo "     yazi          # ファイルマネージャー"
echo "     btm           # システムモニター"
echo ""
echo "  3. スマートナビゲーション:"
echo "     z dotfiles    # zoxideで学習型ディレクトリ移動"
echo ""
echo "  4. Neovim統合:"
echo "     nvim で <leader>gg (LazyGit), <leader>fm (Yazi)"

echo ""
echo "🎯 Phase 5 Modern CLI Integration チェック完了！"