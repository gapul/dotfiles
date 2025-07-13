{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.dotfiles.system.nix-darwin-management;

  # nix-darwin switch wrapper
  nixDarwinSwitchScript = pkgs.writeShellScript "nix-darwin-switch" ''
    #!/usr/bin/env bash
    # Enhanced nix-darwin switch with proper environment handling
    set -euo pipefail

    # カラー定義
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'

    show_help() {
      cat << EOF
    Nix-Darwin Switch Manager

    Usage:
      nix-darwin-switch [options] [-- nix-darwin-args]

    Options:
      -p, --profile PROFILE     Use specific profile (default: default)
      -c, --check              Run flake check before switching
      -n, --dry-run            Show what would be built
      -v, --verbose            Verbose output
      -h, --help               Show this help

    Examples:
      nix-darwin-switch                    # Basic switch
      nix-darwin-switch --check           # Check then switch
      nix-darwin-switch -p macbook        # Use macbook profile
      nix-darwin-switch --dry-run         # Dry run
      nix-darwin-switch -- --show-trace   # Pass args to nix-darwin

    Environment Variables:
      DOTFILES_PROFILE=default            # Default profile name
      DOTFILES_FLAKE_PATH=$PWD            # Path to flake.nix
    EOF
    }

    # デフォルト設定
    PROFILE="''${DOTFILES_PROFILE:-default}"
    FLAKE_PATH="''${DOTFILES_FLAKE_PATH:-$PWD}"
    RUN_CHECK="false"
    DRY_RUN="false"
    VERBOSE="false"
    NIX_DARWIN_ARGS=()

    # 引数解析
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -p|--profile)
          PROFILE="$2"
          shift 2
          ;;
        -c|--check)
          RUN_CHECK="true"
          shift
          ;;
        -n|--dry-run)
          DRY_RUN="true"
          shift
          ;;
        -v|--verbose)
          VERBOSE="true"
          shift
          ;;
        -h|--help)
          show_help
          exit 0
          ;;
        --)
          shift
          NIX_DARWIN_ARGS=("$@")
          break
          ;;
        -*)
          echo -e "''${RED}Unknown option: $1''${NC}" >&2
          show_help
          exit 1
          ;;
        *)
          echo -e "''${RED}Unexpected argument: $1''${NC}" >&2
          show_help
          exit 1
          ;;
      esac
    done

    # フレーク構成
    FLAKE_REF="$FLAKE_PATH#$PROFILE"

    echo -e "''${BLUE}🔄 Nix-Darwin Switch Manager''${NC}"
    echo "=============================="
    echo -e "''${BLUE}Profile:''${NC} $PROFILE"
    echo -e "''${BLUE}Flake:''${NC} $FLAKE_REF"
    echo ""

    # ディレクトリチェック
    if [[ ! -f "$FLAKE_PATH/flake.nix" ]]; then
      echo -e "''${RED}❌ Error: flake.nix not found in $FLAKE_PATH''${NC}" >&2
      exit 1
    fi

    cd "$FLAKE_PATH"

    # Flake check (要求された場合)
    if [[ "$RUN_CHECK" == "true" ]]; then
      echo -e "''${YELLOW}🔍 Running flake check...''${NC}"
      if nix flake check --no-build; then
        echo -e "''${GREEN}✅ Flake check passed''${NC}"
      else
        echo -e "''${RED}❌ Flake check failed''${NC}" >&2
        exit 1
      fi
      echo ""
    fi

    # 環境変数の保存
    ORIGINAL_HOME="$HOME"
    ORIGINAL_USER="$USER"

    # nix-darwin switch実行
    if [[ "$DRY_RUN" == "true" ]]; then
      echo -e "''${YELLOW}🏗️  Dry run: showing what would be built...''${NC}"
      nix build "$FLAKE_REF" --dry-run
    else
      echo -e "''${BLUE}🚀 Running nix-darwin switch...''${NC}"
      
      local switch_cmd=(
        sudo env
        "HOME=$ORIGINAL_HOME"
        "USER=$ORIGINAL_USER"
        nix run nix-darwin -- switch
        --flake "$FLAKE_REF"
        --impure
      )

      # nix-darwin引数追加
      if [[ ''${#NIX_DARWIN_ARGS[@]} -gt 0 ]]; then
        switch_cmd+=("''${NIX_DARWIN_ARGS[@]}")
      fi

      # Verbose出力
      if [[ "$VERBOSE" == "true" ]]; then
        echo -e "''${YELLOW}Command:''${NC} ''${switch_cmd[*]}"
        echo ""
      fi

      # 実行
      if "''${switch_cmd[@]}"; then
        echo ""
        echo -e "''${GREEN}✅ nix-darwin switch completed successfully!''${NC}"
        echo -e "''${BLUE}📁 HOME preserved:''${NC} $ORIGINAL_HOME"
        echo -e "''${BLUE}👤 USER preserved:''${NC} $ORIGINAL_USER"
      else
        echo ""
        echo -e "''${RED}❌ nix-darwin switch failed''${NC}" >&2
        exit 1
      fi
    fi
  '';

  # システム最適化スクリプト
  systemOptimizerScript = pkgs.writeShellScript "system-optimizer" ''
    #!/usr/bin/env bash
    # System Optimization and Maintenance Script
    set -euo pipefail

    # カラー定義
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'

    show_help() {
      cat << EOF
    System Optimizer - Dotfiles Maintenance Tool

    Usage:
      system-optimizer [options]

    Options:
      -a, --all                Run all optimizations
      -n, --nix-cleanup        Nix store cleanup
      -b, --brew-cleanup       Homebrew cleanup
      -c, --cache-cleanup      Cache cleanup
      -s, --system-cleanup     System cleanup
      -d, --docker-cleanup     Docker cleanup
      -g, --git-maintenance    Git repository maintenance
      --dry-run               Show what would be done
      -v, --verbose           Verbose output
      -h, --help              Show this help

    Examples:
      system-optimizer --all               # Full system optimization
      system-optimizer -n -b               # Nix and Homebrew cleanup
      system-optimizer --dry-run --all     # Preview all actions
    EOF
    }

    # デフォルト設定
    RUN_ALL="false"
    NIX_CLEANUP="false"
    BREW_CLEANUP="false"
    CACHE_CLEANUP="false"
    SYSTEM_CLEANUP="false"
    DOCKER_CLEANUP="false"
    GIT_MAINTENANCE="false"
    DRY_RUN="false"
    VERBOSE="false"

    # 引数解析
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -a|--all)
          RUN_ALL="true"
          shift
          ;;
        -n|--nix-cleanup)
          NIX_CLEANUP="true"
          shift
          ;;
        -b|--brew-cleanup)
          BREW_CLEANUP="true"
          shift
          ;;
        -c|--cache-cleanup)
          CACHE_CLEANUP="true"
          shift
          ;;
        -s|--system-cleanup)
          SYSTEM_CLEANUP="true"
          shift
          ;;
        -d|--docker-cleanup)
          DOCKER_CLEANUP="true"
          shift
          ;;
        -g|--git-maintenance)
          GIT_MAINTENANCE="true"
          shift
          ;;
        --dry-run)
          DRY_RUN="true"
          shift
          ;;
        -v|--verbose)
          VERBOSE="true"
          shift
          ;;
        -h|--help)
          show_help
          exit 0
          ;;
        *)
          echo -e "''${RED}Unknown option: $1''${NC}" >&2
          show_help
          exit 1
          ;;
      esac
    done

    # 全実行の場合は全フラグを有効化
    if [[ "$RUN_ALL" == "true" ]]; then
      NIX_CLEANUP="true"
      BREW_CLEANUP="true"
      CACHE_CLEANUP="true"
      SYSTEM_CLEANUP="true"
      DOCKER_CLEANUP="true"
      GIT_MAINTENANCE="true"
    fi

    # 実行関数
    run_command() {
      local description="$1"
      shift
      local cmd=("$@")

      echo -e "''${BLUE}🔧 $description''${NC}"
      
      if [[ "$VERBOSE" == "true" ]]; then
        echo -e "''${YELLOW}Command:''${NC} ''${cmd[*]}"
      fi

      if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "''${YELLOW}[DRY RUN]''${NC} Would execute: ''${cmd[*]}"
      else
        if "''${cmd[@]}"; then
          echo -e "''${GREEN}✅ $description completed''${NC}"
        else
          echo -e "''${RED}❌ $description failed''${NC}" >&2
          return 1
        fi
      fi
      echo ""
    }

    echo -e "''${BLUE}🧹 System Optimizer''${NC}"
    echo "==================="
    echo ""

    # Nixストアクリーンアップ
    if [[ "$NIX_CLEANUP" == "true" ]]; then
      echo -e "''${BLUE}📦 Nix Store Cleanup''${NC}"
      
      if command -v nix &>/dev/null; then
        run_command "Nix garbage collection" nix store gc
        run_command "Nix store optimization" nix store optimise
      else
        echo -e "''${YELLOW}⚠️  Nix not available''${NC}"
      fi
    fi

    # Homebrewクリーンアップ  
    if [[ "$BREW_CLEANUP" == "true" ]]; then
      echo -e "''${BLUE}🍺 Homebrew Cleanup''${NC}"
      
      if command -v brew &>/dev/null; then
        run_command "Homebrew cleanup" brew cleanup --prune=all
        run_command "Homebrew autoremove" brew autoremove
      else
        echo -e "''${YELLOW}⚠️  Homebrew not available''${NC}"
      fi
    fi

    # キャッシュクリーンアップ
    if [[ "$CACHE_CLEANUP" == "true" ]]; then
      echo -e "''${BLUE}🗄️  Cache Cleanup''${NC}"
      
      # ユーザーキャッシュ
      if [[ -d "$HOME/Library/Caches" ]]; then
        run_command "User cache cleanup" find "$HOME/Library/Caches" -type f -atime +30 -delete
      fi

      # Node.js キャッシュ
      if command -v npm &>/dev/null; then
        run_command "npm cache cleanup" npm cache clean --force
      fi

      # Yarn キャッシュ
      if command -v yarn &>/dev/null; then
        run_command "Yarn cache cleanup" yarn cache clean
      fi
    fi

    # システムクリーンアップ
    if [[ "$SYSTEM_CLEANUP" == "true" ]]; then
      echo -e "''${BLUE}🖥️  System Cleanup''${NC}"
      
      # 一時ファイル
      run_command "Temporary files cleanup" find /tmp -type f -atime +7 -delete 2>/dev/null || true
      
      # ログファイル
      if [[ -d "$HOME/Library/Logs" ]]; then
        run_command "Log files cleanup" find "$HOME/Library/Logs" -name "*.log" -atime +30 -delete
      fi
    fi

    # Dockerクリーンアップ
    if [[ "$DOCKER_CLEANUP" == "true" ]]; then
      echo -e "''${BLUE}🐳 Docker Cleanup''${NC}"
      
      if command -v docker &>/dev/null; then
        run_command "Docker system prune" docker system prune -f
        run_command "Docker volume prune" docker volume prune -f
      else
        echo -e "''${YELLOW}⚠️  Docker not available''${NC}"
      fi
    fi

    # Gitメンテナンス
    if [[ "$GIT_MAINTENANCE" == "true" ]]; then
      echo -e "''${BLUE}🔀 Git Maintenance''${NC}"
      
      if [[ -d ".git" ]]; then
        run_command "Git garbage collection" git gc --aggressive
        run_command "Git fsck" git fsck
      else
        echo -e "''${YELLOW}⚠️  Not in a Git repository''${NC}"
      fi
    fi

    echo -e "''${GREEN}🎉 System optimization completed!''${NC}"

    # 空き容量表示
    if [[ "$DRY_RUN" != "true" ]]; then
      echo ""
      echo -e "''${BLUE}💾 Disk Usage:''${NC}"
      df -h / | tail -1
    fi
  '';

in {
  options.dotfiles.system.nix-darwin-management = {
    enable = mkEnableOption "Nix-Darwin Management Tools";

    defaultProfile = mkOption {
      type = types.str;
      default = "default";
      description = "Default nix-darwin profile name";
    };

    enableSystemOptimizer = mkOption {
      type = types.bool;
      default = true;
      description = "Enable system optimizer tool";
    };

    enableAutoCleanup = mkOption {
      type = types.bool;
      default = false;
      description = "Enable automatic periodic cleanup";
    };

    cleanupSchedule = mkOption {
      type = types.str;
      default = "weekly";
      description = "Cleanup schedule (daily, weekly, monthly)";
    };
  };

  config = mkIf cfg.enable {
    # パッケージ追加
    environment.systemPackages = with pkgs; [
      nixDarwinSwitchScript
    ] ++ optionals cfg.enableSystemOptimizer [
      systemOptimizerScript
    ];

    # 環境変数
    environment.variables = {
      DOTFILES_PROFILE = cfg.defaultProfile;
      DOTFILES_FLAKE_PATH = "/Users/$USER/dotfiles";
    };

    # シェルエイリアス
    programs.zsh.shellAliases = mkIf cfg.enable {
      "rebuild" = "nix-darwin-switch";
      "rebuild-check" = "nix-darwin-switch --check";
      "rebuild-dry" = "nix-darwin-switch --dry-run";
      "optimize" = "system-optimizer";
      "cleanup" = "system-optimizer --all";
      "nix-clean" = "system-optimizer --nix-cleanup";
    };

    programs.bash.shellAliases = mkIf cfg.enable {
      "rebuild" = "nix-darwin-switch";
      "rebuild-check" = "nix-darwin-switch --check";
      "rebuild-dry" = "nix-darwin-switch --dry-run";
      "optimize" = "system-optimizer";
      "cleanup" = "system-optimizer --all";
      "nix-clean" = "system-optimizer --nix-cleanup";
    };

    # 自動クリーンアップ (LaunchAgent) - macOSのみ
    launchd.agents = mkIf (cfg.enableAutoCleanup && pkgs.stdenv.isDarwin) {
      dotfiles-auto-cleanup = {
        enable = true;
        config = {
          ProgramArguments = [ "${systemOptimizerScript}" "--nix-cleanup" "--cache-cleanup" ];
          StartCalendarInterval = mkIf (cfg.cleanupSchedule == "weekly") [
            {
              Weekday = 0; # Sunday
              Hour = 2;
              Minute = 0;
            }
          ];
          RunAtLoad = false;
          StandardOutPath = "/tmp/dotfiles-auto-cleanup.log";
          StandardErrorPath = "/tmp/dotfiles-auto-cleanup.error.log";
        };
      };
    };
  };
}