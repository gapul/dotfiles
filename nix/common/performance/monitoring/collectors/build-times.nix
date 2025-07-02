# Build Time Tracking Collector
# Monitors Nix build operations, home-manager switches, and package builds
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.performance.monitoring.buildTimes = {
    enable = mkEnableOption "Build time tracking and monitoring";
    
    trackNixOperations = mkOption {
      type = types.bool;
      default = true;
      description = "Track nix-darwin and home-manager operations";
    };
    
    trackPackageBuilds = mkOption {
      type = types.bool;
      default = true;
      description = "Track individual package build times";
    };
    
    trackEvaluationTime = mkOption {
      type = types.bool;
      default = true;
      description = "Track Nix evaluation time";
    };
    
    alertSlowBuilds = mkOption {
      type = types.bool;
      default = true;
      description = "Alert when builds take significantly longer than baseline";
    };
  };

  config = mkIf (config.dotfiles.performance.enable && config.dotfiles.performance.monitoring.buildTimes.enable) {
    # Build time tracking wrapper scripts
    environment.systemPackages = with pkgs; [
      # Nix operation wrapper
      (writeShellScriptBin "nix-timed" ''
        #!/bin/bash
        
        # Timed wrapper for nix operations
        # Usage: nix-timed <operation> [args...]
        
        set -euo pipefail
        
        OPERATION="$1"
        shift
        
        METRICS_DB="/var/lib/dotfiles-performance/metrics/performance.db"
        USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
        
        mkdir -p "$USER_METRICS_DIR"
        
        START_TIME=$(date +%s)
        START_TIME_MS=$(date +%s%3N)
        
        echo "Starting $OPERATION at $(date)"
        echo "Command: nix $OPERATION $*"
        
        # Execute the actual nix command and capture result
        set +e
        nix "$OPERATION" "$@"
        RESULT=$?
        set -e
        
        END_TIME=$(date +%s)
        END_TIME_MS=$(date +%s%3N)
        DURATION=$((END_TIME - START_TIME))
        DURATION_MS=$((END_TIME_MS - START_TIME_MS))
        
        echo "Completed $OPERATION in $DURATION seconds"
        
        # Count packages built (approximate from output)
        PACKAGES_BUILT=0
        
        # Calculate success
        SUCCESS=$([ $RESULT -eq 0 ] && echo "1" || echo "0")
        
        # Store in database
        ${optionalString config.dotfiles.performance.monitoring.buildTimes.trackNixOperations ''
          if [ -f "$METRICS_DB" ]; then
            ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
              INSERT INTO build_metrics (
                timestamp, operation_type, duration_seconds, success, packages_built, cache_hit_ratio
              ) VALUES (
                $START_TIME, 'nix-$OPERATION', $DURATION, $SUCCESS, $PACKAGES_BUILT, 0.0
              );
EOF
          fi
        ''}
        
        # Log to file
        echo "$(date): $OPERATION completed in $DURATION seconds (success: $SUCCESS)" >> "$USER_METRICS_DIR/build-times.log"
        
        # Check for slow builds and alert
        ${optionalString config.dotfiles.performance.monitoring.buildTimes.alertSlowBuilds ''
          # Get baseline duration for this operation
          if [ -f "$METRICS_DB" ]; then
            BASELINE=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT AVG(duration_seconds) FROM build_metrics WHERE operation_type = 'nix-$OPERATION' AND success = 1 AND timestamp > $(date -d '7 days ago' +%s)" 2>/dev/null || echo "0")
            
            if [ "$BASELINE" != "0" ] && [ $(echo "$DURATION > $BASELINE * 1.5" | ${bc}/bin/bc -l) -eq 1 ]; then
              ALERT_MSG="Slow build detected: $OPERATION took $DURATION seconds (baseline: $BASELINE seconds)"
              echo "ALERT: $ALERT_MSG" >> "$USER_METRICS_DIR/alerts.log"
              
              # Send desktop notification on macOS
              if command -v osascript >/dev/null; then
                osascript -e "display notification \"$ALERT_MSG\" with title \"Build Performance Alert\""
              fi
            fi
          fi
        ''}
        
        exit $RESULT
      '')
      
      # Home-manager wrapper
      (writeShellScriptBin "home-manager-timed" ''
        #!/bin/bash
        
        # Timed wrapper for home-manager operations
        
        set -euo pipefail
        
        OPERATION="$1"
        shift
        
        METRICS_DB="/var/lib/dotfiles-performance/metrics/performance.db"
        USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
        
        START_TIME=$(date +%s)
        
        echo "Starting home-manager $OPERATION at $(date)"
        
        # Execute home-manager command
        set +e
        home-manager "$OPERATION" "$@"
        RESULT=$?
        set -e
        
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        
        SUCCESS=$([ $RESULT -eq 0 ] && echo "1" || echo "0")
        
        echo "Completed home-manager $OPERATION in $DURATION seconds"
        
        # Store metrics
        ${optionalString config.dotfiles.performance.monitoring.buildTimes.trackNixOperations ''
          if [ -f "$METRICS_DB" ]; then
            ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
              INSERT INTO build_metrics (
                timestamp, operation_type, duration_seconds, success, packages_built
              ) VALUES (
                $START_TIME, 'home-manager-$OPERATION', $DURATION, $SUCCESS, 0
              );
EOF
          fi
        ''}
        
        echo "$(date): home-manager $OPERATION completed in $DURATION seconds" >> "$USER_METRICS_DIR/build-times.log"
        
        exit $RESULT
      '')
      
      # Build time analysis script
      (writeShellScriptBin "dotfiles-build-analysis" ''
        #!/bin/bash
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        DAYS="''${2:-7}"
        
        if [ ! -f "$METRICS_DB" ]; then
          echo "Metrics database not found"
          exit 1
        fi
        
        CUTOFF_TIME=$(($(date +%s) - (DAYS * 24 * 3600)))
        
        echo "=== Build Performance Analysis (Last $DAYS days) ==="
        echo
        
        # Build success rate
        echo "=== Build Success Rate ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          .mode column
          .headers on
          
          SELECT 
            operation_type as "Operation",
            COUNT(*) as "Total",
            SUM(success) as "Successful", 
            printf("%.1f%%", (SUM(success) * 100.0 / COUNT(*))) as "Success Rate"
          FROM build_metrics 
          WHERE timestamp > $CUTOFF_TIME
          GROUP BY operation_type
          ORDER BY operation_type;
EOF
        
        echo
        echo "=== Average Build Times ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          SELECT 
            operation_type as "Operation",
            printf("%.1f", AVG(duration_seconds)) as "Avg Time (s)",
            printf("%.1f", MIN(duration_seconds)) as "Min Time (s)",
            printf("%.1f", MAX(duration_seconds)) as "Max Time (s)"
          FROM build_metrics 
          WHERE timestamp > $CUTOFF_TIME AND success = 1
          GROUP BY operation_type
          ORDER BY AVG(duration_seconds) DESC;
EOF
        
        echo
        echo "=== Recent Slow Builds ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          SELECT 
            datetime(timestamp, 'unixepoch', 'localtime') as "Time",
            operation_type as "Operation",
            printf("%.1f", duration_seconds) as "Duration (s)",
            CASE success WHEN 1 THEN "✓" ELSE "✗" END as "Success"
          FROM build_metrics 
          WHERE timestamp > $CUTOFF_TIME AND duration_seconds > 60
          ORDER BY duration_seconds DESC
          LIMIT 10;
EOF
        
        echo
        echo "=== Build Trends ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          SELECT 
            date(timestamp, 'unixepoch', 'localtime') as "Date",
            COUNT(*) as "Builds",
            printf("%.1f", AVG(duration_seconds)) as "Avg Duration (s)"
          FROM build_metrics 
          WHERE timestamp > $CUTOFF_TIME AND success = 1
          GROUP BY date(timestamp, 'unixepoch', 'localtime')
          ORDER BY Date DESC;
EOF
      '')
      
      # Performance baseline establishment script
      (writeShellScriptBin "dotfiles-establish-baseline" ''
        #!/bin/bash
        
        # Establish performance baselines for comparison
        
        echo "Establishing performance baselines..."
        
        METRICS_DB="/var/lib/dotfiles-performance/metrics/performance.db"
        USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
        
        mkdir -p "$USER_METRICS_DIR"
        
        # Test basic Nix evaluation
        echo "Testing Nix evaluation performance..."
        time nix eval .#platformInfo > /dev/null 2>&1 || true
        
        # Test flake check
        echo "Testing flake check performance..."
        time nix flake check --impure > /dev/null 2>&1 || true
        
        # Test home-manager build
        echo "Testing home-manager build performance..."
        time home-manager build --flake .#yuki@darwin > /dev/null 2>&1 || true
        
        echo "Baseline establishment completed"
        echo "Run 'dotfiles-build-analysis' to view performance metrics"
      '')
    ] ++ [
      # Just integration for timed operations
      (writeShellScriptBin "just-timed" ''
        #!/bin/bash
        
        # Wrapper for just commands with timing
        OPERATION="$1"
        shift
        
        START_TIME=$(date +%s)
        echo "Starting: just $OPERATION $*"
        
        just "$OPERATION" "$@"
        RESULT=$?
        
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        
        echo "Completed 'just $OPERATION' in $DURATION seconds"
        
        # Log to build metrics
        USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
        echo "$(date): just $OPERATION completed in $DURATION seconds" >> "$USER_METRICS_DIR/build-times.log"
        
        exit $RESULT
      '')
    ];
    
    # Create performance aliases for common operations
    environment.shellAliases = mkIf config.dotfiles.performance.monitoring.buildTimes.trackNixOperations {
      "nix-rebuild" = "nix-timed run nix-darwin -- switch --flake .";
      "hm-switch" = "home-manager-timed switch --flake .";
      "dotfiles-rebuild" = "nix-timed run nix-darwin -- switch --flake . --impure";
    };
  };
}