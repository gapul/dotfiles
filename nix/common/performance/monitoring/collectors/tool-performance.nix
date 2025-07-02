# Tool Performance Monitoring Collector
# Monitors development tool performance: LSP, editors, compilers, Git operations
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.performance.monitoring.toolPerformance = {
    enable = mkEnableOption "Tool performance monitoring and analysis";
    
    monitorLSP = mkOption {
      type = types.bool;
      default = true;
      description = "Monitor Language Server Protocol response times";
    };
    
    monitorEditors = mkOption {
      type = types.bool;
      default = true;
      description = "Monitor editor startup and operation times";
    };
    
    monitorCompilers = mkOption {
      type = types.bool;
      default = true;
      description = "Monitor compiler and build tool performance";
    };
    
    monitorGitOps = mkOption {
      type = types.bool;
      default = true;
      description = "Monitor Git operation performance";
    };
    
    monitorTerminal = mkOption {
      type = types.bool;
      default = false;
      description = "Monitor terminal and shell performance";
    };
    
    detailedProfiling = mkOption {
      type = types.bool;
      default = false;
      description = "Enable detailed profiling with memory and CPU tracking";
    };
  };

  config = mkIf (config.dotfiles.performance.enable && config.dotfiles.performance.monitoring.toolPerformance.enable) {
    # Tool performance monitoring scripts
    environment.systemPackages = with pkgs; [
      # Main tool performance tracker
      (writeShellScriptBin "dotfiles-track-tool" ''
        #!/bin/bash
        
        # Universal tool performance tracker
        # Usage: dotfiles-track-tool <tool_name> <operation> <command...>
        
        set -euo pipefail
        
        if [ $# -lt 3 ]; then
          echo "Usage: $0 <tool_name> <operation> <command...>"
          echo "Example: $0 nvim startup nvim --version"
          exit 1
        fi
        
        TOOL_NAME="$1"
        OPERATION="$2"
        shift 2
        
        METRICS_DB="/var/lib/dotfiles-performance/metrics/performance.db"
        USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
        
        mkdir -p "$USER_METRICS_DIR"
        
        # Prepare tracking
        START_TIME_MS=$(date +%s%3N)
        START_TIME=$(date +%s)
        
        # Get initial memory usage (if detailed profiling enabled)
        INITIAL_MEMORY=0
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.detailedProfiling ''
          if command -v ps >/dev/null; then
            INITIAL_MEMORY=$(ps -o rss= -p $$ 2>/dev/null || echo "0")
          fi
        ''}
        
        # Execute the command and capture result
        echo "Tracking: $TOOL_NAME $OPERATION"
        echo "Command: $*"
        
        set +e
        ${if config.dotfiles.performance.monitoring.toolPerformance.detailedProfiling then ''
          # Detailed profiling with time and memory
          (time "$@") 2>&1
          RESULT=$?
        '' else ''
          # Simple execution
          "$@" >/dev/null 2>&1
          RESULT=$?
        ''}
        set -e
        
        # Calculate duration
        END_TIME_MS=$(date +%s%3N)
        DURATION_MS=$((END_TIME_MS - START_TIME_MS))
        
        # Get peak memory usage (approximation)
        PEAK_MEMORY=0
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.detailedProfiling ''
          if command -v ps >/dev/null; then
            PEAK_MEMORY=$(ps -o rss= -p $$ 2>/dev/null || echo "$INITIAL_MEMORY")
          fi
        ''}
        
        SUCCESS=$([ $RESULT -eq 0 ] && echo "1" || echo "0")
        
        echo "Completed in $DURATION_MS ms (success: $SUCCESS)"
        
        # Store in database
        if [ -f "$METRICS_DB" ]; then
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            INSERT INTO tool_performance (
              timestamp, tool_name, operation, duration_ms, memory_peak_mb, 
              success, working_directory
            ) VALUES (
              $START_TIME, '$TOOL_NAME', '$OPERATION', $DURATION_MS, 
              $(echo "scale=2; $PEAK_MEMORY / 1024" | ${bc}/bin/bc), 
              $SUCCESS, '$(pwd)'
            );
EOF
        fi
        
        # Log to file
        echo "$(date): $TOOL_NAME $OPERATION - $DURATION_MS ms (success: $SUCCESS)" >> "$USER_METRICS_DIR/tool-performance.log"
        
        exit $RESULT
      '')
      
      # LSP Performance Monitor
      (writeShellScriptBin "dotfiles-monitor-lsp" ''
        #!/bin/bash
        
        # Monitor Language Server Protocol performance
        
        echo "🔍 Monitoring LSP Performance"
        
        USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
        mkdir -p "$USER_METRICS_DIR"
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorLSP ''
          # Test LSP response times for common languages
          
          # Nix LSP (nil)
          if command -v nil >/dev/null; then
            echo "Testing Nix LSP (nil)..."
            dotfiles-track-tool nil startup nil --version
          fi
          
          # TypeScript LSP
          if command -v typescript-language-server >/dev/null; then
            echo "Testing TypeScript LSP..."
            dotfiles-track-tool typescript-lsp startup typescript-language-server --version
          fi
          
          # Rust LSP (rust-analyzer)
          if command -v rust-analyzer >/dev/null; then
            echo "Testing Rust LSP..."
            dotfiles-track-tool rust-analyzer startup rust-analyzer --version
          fi
          
          # Go LSP (gopls)
          if command -v gopls >/dev/null; then
            echo "Testing Go LSP..."
            dotfiles-track-tool gopls startup gopls version
          fi
          
          # Python LSP (if available)
          if command -v pylsp >/dev/null; then
            echo "Testing Python LSP..."
            dotfiles-track-tool pylsp startup pylsp --version
          fi
        ''}
        
        echo "LSP monitoring completed"
      '')
      
      # Editor Performance Monitor
      (writeShellScriptBin "dotfiles-monitor-editors" ''
        #!/bin/bash
        
        # Monitor editor startup and operation performance
        
        echo "📝 Monitoring Editor Performance"
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorEditors ''
          # Neovim
          if command -v nvim >/dev/null; then
            echo "Testing Neovim startup..."
            dotfiles-track-tool nvim startup nvim --version
            
            # Test with a simple file operation
            echo "Testing Neovim file operation..."
            echo "test content" > /tmp/perf-test.txt
            dotfiles-track-tool nvim file-edit nvim -c "wq" /tmp/perf-test.txt
            rm -f /tmp/perf-test.txt
          fi
          
          # VSCode (if available)
          if command -v code >/dev/null; then
            echo "Testing VSCode startup..."
            dotfiles-track-tool vscode startup code --version
          fi
          
          # Zed (if available)  
          if command -v zed >/dev/null; then
            echo "Testing Zed startup..."
            dotfiles-track-tool zed startup zed --version
          fi
          
          # Vim (fallback)
          if command -v vim >/dev/null; then
            echo "Testing Vim startup..."
            dotfiles-track-tool vim startup vim --version
          fi
        ''}
        
        echo "Editor monitoring completed"
      '')
      
      # Compiler Performance Monitor
      (writeShellScriptBin "dotfiles-monitor-compilers" ''
        #!/bin/bash
        
        # Monitor compiler and build tool performance
        
        echo "🔨 Monitoring Compiler Performance"
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorCompilers ''
          # Create test files for compilation
          mkdir -p /tmp/dotfiles-perf-test
          cd /tmp/dotfiles-perf-test
          
          # Rust compiler
          if command -v rustc >/dev/null; then
            echo "Testing Rust compiler..."
            echo 'fn main() { println!("Hello, world!"); }' > hello.rs
            dotfiles-track-tool rustc compile rustc hello.rs
            rm -f hello.rs hello
          fi
          
          # Go compiler
          if command -v go >/dev/null; then
            echo "Testing Go compiler..."
            echo 'package main; import "fmt"; func main() { fmt.Println("Hello, world!") }' > hello.go
            dotfiles-track-tool go compile go build hello.go
            rm -f hello.go hello
          fi
          
          # TypeScript compiler
          if command -v tsc >/dev/null; then
            echo "Testing TypeScript compiler..."
            echo 'console.log("Hello, world!");' > hello.ts
            dotfiles-track-tool tsc compile tsc hello.ts
            rm -f hello.ts hello.js
          fi
          
          # Python (bytecode compilation)
          if command -v python3 >/dev/null; then
            echo "Testing Python compilation..."
            echo 'print("Hello, world!")' > hello.py
            dotfiles-track-tool python3 compile python3 -m py_compile hello.py
            rm -f hello.py __pycache__ -rf
          fi
          
          # Nix evaluation (as a "compiler")
          if command -v nix >/dev/null; then
            echo "Testing Nix evaluation..."
            dotfiles-track-tool nix eval nix eval --expr "1 + 1"
          fi
          
          cd - >/dev/null
          rm -rf /tmp/dotfiles-perf-test
        ''}
        
        echo "Compiler monitoring completed"
      '')
      
      # Git Operations Monitor
      (writeShellScriptBin "dotfiles-monitor-git" ''
        #!/bin/bash
        
        # Monitor Git operation performance
        
        echo "🔄 Monitoring Git Performance"
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorGitOps ''
          # Test in current directory if it's a git repo
          if [ -d ".git" ]; then
            echo "Testing Git operations in current repository..."
            
            # Git status
            dotfiles-track-tool git status git status
            
            # Git log (limited)
            dotfiles-track-tool git log git log --oneline -10
            
            # Git diff
            dotfiles-track-tool git diff git diff --cached
            
            # Git branch listing
            dotfiles-track-tool git branch git branch -l
            
          else
            echo "Not in a Git repository, creating test repo..."
            
            mkdir -p /tmp/git-perf-test
            cd /tmp/git-perf-test
            
            # Initialize repo
            dotfiles-track-tool git init git init
            
            # Create and add file
            echo "test content" > test.txt
            dotfiles-track-tool git add git add test.txt
            
            # Commit
            dotfiles-track-tool git commit git commit -m "Test commit"
            
            cd - >/dev/null
            rm -rf /tmp/git-perf-test
          fi
        ''}
        
        echo "Git monitoring completed"
      '')
      
      # Terminal Performance Monitor
      (writeShellScriptBin "dotfiles-monitor-terminal" ''
        #!/bin/bash
        
        # Monitor terminal and shell performance
        
        echo "💻 Monitoring Terminal Performance"
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorTerminal ''
          # Shell startup time
          if [ -n "$ZSH_VERSION" ]; then
            echo "Testing Zsh startup..."
            dotfiles-track-tool zsh startup zsh -c "exit"
          elif [ -n "$BASH_VERSION" ]; then
            echo "Testing Bash startup..."
            dotfiles-track-tool bash startup bash -c "exit"
          fi
          
          # Common shell commands
          dotfiles-track-tool shell ls ls -la > /dev/null
          dotfiles-track-tool shell find find /tmp -name "*.tmp" -type f 2>/dev/null
          dotfiles-track-tool shell grep grep "test" /dev/null 2>/dev/null || true
          
          # Starship prompt (if available)
          if command -v starship >/dev/null; then
            echo "Testing Starship prompt..."
            dotfiles-track-tool starship prompt starship prompt
          fi
        ''}
        
        echo "Terminal monitoring completed"
      '')
      
      # Comprehensive tool benchmark
      (writeShellScriptBin "dotfiles-benchmark-tools" ''
        #!/bin/bash
        
        # Run comprehensive tool performance benchmark
        
        echo "🚀 Running Comprehensive Tool Performance Benchmark"
        echo "================================================="
        
        # Run all monitoring scripts
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorLSP ''
          echo "1/5 - LSP Performance..."
          dotfiles-monitor-lsp
        ''}
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorEditors ''
          echo "2/5 - Editor Performance..."
          dotfiles-monitor-editors
        ''}
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorCompilers ''
          echo "3/5 - Compiler Performance..."
          dotfiles-monitor-compilers
        ''}
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorGitOps ''
          echo "4/5 - Git Performance..."
          dotfiles-monitor-git
        ''}
        
        ${optionalString config.dotfiles.performance.monitoring.toolPerformance.monitorTerminal ''
          echo "5/5 - Terminal Performance..."
          dotfiles-monitor-terminal
        ''}
        
        echo
        echo "✅ Benchmark completed!"
        echo "Run 'just perf-tools' to view results"
      '')
      
      # Tool performance analysis
      (writeShellScriptBin "dotfiles-analyze-tools" ''
        #!/bin/bash
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        DAYS="''${2:-7}"
        
        if [ ! -f "$METRICS_DB" ]; then
          echo "Metrics database not found"
          exit 1
        fi
        
        CUTOFF_TIME=$(($(date +%s) - (DAYS * 24 * 3600)))
        
        echo "=== Tool Performance Analysis (Last $DAYS days) ==="
        echo
        
        # Average performance by tool
        echo "=== Average Performance by Tool ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          .mode column
          .headers on
          .width 15 12 8 8 8 8
          
          SELECT 
            tool_name as "Tool",
            operation as "Operation",
            COUNT(*) as "Runs",
            printf("%.0f", AVG(duration_ms)) as "Avg (ms)",
            printf("%.0f", MIN(duration_ms)) as "Min (ms)",
            printf("%.0f", MAX(duration_ms)) as "Max (ms)"
          FROM tool_performance 
          WHERE timestamp > $CUTOFF_TIME
          GROUP BY tool_name, operation
          ORDER BY AVG(duration_ms) DESC;
EOF
        
        echo
        echo "=== Slowest Tool Operations ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          SELECT 
            datetime(timestamp, 'unixepoch', 'localtime') as "Time",
            tool_name as "Tool",
            operation as "Operation",
            printf("%.0f", duration_ms) as "Duration (ms)",
            CASE success WHEN 1 THEN "✓" ELSE "✗" END as "Success"
          FROM tool_performance 
          WHERE timestamp > $CUTOFF_TIME
          ORDER BY duration_ms DESC
          LIMIT 15;
EOF
        
        echo
        echo "=== Tool Success Rates ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          SELECT 
            tool_name as "Tool",
            COUNT(*) as "Total Runs",
            SUM(success) as "Successful",
            printf("%.1f%%", (SUM(success) * 100.0 / COUNT(*))) as "Success Rate"
          FROM tool_performance 
          WHERE timestamp > $CUTOFF_TIME
          GROUP BY tool_name
          ORDER BY (SUM(success) * 100.0 / COUNT(*)) ASC;
EOF
      '')
    ] ++ (
      # Enable additional packages for detailed profiling
      lib.optionals config.dotfiles.performance.monitoring.toolPerformance.detailedProfiling (with pkgs; [
      # Memory profiling tools
      valgrind
      
      # CPU profiling tools (platform-specific)
    ] ++ lib.optionals (platformInfo.isDarwin or false) [
      # macOS profiling tools
    ] ++ lib.optionals (!(platformInfo.isDarwin or false)) [
      # Linux profiling tools
      perf-tools
    ]));
  };
}