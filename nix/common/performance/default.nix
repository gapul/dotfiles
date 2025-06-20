{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.performance;
in
{
  options.dotfiles.performance = {
    enable = mkEnableOption "Advanced performance optimization system";
    
    nixOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Nix store and build optimization";
    };
    
    shellOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable shell startup optimization";
    };
    
    lspOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable LSP performance tuning";
    };
    
    buildOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable build and deployment optimization";
    };
    
    monitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable performance monitoring and profiling";
    };
    
    cacheOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable advanced cache management";
    };
    
    parallelJobs = mkOption {
      type = types.int;
      default = 8;
      description = "Number of parallel build jobs";
    };
    
    maxMemory = mkOption {
      type = types.str;
      default = "8G";
      description = "Maximum memory allocation for builds";
    };
  };

  config = mkIf cfg.enable {
    # Performance optimization packages (macOS compatible)
    home-manager.users.yuki.home.packages = with pkgs; [
      # Performance monitoring tools
      htop
      btop
      # iotop - Linux only, not available on macOS
      # nethogs - Linux only, not available on macOS  
      # iftop - Not reliable on macOS
      
      # Build optimization
      ccache
      # distcc - Cross-platform issues, skip for now
      
      # Memory optimization - macOS has different approach
      # zram-generator - Linux only
      
      # Disk optimization - macOS uses different utilities
      # fstrim - Linux only
      
      # Network optimization
      iperf3
      
      # Profiling tools (cross-platform)
      # perf-tools - Linux only
      # flamegraph - Available but requires setup
      
    ] ++ optionals cfg.monitoring [
      # Advanced monitoring (cross-platform)
      # sysstat - Linux only
      # atop - Linux only  
      # nmon - Linux only
      
    ] ++ optionals cfg.buildOptimization [
      # Build acceleration
      ninja
      # mold - Linux only fast linker
      # lld - Available but integration complex
    ];

    # Nix configuration optimization (nix-darwin compatible)
    nix = mkIf cfg.nixOptimization {
      settings = {
        # Build optimization
        max-jobs = cfg.parallelJobs;
        cores = cfg.parallelJobs;
        
        # Memory optimization
        max-free = mkDefault (1024 * 1024 * 1024 * 2); # 2GB
        min-free = mkDefault (1024 * 1024 * 1024 * 1); # 1GB
        
        # Build efficiency
        keep-outputs = true;
        keep-derivations = true;
        
        # Cache optimization
        auto-optimise-store = true;
        
        # Substituters for faster downloads
        substituters = [
          "https://cache.nixos.org/"
          "https://nix-community.cachix.org"
          "https://devenv.cachix.org"
        ];
        
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
        
        # Experimental features for performance
        experimental-features = [
          "nix-command"
          "flakes"
          "auto-allocate-uids"
          # "cgroups" - Linux only
        ];
      };
    };

    # Shell optimization
    home-manager.users.yuki.programs.zsh = mkIf cfg.shellOptimization {
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      
      # Fast completion system
      completionInit = ''
        # Initialize completion system with optimization
        autoload -Uz compinit
        
        # Only check compinit once per day for speed
        if [[ -n ${HOME}/.zcompdump(#qN.mh+24) ]]; then
          compinit -d ${HOME}/.zcompdump
        else
          compinit -C -d ${HOME}/.zcompdump
        fi
        
        # Speed up completion
        zstyle ':completion:*' use-cache true
        zstyle ':completion:*' cache-path ${HOME}/.zsh/cache
        
        # Faster directory completion
        zstyle ':completion:*:*:cd:*:directory-stack' menu yes select
        zstyle ':completion:*' menu select
        
        # Performance optimization
        zstyle ':completion:*' accept-exact '*(N)'
        zstyle ':completion:*' special-dirs true
      '';
      
      # Optimized shell aliases
      shellAliases = {
        # Fast navigation
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";
        
        # Performance commands
        perf-monitor = "performance-monitor";
        perf-analyze = "performance-analyze";
        perf-optimize = "performance-optimize";
        perf-clean = "performance-clean";
        
        # Fast file operations
        ll = "eza -la --group-directories-first";
        lt = "eza --tree --level=2";
        lh = "eza -la --group-directories-first | head -20";
        
        # Fast search
        ff = "fd";
        rg = "rg --smart-case --hidden";
        
        # Memory optimization
        mem-clean = "sudo purge"; # macOS specific
        disk-clean = "performance-disk-cleanup";
        
        # Nix optimization
        nix-clean = "nix store gc && nix store optimise";
        nix-update = "nix flake update";
        nix-check = "nix flake check --impure";
      };
      
      # Optimized history settings
      history = {
        size = 100000;
        save = 100000;
        share = true;
        ignoreDups = true;
        ignoreSpace = true;
        expireDuplicatesFirst = true;
      };
      
      # Performance initialization
      initExtra = ''
        # Lazy load heavy tools for faster startup
        lazy_load() {
          local cmd="$1"
          shift
          eval "$cmd() { unfunction $cmd; source <($@); $cmd \$@; }"
        }
        
        # Performance monitoring
        perf_start_time=$EPOCHREALTIME
        precmd_functions+=(track_command_time)
        track_command_time() {
          if [[ -n $perf_start_time ]]; then
            local duration=$(( EPOCHREALTIME - perf_start_time ))
            if (( duration > 0.1 )); then
              echo "[⏱️  ''${duration:.3f}s]"
            fi
          fi
          perf_start_time=$EPOCHREALTIME
        }
        
        # Fast directory jumping
        export CDPATH=".:$HOME:$HOME/dotfiles:$HOME/Documents:$HOME/Projects"
        
        # Performance environment variables
        export HISTCONTROL=ignoreboth:erasedups
        export HISTIGNORE="ls:cd:cd -:pwd:exit:date:* --help"
        export PERFORMANCE_MONITORING=true
      '';
    };

    # LSP optimization configuration
    home-manager.users.yuki.home.file.".config/nvim/lua/performance.lua" = mkIf cfg.lspOptimization {
      text = ''
        -- LSP Performance Optimization
        local M = {}
        
        -- Optimize LSP settings for performance
        M.setup_lsp_performance = function()
          -- Reduce LSP overhead
          vim.lsp.set_log_level("WARN")
          
          -- Optimize completion
          vim.opt.completeopt = { "menu", "menuone", "noselect" }
          vim.opt.pumheight = 10
          
          -- Faster syntax highlighting
          vim.opt.syntax = "enable"
          vim.opt.synmaxcol = 200
          
          -- Performance settings
          vim.opt.updatetime = 300
          vim.opt.timeoutlen = 500
          vim.opt.ttimeoutlen = 10
          
          -- Memory optimization
          vim.opt.maxmempattern = 2000
          vim.opt.history = 1000
          
          -- Faster file operations
          vim.opt.backup = false
          vim.opt.writebackup = false
          vim.opt.swapfile = false
        end
        
        -- Monitor LSP performance
        M.monitor_lsp = function()
          local function get_lsp_stats()
            local clients = vim.lsp.get_active_clients()
            local stats = {}
            
            for _, client in ipairs(clients) do
              table.insert(stats, {
                name = client.name,
                requests = client.requests or {},
                offset_encoding = client.offset_encoding
              })
            end
            
            return stats
          end
          
          vim.api.nvim_create_user_command("LspPerf", function()
            local stats = get_lsp_stats()
            print(vim.inspect(stats))
          end, {})
        end
        
        return M
      '';
    };

    # Performance monitoring system
    home-manager.users.yuki.home.file."bin/performance-monitor" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Advanced Performance Monitoring System
        set -euo pipefail
        
        ACTION="''${1:-status}"
        DURATION="''${2:-60}"
        
        echo "📊 Performance Monitoring System"
        echo "================================"
        echo "Action: $ACTION"
        echo "Duration: ''${DURATION}s"
        echo ""
        
        case "$ACTION" in
          "status")
            echo "🖥️  System Status:"
            
            # CPU usage
            if command -v btop &> /dev/null; then
              echo "📈 CPU Usage:"
              btop --snapshot | head -10
            else
              echo "📈 CPU Usage: $(top -l 1 | grep "CPU usage" || echo "N/A")"
            fi
            
            # Memory usage
            if [[ "$(uname)" == "Darwin" ]]; then
              echo ""
              echo "💾 Memory Usage:"
              vm_stat | head -5
              echo "Total Memory: $(system_profiler SPHardwareDataType | grep "Memory:" | awk '{print $2" "$3}')"
            else
              echo ""
              echo "💾 Memory Usage:"
              free -h
            fi
            
            # Disk usage
            echo ""
            echo "💿 Disk Usage:"
            df -h / | tail -1
            
            # Nix store size
            if [[ -d /nix/store ]]; then
              echo ""
              echo "❄️  Nix Store:"
              echo "Size: $(du -sh /nix/store 2>/dev/null | cut -f1)"
              echo "Items: $(find /nix/store -maxdepth 1 -type d | wc -l | tr -d ' ')"
            fi
            
            # Development tools performance
            echo ""
            echo "🛠️  Development Performance:"
            
            # Shell startup time
            SHELL_TIME=$(time (zsh -i -c exit) 2>&1 | grep real | awk '{print $2}')
            echo "Shell startup: $SHELL_TIME"
            
            # LSP responsiveness
            if command -v nvim &> /dev/null; then
              echo "LSP check: Available"
            fi
            ;;
            
          "analyze")
            echo "🔍 Performance Analysis..."
            
            # Create performance report
            REPORT_DIR="$HOME/.performance-reports"
            mkdir -p "$REPORT_DIR"
            REPORT_FILE="$REPORT_DIR/performance-$(date +%Y%m%d_%H%M%S).txt"
            
            {
              echo "Performance Analysis Report"
              echo "Generated: $(date)"
              echo "Duration: ''${DURATION}s"
              echo ""
              
              # System information
              echo "=== System Information ==="
              uname -a
              echo ""
              
              if [[ "$(uname)" == "Darwin" ]]; then
                system_profiler SPHardwareDataType | head -10
              else
                lscpu | head -10
              fi
              
              echo ""
              echo "=== Resource Usage Over Time ==="
              
              # Monitor for specified duration
              for i in $(seq 1 "$DURATION"); do
                echo "[$i/$DURATION] $(date)"
                
                # CPU
                if [[ "$(uname)" == "Darwin" ]]; then
                  top -l 1 | grep "CPU usage" || echo "CPU: N/A"
                else
                  grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4)} END {print "CPU: " usage "%"}'
                fi
                
                # Memory
                if [[ "$(uname)" == "Darwin" ]]; then
                  vm_stat | head -3
                else
                  free | grep Mem | awk '{print "Memory: " ($3/$2)*100 "%"}'
                fi
                
                echo "---"
                sleep 1
              done
              
            } > "$REPORT_FILE"
            
            echo "✅ Analysis complete: $REPORT_FILE"
            ;;
            
          "optimize")
            echo "⚡ Performance Optimization..."
            
            # Nix optimization
            echo "1. Optimizing Nix store..."
            if command -v nix &> /dev/null; then
              nix store gc --verbose
              nix store optimise
              echo "✅ Nix store optimized"
            fi
            
            # Clear system caches
            echo ""
            echo "2. Clearing system caches..."
            if [[ "$(uname)" == "Darwin" ]]; then
              sudo purge
              echo "✅ macOS caches cleared"
            else
              sync
              echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
              echo "✅ Linux caches cleared"
            fi
            
            # Clean development environments
            echo ""
            echo "3. Cleaning development environments..."
            
            # Clean npm cache
            if command -v npm &> /dev/null; then
              npm cache clean --force
              echo "✅ npm cache cleaned"
            fi
            
            # Clean cargo cache
            if command -v cargo &> /dev/null; then
              cargo clean
              echo "✅ cargo cache cleaned"
            fi
            
            # Clean Docker
            if command -v docker &> /dev/null; then
              docker system prune -f
              echo "✅ Docker cache cleaned"
            fi
            
            echo ""
            echo "🎉 Performance optimization complete!"
            ;;
            
          "benchmark")
            echo "🏃 Performance Benchmarking..."
            
            # Shell startup benchmark
            echo "Shell startup benchmark:"
            for i in {1..5}; do
              time (zsh -i -c exit) 2>&1 | grep real
            done
            
            # File operations benchmark
            echo ""
            echo "File operations benchmark:"
            TEMP_DIR=$(mktemp -d)
            
            # Create files test
            time (for i in {1..1000}; do touch "$TEMP_DIR/file$i"; done) 2>&1 | grep real
            
            # Search test
            time (find "$TEMP_DIR" -name "file*" | wc -l) 2>&1 | grep real
            
            # Cleanup
            rm -rf "$TEMP_DIR"
            
            # Network benchmark
            if command -v iperf3 &> /dev/null; then
              echo ""
              echo "Network benchmark available (iperf3)"
            fi
            ;;
            
          *)
            echo "Usage: performance-monitor <action> [duration]"
            echo ""
            echo "Actions:"
            echo "  status     - Show current system status"
            echo "  analyze    - Analyze performance over time"
            echo "  optimize   - Optimize system performance"
            echo "  benchmark  - Run performance benchmarks"
            echo ""
            echo "Duration: Time in seconds for analysis (default: 60)"
            ;;
        esac
      '';
    };

    # Advanced cache management
    home-manager.users.yuki.home.file."bin/performance-cache-manager" = mkIf cfg.cacheOptimization {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Advanced Cache Management System
        set -euo pipefail
        
        ACTION="''${1:-status}"
        
        echo "🗄️  Cache Management System"
        echo "=========================="
        echo "Action: $ACTION"
        echo ""
        
        case "$ACTION" in
          "status")
            echo "📊 Cache Status:"
            echo ""
            
            # Nix store
            if [[ -d /nix/store ]]; then
              echo "❄️  Nix Store: $(du -sh /nix/store 2>/dev/null | cut -f1)"
            fi
            
            # npm cache
            if command -v npm &> /dev/null; then
              NPM_CACHE=$(npm config get cache)
              if [[ -d "$NPM_CACHE" ]]; then
                echo "📦 npm cache: $(du -sh "$NPM_CACHE" 2>/dev/null | cut -f1)"
              fi
            fi
            
            # Cargo cache
            if [[ -d "$HOME/.cargo" ]]; then
              echo "🦀 Cargo cache: $(du -sh "$HOME/.cargo" 2>/dev/null | cut -f1)"
            fi
            
            # Docker cache
            if command -v docker &> /dev/null; then
              echo "🐳 Docker: $(docker system df 2>/dev/null | tail -n +2)"
            fi
            
            # LSP cache
            if [[ -d "$HOME/.cache/nvim" ]]; then
              echo "📝 Neovim cache: $(du -sh "$HOME/.cache/nvim" 2>/dev/null | cut -f1)"
            fi
            ;;
            
          "clean")
            echo "🧹 Cleaning caches..."
            
            CLEANED=0
            
            # Clean Nix store
            if command -v nix &> /dev/null; then
              echo "Cleaning Nix store..."
              nix store gc --verbose
              ((CLEANED++))
            fi
            
            # Clean npm cache
            if command -v npm &> /dev/null; then
              echo "Cleaning npm cache..."
              npm cache clean --force
              ((CLEANED++))
            fi
            
            # Clean cargo cache
            if command -v cargo &> /dev/null; then
              echo "Cleaning cargo cache..."
              cargo clean
              ((CLEANED++))
            fi
            
            # Clean Docker cache
            if command -v docker &> /dev/null; then
              echo "Cleaning Docker cache..."
              docker system prune -f
              ((CLEANED++))
            fi
            
            # Clean development caches
            echo "Cleaning development caches..."
            
            # Remove node_modules directories older than 30 days
            find "$HOME" -name "node_modules" -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
            
            # Clean LSP and editor caches
            rm -rf "$HOME/.cache/nvim/lsp" 2>/dev/null || true
            rm -rf "$HOME/.cache/vscode" 2>/dev/null || true
            
            ((CLEANED++))
            
            echo ""
            echo "✅ Cache cleaning complete! ($CLEANED systems cleaned)"
            ;;
            
          "optimize")
            echo "⚡ Optimizing caches..."
            
            # Optimize Nix store
            if command -v nix &> /dev/null; then
              echo "Optimizing Nix store..."
              nix store optimise
            fi
            
            # Setup cache directories
            echo "Setting up cache directories..."
            mkdir -p "$HOME/.cache/zsh"
            mkdir -p "$HOME/.cache/nvim"
            mkdir -p "$HOME/.cache/performance"
            
            # Configure cache sizes
            echo "Configuring cache limits..."
            
            # Limit npm cache size
            if command -v npm &> /dev/null; then
              npm config set cache-max 1073741824  # 1GB
            fi
            
            echo "✅ Cache optimization complete!"
            ;;
            
          *)
            echo "Usage: performance-cache-manager <action>"
            echo ""
            echo "Actions:"
            echo "  status     - Show cache status"
            echo "  clean      - Clean all caches"
            echo "  optimize   - Optimize cache configuration"
            ;;
        esac
      '';
    };

    # Build optimization configuration
    home-manager.users.yuki.home.sessionVariables = mkIf cfg.buildOptimization {
      # Parallel compilation
      MAKEFLAGS = "-j${toString cfg.parallelJobs}";
      CMAKE_BUILD_PARALLEL_LEVEL = toString cfg.parallelJobs;
      
      # Rust optimization
      CARGO_BUILD_JOBS = toString cfg.parallelJobs;
      CARGO_BUILD_INCREMENTAL = "true";
      
      # Node.js optimization
      UV_THREADPOOL_SIZE = toString cfg.parallelJobs;
      
      # Memory limits
      NIX_BUILD_MEMORY_LIMIT = cfg.maxMemory;
      
      # Cache directories
      CCACHE_DIR = "$HOME/.cache/ccache";
      CARGO_HOME = "$HOME/.cache/cargo";
      
      # Performance monitoring
      PERFORMANCE_OPTIMIZATION = "enabled";
    };

    # Performance health check
    home-manager.users.yuki.home.file."bin/performance-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "⚡ Performance System Health Check"
        echo "================================="
        echo ""
        
        ISSUES=0
        
        # Check Nix optimization
        ${if cfg.nixOptimization then ''
          echo "❄️  Nix Optimization:"
          if nix show-config | grep -q "auto-optimise-store = true"; then
            echo "  ✅ Auto-optimise enabled"
          else
            echo "  ⚠️  Auto-optimise disabled"
            ((ISSUES++))
          fi
          
          MAX_JOBS=$(nix show-config | grep "max-jobs" | cut -d'=' -f2 | tr -d ' ')
          echo "  📊 Max jobs: $MAX_JOBS"
        '' else ''
          echo "❄️  Nix Optimization: Disabled"
        ''}
        
        # Check shell performance
        ${if cfg.shellOptimization then ''
          echo ""
          echo "🐚 Shell Optimization:"
          if [[ -f "$HOME/.zcompdump" ]]; then
            echo "  ✅ Completion cache exists"
          else
            echo "  ⚠️  No completion cache"
            ((ISSUES++))
          fi
          
          # Test shell startup time
          SHELL_TIME=$(time (zsh -i -c exit) 2>&1 | grep real | awk '{print $2}' | tr -d 's')
          if (( $(echo "$SHELL_TIME < 1" | bc -l) )); then
            echo "  ✅ Shell startup: ''${SHELL_TIME}s (fast)"
          else
            echo "  ⚠️  Shell startup: ''${SHELL_TIME}s (slow)"
          fi
        '' else ''
          echo ""
          echo "🐚 Shell Optimization: Disabled"
        ''}
        
        # Check monitoring tools
        ${if cfg.monitoring then ''
          echo ""
          echo "📊 Performance Monitoring:"
          if command -v performance-monitor &> /dev/null; then
            echo "  ✅ Performance monitor: Available"
          else
            echo "  ❌ Performance monitor: Not found"
            ((ISSUES++))
          fi
          
          if command -v btop &> /dev/null; then
            echo "  ✅ btop: Available"
          else
            echo "  ⚠️  btop: Not available"
          fi
        '' else ''
          echo ""
          echo "📊 Performance Monitoring: Disabled"
        ''}
        
        # Check cache optimization
        ${if cfg.cacheOptimization then ''
          echo ""
          echo "🗄️  Cache Optimization:"
          if command -v performance-cache-manager &> /dev/null; then
            echo "  ✅ Cache manager: Available"
          else
            echo "  ❌ Cache manager: Not found"
            ((ISSUES++))
          fi
          
          if [[ -d "$HOME/.cache" ]]; then
            CACHE_SIZE=$(du -sh "$HOME/.cache" 2>/dev/null | cut -f1)
            echo "  📊 Cache size: $CACHE_SIZE"
          fi
        '' else ''
          echo ""
          echo "🗄️  Cache Optimization: Disabled"
        ''}
        
        # System resources
        echo ""
        echo "💻 System Resources:"
        
        # CPU cores
        if [[ "$(uname)" == "Darwin" ]]; then
          CPU_CORES=$(sysctl -n hw.ncpu)
        else
          CPU_CORES=$(nproc)
        fi
        echo "  🖥️  CPU cores: $CPU_CORES"
        
        # Memory
        if [[ "$(uname)" == "Darwin" ]]; then
          MEMORY=$(system_profiler SPHardwareDataType | grep "Memory:" | awk '{print $2" "$3}')
        else
          MEMORY=$(free -h | grep "Mem:" | awk '{print $2}')
        fi
        echo "  💾 Memory: $MEMORY"
        
        # Build settings
        echo ""
        echo "🔧 Build Configuration:"
        echo "  ⚙️  Parallel jobs: ${toString cfg.parallelJobs}"
        echo "  📏 Memory limit: ${cfg.maxMemory}"
        
        # Summary
        echo ""
        echo "📋 Performance Status:"
        if [[ $ISSUES -eq 0 ]]; then
          echo "  ✅ Performance system: Fully optimized"
        else
          echo "  ⚠️  Performance system: $ISSUES issues detected"
        fi
        
        echo ""
        echo "🚀 Available Commands:"
        echo "  performance-monitor      - System monitoring"
        echo "  performance-cache-manager - Cache management"
        echo "  performance-health       - This health check"
      '';
    };

    # Shell aliases for performance
    home-manager.users.yuki.programs.zsh.shellAliases = {
      perf = "performance-monitor";
      perf-health = "performance-health";
      perf-cache = "performance-cache-manager";
      perf-clean = "performance-cache-manager clean && performance-monitor optimize";
      
      # Quick performance commands
      top = "btop";
      htop = "btop";
      iotop = "btop";
    };

    # Performance environment variables
    home-manager.users.yuki.home.sessionVariables = {
      PERFORMANCE_SYSTEM_ENABLED = "true";
      PERFORMANCE_PARALLEL_JOBS = toString cfg.parallelJobs;
      PERFORMANCE_MAX_MEMORY = cfg.maxMemory;
    };
  };
}