{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.dotfiles.system.health-check;

  # 統一ヘルスチェック機能
  healthCheckScript = pkgs.writeShellScript "dotfiles-health-check" ''
    #!/usr/bin/env bash
    # Unified Dotfiles Health Check System
    set -euo pipefail

    # カラー定義
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    # ヘルスチェック関数
    check_status() {
      local status=$1
      local message=$2
      if [[ $status -eq 0 ]]; then
        echo -e "  ''${GREEN}✅''${NC} $message"
        return 0
      else
        echo -e "  ''${RED}❌''${NC} $message"
        return 1
      fi
    }

    warning_status() {
      local message=$1
      echo -e "  ''${YELLOW}⚠️''${NC} $message"
    }

    info_status() {
      local message=$1
      echo -e "  ''${BLUE}ℹ️''${NC} $message"
    }

    # メインヘルスチェック関数
    health_check_main() {
      echo -e "''${BLUE}🏥 Dotfiles Unified Health Check''${NC}"
      echo "=================================="
      echo ""

      local overall_status=0

      # 1. システム基本チェック
      echo "📋 System Basics:"
      check_status 0 "macOS: $(sw_vers -productVersion)"
      
      if [[ -d "/nix/store" ]]; then
        local nix_size=$(du -sh /nix/store 2>/dev/null | cut -f1)
        check_status 0 "Nix Store: $nix_size"
      else
        check_status 1 "Nix Store: Not found"
        overall_status=1
      fi

      if command -v brew &>/dev/null; then
        local formulae_count=$(/opt/homebrew/bin/brew list --formula 2>/dev/null | wc -l | tr -d ' ')
        local cask_count=$(/opt/homebrew/bin/brew list --cask 2>/dev/null | wc -l | tr -d ' ')
        check_status 0 "Homebrew: $formulae_count formulae, $cask_count casks"
      else
        warning_status "Homebrew: Not available"
      fi
      echo ""

      # 2. Modern CLI Tools チェック
      echo "🛠️  Modern CLI Tools:"
      local cli_tools=(${toString cfg.cliTools})
      for tool in $cli_tools; do
        if command -v "$tool" &>/dev/null; then
          local version=$(eval "$tool --version 2>/dev/null | head -1" || echo "installed")
          check_status 0 "$tool: $version"
        else
          check_status 1 "$tool: Not found"
          overall_status=1
        fi
      done
      echo ""

      # 3. AI Platform チェック
      echo "🤖 AI Platform:"
      if command -v ollama &>/dev/null; then
        local ollama_status=$(ollama list 2>/dev/null | wc -l || echo "0")
        check_status 0 "Ollama: $ollama_status models available"
      else
        warning_status "Ollama: Not installed"
      fi

      if command -v sgpt &>/dev/null; then
        check_status 0 "shell-gpt: Available"
      else
        warning_status "shell-gpt: Not installed"
      fi
      echo ""

      # 4. Development Environment チェック
      echo "💻 Development Environment:"
      
      # Git設定チェック
      if git config --global user.email &>/dev/null && git config --global user.name &>/dev/null; then
        local git_email=$(git config --global user.email)
        local git_name=$(git config --global user.name)
        check_status 0 "Git Config: $git_name <$git_email>"
      else
        check_status 1 "Git Config: Incomplete"
        overall_status=1
      fi

      # Neovim設定チェック
      if [[ -f "$HOME/.config/nvim/init.lua" ]]; then
        check_status 0 "Neovim: Configuration found"
      else
        warning_status "Neovim: Configuration not found"
      fi

      # Zsh設定チェック
      if [[ -f "$HOME/.zshrc" ]]; then
        check_status 0 "Zsh: Configuration active"
      else
        warning_status "Zsh: Default configuration"
      fi
      echo ""

      # 5. セキュリティチェック
      echo "🔐 Security:"
      
      # SSH設定チェック
      if [[ -f "$HOME/.ssh/config" ]]; then
        check_status 0 "SSH: Configuration found"
      else
        warning_status "SSH: No custom configuration"
      fi

      # GPG設定チェック  
      if command -v gpg &>/dev/null && gpg --list-secret-keys &>/dev/null; then
        local gpg_keys=$(gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep -c "^sec" || echo "0")
        check_status 0 "GPG: $gpg_keys secret keys"
      else
        warning_status "GPG: No keys configured"
      fi
      echo ""

      # 6. 設定ファイルチェック
      echo "⚙️  Configuration Files:"
      local config_files=(
        "$HOME/.config/bat/config"
        "$HOME/.config/bottom/bottom.toml"
        "$HOME/.config/yazi/theme.toml"
        "$HOME/.config/ripgrep/config"
      )

      for config_file in "''${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
          check_status 0 "$(basename "$config_file"): Found"
        else
          warning_status "$(basename "$config_file"): Not found"
        fi
      done
      echo ""

      # 7. 重要なアプリケーションチェック
      echo "📱 Important Applications:"
      local important_apps=(${toString (map (app: ''"${app}"'') cfg.importantApps)})
      for app in $important_apps; do
        if [[ -d "/Applications/$app" ]]; then
          check_status 0 "$app: Installed"
        else
          check_status 1 "$app: Not found"
        fi
      done
      echo ""

      # 8. 全体サマリー
      echo "📊 Health Check Summary:"
      if [[ $overall_status -eq 0 ]]; then
        echo -e "  ''${GREEN}🎉 All critical systems are healthy!''${NC}"
      else
        echo -e "  ''${YELLOW}⚠️  Some issues detected, but system is functional''${NC}"
      fi
      echo ""

      # 9. 推奨アクション
      echo "🎯 Recommended Actions:"
      echo "  • Quick check: dotfiles-quick-check"
      echo "  • System rebuild: cd ~/dotfiles && just rebuild"
      echo "  • Update packages: cd ~/dotfiles && just update"
      echo "  • Clean system: cd ~/dotfiles && just clean"
      echo ""

      return $overall_status
    }

    # クイックチェック関数
    quick_check() {
      echo -e "''${BLUE}🔍 Quick System Check''${NC}"
      echo "===================="
      echo ""

      echo "✅ System Status:"
      echo "  • macOS: $(sw_vers -productVersion)"
      
      if [[ -d "/nix/store" ]]; then
        echo "  • Nix Store: $(du -sh /nix/store 2>/dev/null | cut -f1)"
      fi
      
      if command -v brew &>/dev/null; then
        local formulae=$(/opt/homebrew/bin/brew list --formula 2>/dev/null | wc -l | tr -d ' ')
        local casks=$(/opt/homebrew/bin/brew list --cask 2>/dev/null | wc -l | tr -d ' ')
        echo "  • Homebrew: $formulae formulae, $casks casks"
      fi
      echo ""

      echo "✅ Git Config:"
      if git config --global user.email &>/dev/null; then
        echo "  • Email: $(git config --global user.email)"
        echo "  • Name: $(git config --global user.name)"
      else
        echo "  • Git: Not configured"
      fi
      echo ""

      echo "🎯 Next Actions:"
      echo "  • Full health check: dotfiles-health-check"
      echo "  • System rebuild: cd ~/dotfiles && just rebuild"
      echo "  • Homebrew check: brew doctor"
    }

    # 引数に応じて実行
    case "''${1:-full}" in
      "quick"|"-q"|"--quick")
        quick_check
        ;;
      "full"|"-f"|"--full"|"")
        health_check_main
        ;;
      *)
        echo "Usage: dotfiles-health-check [quick|full]"
        echo "  quick: Basic system status"
        echo "  full:  Comprehensive health check (default)"
        exit 1
        ;;
    esac
  '';

  # クイックチェック専用スクリプト
  quickCheckScript = pkgs.writeShellScript "dotfiles-quick-check" ''
    ${healthCheckScript} quick
  '';

in {
  options.dotfiles.system.health-check = {
    enable = mkEnableOption "Unified Health Check System";

    cliTools = mkOption {
      type = types.listOf types.str;
      default = [ "eza" "bat" "rg" "fd" "zoxide" "lazygit" "yazi" "btm" ];
      description = "CLI tools to check in health check";
    };

    importantApps = mkOption {
      type = types.listOf types.str;
      default = [ "VOICEVOX.app" "battery.app" "Claude.app" "Zed.app" ];
      description = "Important applications to check";
    };

    enableQuickCheck = mkOption {
      type = types.bool;
      default = true;
      description = "Enable quick check command";
    };
  };

  config = mkIf cfg.enable {
    # ヘルスチェックコマンドを追加
    environment.systemPackages = with pkgs; [
      healthCheckScript
    ] ++ optionals cfg.enableQuickCheck [
      quickCheckScript
    ];

    # シェルエイリアス追加
    programs.zsh.shellAliases = mkIf cfg.enable {
      "health" = "dotfiles-health-check";
      "health-quick" = "dotfiles-health-check quick";
      "quick-check" = "dotfiles-quick-check";
    };

    programs.bash.shellAliases = mkIf cfg.enable {
      "health" = "dotfiles-health-check";
      "health-quick" = "dotfiles-health-check quick";
      "quick-check" = "dotfiles-quick-check";
    };
  };
}