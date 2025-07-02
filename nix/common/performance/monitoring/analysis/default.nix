# Data Analysis and Trend Detection System
# Advanced analytics for performance data with predictive insights
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.performance.monitoring.analysis = {
    enable = mkEnableOption "Performance data analysis and trend detection";
    
    enableTrendAnalysis = mkOption {
      type = types.bool;
      default = true;
      description = "Enable trend analysis and prediction";
    };
    
    enableAnomalyDetection = mkOption {
      type = types.bool;
      default = true;
      description = "Enable anomaly detection in performance metrics";
    };
    
    enablePredictiveAnalysis = mkOption {
      type = types.bool;
      default = false;
      description = "Enable predictive performance analysis";
    };
    
    reportingInterval = mkOption {
      type = types.enum [ "daily" "weekly" "monthly" ];
      default = "weekly";
      description = "Automatic performance report generation interval";
    };
    
    alertThresholds = {
      cpuUsageHigh = mkOption {
        type = types.int;
        default = 80;
        description = "CPU usage percentage threshold for alerts";
      };
      
      memoryUsageHigh = mkOption {
        type = types.int;
        default = 85;
        description = "Memory usage percentage threshold for alerts";
      };
      
      buildTimeIncrease = mkOption {
        type = types.float;
        default = 1.5;
        description = "Build time increase multiplier for alerts";
      };
    };
  };

  config = mkIf (config.dotfiles.performance.enable && config.dotfiles.performance.monitoring.analysis.enable) {
    # Advanced analysis scripts
    environment.systemPackages = with pkgs; [
      # Performance trend analyzer
      (writeShellScriptBin "dotfiles-analyze-trends" ''
        #!/bin/bash
        
        # Comprehensive performance trend analysis
        
        set -euo pipefail
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        PERIOD_DAYS="''${2:-30}"
        OUTPUT_DIR="''${3:-/Users/yuki/.local/share/dotfiles-performance/reports}"
        
        if [ ! -f "$METRICS_DB" ]; then
          echo "Metrics database not found at $METRICS_DB"
          exit 1
        fi
        
        mkdir -p "$OUTPUT_DIR"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        REPORT_FILE="$OUTPUT_DIR/trend_analysis_$TIMESTAMP.md"
        
        echo "Generating performance trend analysis for last $PERIOD_DAYS days..."
        
        CUTOFF_TIME=$(($(date +%s) - (PERIOD_DAYS * 24 * 3600)))
        
        {
          echo "# Performance Trend Analysis Report"
          echo "Generated: $(date)"
          echo "Analysis Period: Last $PERIOD_DAYS days"
          echo ""
          
          echo "## Executive Summary"
          echo ""
          
          # System performance summary
          echo "### System Performance Trends"
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            SELECT 
              printf("- Average CPU Usage: %.1f%% (Range: %.1f%% - %.1f%%)", 
                AVG(cpu_usage_percent), MIN(cpu_usage_percent), MAX(cpu_usage_percent)),
              printf("- Average Memory Usage: %.1f%% (Range: %.1f%% - %.1f%%)",
                AVG(memory_usage_percent), MIN(memory_usage_percent), MAX(memory_usage_percent)),
              printf("- Average Load: %.2f (Range: %.2f - %.2f)",
                AVG(load_average_1m), MIN(load_average_1m), MAX(load_average_1m))
            FROM system_metrics 
            WHERE timestamp > $CUTOFF_TIME;
EOF
          
          echo ""
          echo "### Build Performance Summary"
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            SELECT 
              printf("- Total Builds: %d", COUNT(*)),
              printf("- Success Rate: %.1f%%", (SUM(success) * 100.0 / COUNT(*))),
              printf("- Average Build Time: %.1f seconds", AVG(duration_seconds))
            FROM build_metrics 
            WHERE timestamp > $CUTOFF_TIME;
EOF
          
          echo ""
          echo "## Detailed Analysis"
          echo ""
          
          echo "### CPU Usage Trends"
          echo ""
          echo "\`\`\`"
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            .mode column
            .headers on
            .width 12 8 8 8 8
            
            SELECT 
              date(timestamp, 'unixepoch', 'localtime') as "Date",
              printf("%.1f", AVG(cpu_usage_percent)) as "Avg CPU",
              printf("%.1f", MIN(cpu_usage_percent)) as "Min CPU",
              printf("%.1f", MAX(cpu_usage_percent)) as "Max CPU",
              COUNT(*) as "Samples"
            FROM system_metrics 
            WHERE timestamp > $CUTOFF_TIME
            GROUP BY date(timestamp, 'unixepoch', 'localtime')
            ORDER BY Date DESC
            LIMIT 10;
EOF
          echo "\`\`\`"
          echo ""
          
          echo "### Memory Usage Patterns"
          echo ""
          echo "\`\`\`"
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            SELECT 
              date(timestamp, 'unixepoch', 'localtime') as "Date",
              printf("%.1f", AVG(memory_usage_percent)) as "Avg Memory",
              printf("%.1f", MIN(memory_usage_percent)) as "Min Memory", 
              printf("%.1f", MAX(memory_usage_percent)) as "Max Memory",
              COUNT(*) as "Samples"
            FROM system_metrics 
            WHERE timestamp > $CUTOFF_TIME
            GROUP BY date(timestamp, 'unixepoch', 'localtime')
            ORDER BY Date DESC
            LIMIT 10;
EOF
          echo "\`\`\`"
          echo ""
          
          echo "### Build Time Evolution"
          echo ""
          echo "\`\`\`"
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            SELECT 
              date(timestamp, 'unixepoch', 'localtime') as "Date",
              operation_type as "Operation",
              printf("%.1f", AVG(duration_seconds)) as "Avg Time",
              COUNT(*) as "Builds"
            FROM build_metrics 
            WHERE timestamp > $CUTOFF_TIME AND success = 1
            GROUP BY date(timestamp, 'unixepoch', 'localtime'), operation_type
            ORDER BY Date DESC, operation_type
            LIMIT 20;
EOF
          echo "\`\`\`"
          echo ""
          
          echo "### Performance Anomalies Detected"
          echo ""
          
          # Detect CPU spikes
          CPU_THRESHOLD=${toString config.dotfiles.performance.monitoring.analysis.alertThresholds.cpuUsageHigh}
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            SELECT 
              datetime(timestamp, 'unixepoch', 'localtime') as "Time",
              printf("%.1f%%", cpu_usage_percent) as "CPU Usage"
            FROM system_metrics 
            WHERE timestamp > $CUTOFF_TIME AND cpu_usage_percent > $CPU_THRESHOLD
            ORDER BY cpu_usage_percent DESC
            LIMIT 5;
EOF
          
          echo ""
          echo "### Tool Performance Insights"
          echo ""
          echo "\`\`\`"
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            SELECT 
              tool_name as "Tool",
              operation as "Operation",
              COUNT(*) as "Usage Count",
              printf("%.0f", AVG(duration_ms)) as "Avg Time (ms)",
              printf("%.1f%%", (SUM(success) * 100.0 / COUNT(*))) as "Success Rate"
            FROM tool_performance 
            WHERE timestamp > $CUTOFF_TIME
            GROUP BY tool_name, operation
            ORDER BY COUNT(*) DESC
            LIMIT 15;
EOF
          echo "\`\`\`"
          echo ""
          
          echo "## Recommendations"
          echo ""
          
          # Generate recommendations based on data
          echo "### Performance Optimization Suggestions"
          echo ""
          
          # Check for slow builds
          SLOW_BUILDS=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM build_metrics WHERE timestamp > $CUTOFF_TIME AND duration_seconds > 300 AND success = 1")
          if [ "$SLOW_BUILDS" -gt 0 ]; then
            echo "- Consider optimizing build process - $SLOW_BUILDS builds took longer than 5 minutes"
          fi
          
          # Check for high resource usage
          HIGH_CPU_PERIODS=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM system_metrics WHERE timestamp > $CUTOFF_TIME AND cpu_usage_percent > $CPU_THRESHOLD")
          if [ "$HIGH_CPU_PERIODS" -gt 0 ]; then
            echo "- CPU usage was high during $HIGH_CPU_PERIODS measurement periods - consider monitoring background processes"
          fi
          
          # Check tool performance
          FAILED_TOOLS=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM tool_performance WHERE timestamp > $CUTOFF_TIME AND success = 0")
          if [ "$FAILED_TOOLS" -gt 0 ]; then
            echo "- $FAILED_TOOLS tool operations failed - investigate tool configuration"
          fi
          
          echo ""
          echo "### System Health Score"
          
          # Calculate overall health score
          CPU_SCORE=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT CASE WHEN AVG(cpu_usage_percent) < 50 THEN 100 WHEN AVG(cpu_usage_percent) < 70 THEN 80 WHEN AVG(cpu_usage_percent) < 85 THEN 60 ELSE 40 END FROM system_metrics WHERE timestamp > $CUTOFF_TIME")
          MEMORY_SCORE=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT CASE WHEN AVG(memory_usage_percent) < 60 THEN 100 WHEN AVG(memory_usage_percent) < 75 THEN 80 WHEN AVG(memory_usage_percent) < 90 THEN 60 ELSE 40 END FROM system_metrics WHERE timestamp > $CUTOFF_TIME")
          BUILD_SCORE=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT CASE WHEN (SUM(success) * 100.0 / COUNT(*)) > 95 THEN 100 WHEN (SUM(success) * 100.0 / COUNT(*)) > 90 THEN 80 WHEN (SUM(success) * 100.0 / COUNT(*)) > 80 THEN 60 ELSE 40 END FROM build_metrics WHERE timestamp > $CUTOFF_TIME")
          
          OVERALL_SCORE=$(echo "scale=0; ($CPU_SCORE + $MEMORY_SCORE + $BUILD_SCORE) / 3" | ${bc}/bin/bc)
          
          echo ""
          echo "**Overall System Health Score: $OVERALL_SCORE/100**"
          echo ""
          echo "- CPU Performance: $CPU_SCORE/100"
          echo "- Memory Management: $MEMORY_SCORE/100" 
          echo "- Build Reliability: $BUILD_SCORE/100"
          echo ""
          
          echo "---"
          echo "*Report generated by dotfiles performance monitoring system*"
          
        } > "$REPORT_FILE"
        
        echo "Trend analysis completed: $REPORT_FILE"
        
        # Display summary
        echo ""
        echo "=== Quick Summary ==="
        tail -10 "$REPORT_FILE"
      '')
      
      # Anomaly detection script
      (writeShellScriptBin "dotfiles-detect-anomalies" ''
        #!/bin/bash
        
        # Anomaly detection in performance metrics
        
        set -euo pipefail
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        DAYS="''${2:-7}"
        
        if [ ! -f "$METRICS_DB" ]; then
          echo "Metrics database not found"
          exit 1
        fi
        
        echo "🔍 Detecting Performance Anomalies (Last $DAYS days)"
        echo "================================================="
        echo ""
        
        CUTOFF_TIME=$(($(date +%s) - (DAYS * 24 * 3600)))
        
        # CPU Usage Anomalies
        echo "### CPU Usage Anomalies"
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          .mode column
          .headers on
          
          WITH cpu_stats AS (
            SELECT AVG(cpu_usage_percent) as avg_cpu, 
                   (AVG(cpu_usage_percent * cpu_usage_percent) - AVG(cpu_usage_percent) * AVG(cpu_usage_percent)) as variance
            FROM system_metrics 
            WHERE timestamp > $CUTOFF_TIME
          )
          SELECT 
            datetime(timestamp, 'unixepoch', 'localtime') as "Time",
            printf("%.1f%%", cpu_usage_percent) as "CPU Usage",
            printf("%.1f", (cpu_usage_percent - avg_cpu) / SQRT(variance)) as "Z-Score"
          FROM system_metrics, cpu_stats
          WHERE timestamp > $CUTOFF_TIME 
            AND ABS(cpu_usage_percent - avg_cpu) > (2 * SQRT(variance))
          ORDER BY ABS(cpu_usage_percent - avg_cpu) DESC
          LIMIT 10;
EOF
        
        echo ""
        echo "### Memory Usage Anomalies"
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          WITH memory_stats AS (
            SELECT AVG(memory_usage_percent) as avg_memory,
                   (AVG(memory_usage_percent * memory_usage_percent) - AVG(memory_usage_percent) * AVG(memory_usage_percent)) as variance
            FROM system_metrics 
            WHERE timestamp > $CUTOFF_TIME
          )
          SELECT 
            datetime(timestamp, 'unixepoch', 'localtime') as "Time",
            printf("%.1f%%", memory_usage_percent) as "Memory Usage",
            printf("%.1f", (memory_usage_percent - avg_memory) / SQRT(variance)) as "Z-Score"
          FROM system_metrics, memory_stats
          WHERE timestamp > $CUTOFF_TIME 
            AND ABS(memory_usage_percent - avg_memory) > (2 * SQRT(variance))
          ORDER BY ABS(memory_usage_percent - avg_memory) DESC
          LIMIT 10;
EOF
        
        echo ""
        echo "### Build Time Anomalies"
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          WITH build_stats AS (
            SELECT operation_type,
                   AVG(duration_seconds) as avg_duration,
                   (AVG(duration_seconds * duration_seconds) - AVG(duration_seconds) * AVG(duration_seconds)) as variance
            FROM build_metrics 
            WHERE timestamp > $CUTOFF_TIME AND success = 1
            GROUP BY operation_type
          )
          SELECT 
            datetime(b.timestamp, 'unixepoch', 'localtime') as "Time",
            b.operation_type as "Operation",
            printf("%.1f", b.duration_seconds) as "Duration (s)",
            printf("%.1f", (b.duration_seconds - s.avg_duration) / SQRT(s.variance)) as "Z-Score"
          FROM build_metrics b
          JOIN build_stats s ON b.operation_type = s.operation_type
          WHERE b.timestamp > $CUTOFF_TIME 
            AND b.success = 1
            AND ABS(b.duration_seconds - s.avg_duration) > (2 * SQRT(s.variance))
          ORDER BY ABS(b.duration_seconds - s.avg_duration) DESC
          LIMIT 10;
EOF
        
        echo ""
        echo "### Tool Performance Anomalies"
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          WITH tool_stats AS (
            SELECT tool_name, operation,
                   AVG(duration_ms) as avg_duration,
                   (AVG(duration_ms * duration_ms) - AVG(duration_ms) * AVG(duration_ms)) as variance
            FROM tool_performance 
            WHERE timestamp > $CUTOFF_TIME AND success = 1
            GROUP BY tool_name, operation
            HAVING COUNT(*) > 5
          )
          SELECT 
            datetime(t.timestamp, 'unixepoch', 'localtime') as "Time",
            t.tool_name as "Tool",
            t.operation as "Operation",
            printf("%.0f", t.duration_ms) as "Duration (ms)",
            printf("%.1f", (t.duration_ms - s.avg_duration) / SQRT(s.variance)) as "Z-Score"
          FROM tool_performance t
          JOIN tool_stats s ON t.tool_name = s.tool_name AND t.operation = s.operation
          WHERE t.timestamp > $CUTOFF_TIME 
            AND t.success = 1
            AND ABS(t.duration_ms - s.avg_duration) > (2 * SQRT(s.variance))
          ORDER BY ABS(t.duration_ms - s.avg_duration) DESC
          LIMIT 10;
EOF
        
        echo ""
        echo "Anomaly detection completed"
      '')
      
      # Performance alerting system
      (writeShellScriptBin "dotfiles-check-alerts" ''
        #!/bin/bash
        
        # Real-time performance alerting
        
        set -euo pipefail
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        ALERT_LOG="/Users/yuki/.local/share/dotfiles-performance/logs/alerts.log"
        
        mkdir -p "$(dirname "$ALERT_LOG")"
        
        if [ ! -f "$METRICS_DB" ]; then
          echo "Metrics database not found"
          exit 1
        fi
        
        # Check recent metrics (last 5 minutes)
        RECENT_TIME=$(($(date +%s) - 300))
        CURRENT_TIME=$(date +%s)
        
        # CPU usage alert
        CPU_THRESHOLD=${toString config.dotfiles.performance.monitoring.analysis.alertThresholds.cpuUsageHigh}
        HIGH_CPU=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM system_metrics WHERE timestamp > $RECENT_TIME AND cpu_usage_percent > $CPU_THRESHOLD")
        
        if [ "$HIGH_CPU" -gt 0 ]; then
          ALERT_MSG="HIGH CPU USAGE: CPU usage exceeded $CPU_THRESHOLD% threshold"
          echo "$(date): $ALERT_MSG" >> "$ALERT_LOG"
          
          # Store alert in database
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            INSERT INTO performance_alerts (
              timestamp, alert_type, severity, metric_name, current_value, threshold_value, message
            ) VALUES (
              $CURRENT_TIME, 'system', 'high', 'cpu_usage', 
              (SELECT MAX(cpu_usage_percent) FROM system_metrics WHERE timestamp > $RECENT_TIME),
              $CPU_THRESHOLD, '$ALERT_MSG'
            );
EOF
          
          echo "$ALERT_MSG"
        fi
        
        # Memory usage alert
        MEMORY_THRESHOLD=${toString config.dotfiles.performance.monitoring.analysis.alertThresholds.memoryUsageHigh}
        HIGH_MEMORY=$(${sqlite}/bin/sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM system_metrics WHERE timestamp > $RECENT_TIME AND memory_usage_percent > $MEMORY_THRESHOLD")
        
        if [ "$HIGH_MEMORY" -gt 0 ]; then
          ALERT_MSG="HIGH MEMORY USAGE: Memory usage exceeded $MEMORY_THRESHOLD% threshold"
          echo "$(date): $ALERT_MSG" >> "$ALERT_LOG"
          
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            INSERT INTO performance_alerts (
              timestamp, alert_type, severity, metric_name, current_value, threshold_value, message
            ) VALUES (
              $CURRENT_TIME, 'system', 'high', 'memory_usage',
              (SELECT MAX(memory_usage_percent) FROM system_metrics WHERE timestamp > $RECENT_TIME),
              $MEMORY_THRESHOLD, '$ALERT_MSG'
            );
EOF
          
          echo "$ALERT_MSG"
        fi
        
        # Build time alerts (last 24 hours)
        BUILD_TIME_MULTIPLIER=${toString config.dotfiles.performance.monitoring.analysis.alertThresholds.buildTimeIncrease}
        RECENT_24H=$(($(date +%s) - 86400))
        
        # Get recent slow builds
        SLOW_BUILDS=$(${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          WITH baselines AS (
            SELECT operation_type, AVG(duration_seconds) as baseline
            FROM build_metrics 
            WHERE timestamp > $RECENT_24H AND success = 1
            GROUP BY operation_type
          )
          SELECT COUNT(*)
          FROM build_metrics b
          JOIN baselines bl ON b.operation_type = bl.operation_type
          WHERE b.timestamp > $RECENT_TIME 
            AND b.success = 1
            AND b.duration_seconds > (bl.baseline * $BUILD_TIME_MULTIPLIER);
EOF
        )
        
        if [ "$SLOW_BUILDS" -gt 0 ]; then
          ALERT_MSG="SLOW BUILD DETECTED: $SLOW_BUILDS builds exceeded baseline by ${BUILD_TIME_MULTIPLIER}x"
          echo "$(date): $ALERT_MSG" >> "$ALERT_LOG"
          
          ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
            INSERT INTO performance_alerts (
              timestamp, alert_type, severity, metric_name, current_value, threshold_value, message
            ) VALUES (
              $CURRENT_TIME, 'build', 'medium', 'build_duration', $SLOW_BUILDS, $BUILD_TIME_MULTIPLIER, '$ALERT_MSG'
            );
EOF
          
          echo "$ALERT_MSG"
        fi
        
        # Show recent unacknowledged alerts
        echo ""
        echo "=== Recent Unacknowledged Alerts ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          .mode column
          .headers on
          
          SELECT 
            datetime(timestamp, 'unixepoch', 'localtime') as "Time",
            alert_type as "Type",
            severity as "Severity", 
            message as "Message"
          FROM performance_alerts 
          WHERE acknowledged = 0 AND timestamp > $RECENT_24H
          ORDER BY timestamp DESC
          LIMIT 10;
EOF
      '')
      
      # Performance report generator
      (writeShellScriptBin "dotfiles-generate-report" ''
        #!/bin/bash
        
        # Generate comprehensive performance report
        
        set -euo pipefail
        
        REPORT_TYPE="''${1:-weekly}"
        OUTPUT_DIR="''${2:-/Users/yuki/.local/share/dotfiles-performance/reports}"
        
        mkdir -p "$OUTPUT_DIR"
        
        case "$REPORT_TYPE" in
          daily)
            DAYS=1
            ;;
          weekly)
            DAYS=7
            ;;
          monthly)
            DAYS=30
            ;;
          *)
            echo "Invalid report type. Use: daily, weekly, monthly"
            exit 1
            ;;
        esac
        
        echo "Generating $REPORT_TYPE performance report..."
        
        # Run comprehensive analysis
        dotfiles-analyze-trends /var/lib/dotfiles-performance/metrics/performance.db $DAYS "$OUTPUT_DIR"
        
        # Run anomaly detection
        echo "" 
        echo "Running anomaly detection..."
        dotfiles-detect-anomalies /var/lib/dotfiles-performance/metrics/performance.db $DAYS > "$OUTPUT_DIR/anomalies_$(date +%Y%m%d).txt"
        
        # Check for alerts
        echo ""
        echo "Checking for performance alerts..."
        dotfiles-check-alerts > "$OUTPUT_DIR/alerts_$(date +%Y%m%d).txt"
        
        echo ""
        echo "Report generation completed!"
        echo "Reports saved to: $OUTPUT_DIR"
        ls -la "$OUTPUT_DIR"/*$(date +%Y%m%d)*
      '')
    ];
    
    # Automated report generation
    launchd.user.agents.dotfiles-performance-reports = mkIf (platformInfo.isDarwin or false) {
      serviceConfig = {
        Label = "org.dotfiles.performance-reports";
        ProgramArguments = [
          "${pkgs.writeShellScript "performance-reports" ''
            #!/bin/bash
            dotfiles-generate-report ${config.dotfiles.performance.monitoring.analysis.reportingInterval}
          ''}"
        ];
        StartCalendarInterval = {
          Weekday = 1;  # Monday
          Hour = 9;
          Minute = 0;
        };
        StandardErrorPath = "/Users/yuki/.local/share/dotfiles-performance/logs/reports-error.log";
        StandardOutPath = "/Users/yuki/.local/share/dotfiles-performance/logs/reports-output.log";
      };
    };
  };
}