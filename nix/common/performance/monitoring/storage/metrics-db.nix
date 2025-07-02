# Metrics Database Management
# SQLite database setup, maintenance, and optimization for performance metrics
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.performance.monitoring.storage = {
    databasePath = mkOption {
      type = types.str;
      default = "/var/lib/dotfiles-performance/metrics/performance.db";
      description = "Path to the performance metrics database";
    };
    
    userDatabasePath = mkOption {
      type = types.str;
      default = "/Users/yuki/.local/share/dotfiles-performance/metrics/performance.db";
      description = "User-specific database path";
    };
    
    enableWAL = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Write-Ahead Logging for better performance";
    };
    
    autoVacuum = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic database maintenance";
    };
    
    compressionEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable data compression for older records";
    };
  };

  config = mkIf config.dotfiles.performance.enable {
    # Database management scripts
    environment.systemPackages = with pkgs; [
      # Database initialization and setup
      (writeShellScriptBin "dotfiles-init-database" ''
        #!/bin/bash
        
        # Initialize performance monitoring database
        
        set -euo pipefail
        
        DB_PATH="''${1:-${config.dotfiles.performance.monitoring.storage.databasePath}}"
        USER_DB_PATH="${config.dotfiles.performance.monitoring.storage.userDatabasePath}"
        
        echo "Initializing performance database at $DB_PATH"
        
        # Create directory structure
        mkdir -p "$(dirname "$DB_PATH")"
        mkdir -p "$(dirname "$USER_DB_PATH")"
        
        # Initialize system database
        ${sqlite}/bin/sqlite3 "$DB_PATH" << 'EOF'
          -- System metrics table
          CREATE TABLE IF NOT EXISTS system_metrics (
            timestamp INTEGER PRIMARY KEY,
            cpu_usage_percent REAL NOT NULL,
            memory_usage_percent REAL NOT NULL,
            disk_usage_percent REAL NOT NULL,
            load_average_1m REAL NOT NULL,
            load_average_5m REAL NOT NULL,
            load_average_15m REAL NOT NULL,
            disk_read_mb_per_sec REAL DEFAULT 0,
            disk_write_mb_per_sec REAL DEFAULT 0,
            network_rx_mb_per_sec REAL DEFAULT 0,
            network_tx_mb_per_sec REAL DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          );
          
          -- Build metrics table
          CREATE TABLE IF NOT EXISTS build_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            operation_type TEXT NOT NULL,
            duration_seconds REAL NOT NULL,
            success BOOLEAN NOT NULL DEFAULT 0,
            packages_built INTEGER DEFAULT 0,
            cache_hit_ratio REAL DEFAULT 0.0,
            error_message TEXT,
            nix_version TEXT,
            platform TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          );
          
          -- Tool performance table
          CREATE TABLE IF NOT EXISTS tool_performance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            tool_name TEXT NOT NULL,
            operation TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            memory_peak_mb REAL DEFAULT 0,
            cpu_usage_percent REAL DEFAULT 0,
            success BOOLEAN NOT NULL DEFAULT 1,
            error_message TEXT,
            working_directory TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          );
          
          -- Performance alerts table
          CREATE TABLE IF NOT EXISTS performance_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            alert_type TEXT NOT NULL,
            severity TEXT NOT NULL, -- 'low', 'medium', 'high', 'critical'
            metric_name TEXT NOT NULL,
            current_value REAL NOT NULL,
            threshold_value REAL NOT NULL,
            message TEXT NOT NULL,
            acknowledged BOOLEAN DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          );
          
          -- Performance baselines table
          CREATE TABLE IF NOT EXISTS performance_baselines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            metric_type TEXT NOT NULL,
            operation_name TEXT NOT NULL,
            baseline_value REAL NOT NULL,
            measurement_count INTEGER NOT NULL,
            confidence_interval REAL NOT NULL,
            last_updated INTEGER NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          );
          
          -- System information table
          CREATE TABLE IF NOT EXISTS system_info (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            platform TEXT NOT NULL,
            cpu_model TEXT,
            cpu_cores INTEGER,
            memory_total_mb INTEGER,
            disk_total_gb INTEGER,
            nix_version TEXT,
            darwin_version TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          );
          
          -- Create indexes for performance
          CREATE INDEX IF NOT EXISTS idx_system_metrics_timestamp ON system_metrics(timestamp);
          CREATE INDEX IF NOT EXISTS idx_system_metrics_cpu ON system_metrics(cpu_usage_percent);
          CREATE INDEX IF NOT EXISTS idx_system_metrics_memory ON system_metrics(memory_usage_percent);
          
          CREATE INDEX IF NOT EXISTS idx_build_metrics_timestamp ON build_metrics(timestamp);
          CREATE INDEX IF NOT EXISTS idx_build_metrics_operation ON build_metrics(operation_type);
          CREATE INDEX IF NOT EXISTS idx_build_metrics_success ON build_metrics(success);
          CREATE INDEX IF NOT EXISTS idx_build_metrics_duration ON build_metrics(duration_seconds);
          
          CREATE INDEX IF NOT EXISTS idx_tool_performance_timestamp ON tool_performance(timestamp);
          CREATE INDEX IF NOT EXISTS idx_tool_performance_tool ON tool_performance(tool_name);
          CREATE INDEX IF NOT EXISTS idx_tool_performance_operation ON tool_performance(operation);
          
          CREATE INDEX IF NOT EXISTS idx_alerts_timestamp ON performance_alerts(timestamp);
          CREATE INDEX IF NOT EXISTS idx_alerts_type ON performance_alerts(alert_type);
          CREATE INDEX IF NOT EXISTS idx_alerts_acknowledged ON performance_alerts(acknowledged);
          
          CREATE INDEX IF NOT EXISTS idx_baselines_metric ON performance_baselines(metric_type, operation_name);
EOF
        
        # Configure database settings
        ${optionalString config.dotfiles.performance.monitoring.storage.enableWAL ''
          ${sqlite}/bin/sqlite3 "$DB_PATH" "PRAGMA journal_mode=WAL;"
          ${sqlite}/bin/sqlite3 "$DB_PATH" "PRAGMA synchronous=NORMAL;"
        ''}
        
        ${optionalString config.dotfiles.performance.monitoring.storage.autoVacuum ''
          ${sqlite}/bin/sqlite3 "$DB_PATH" "PRAGMA auto_vacuum=INCREMENTAL;"
        ''}
        
        # Set appropriate permissions
        chmod 644 "$DB_PATH"
        
        # Create user database (symlink to system database if accessible)
        if [ -w "$(dirname "$DB_PATH")" ]; then
          ln -sf "$DB_PATH" "$USER_DB_PATH" 2>/dev/null || cp "$DB_PATH" "$USER_DB_PATH"
        else
          # Create separate user database
          cp "$DB_PATH" "$USER_DB_PATH"
          chown yuki:staff "$USER_DB_PATH" 2>/dev/null || true
        fi
        
        echo "Database initialized successfully at $DB_PATH"
        echo "User database available at $USER_DB_PATH"
        
        # Insert initial system information
        PLATFORM=$(uname -s)
        CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs 2>/dev/null || echo "Unknown")
        CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "1")
        MEMORY_MB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo "0") / 1024 / 1024 ))
        NIX_VERSION=$(nix --version 2>/dev/null | head -1 || echo "Unknown")
        
        ${sqlite}/bin/sqlite3 "$DB_PATH" << EOF
          INSERT INTO system_info (
            timestamp, platform, cpu_model, cpu_cores, memory_total_mb, nix_version
          ) VALUES (
            $(date +%s), '$PLATFORM', '$CPU_MODEL', $CPU_CORES, $MEMORY_MB, '$NIX_VERSION'
          );
EOF
        
        echo "System information recorded"
      '')
      
      # Database maintenance script
      (writeShellScriptBin "dotfiles-maintain-database" ''
        #!/bin/bash
        
        # Database maintenance and optimization
        
        set -euo pipefail
        
        DB_PATH="''${1:-${config.dotfiles.performance.monitoring.storage.databasePath}}"
        
        if [ ! -f "$DB_PATH" ]; then
          echo "Database not found at $DB_PATH"
          exit 1
        fi
        
        echo "Performing database maintenance on $DB_PATH"
        
        # Get database size before maintenance
        SIZE_BEFORE=$(stat -f%z "$DB_PATH" 2>/dev/null || stat -c%s "$DB_PATH" 2>/dev/null || echo "0")
        
        # Clean old data based on retention policy
        RETENTION_DAYS=${toString config.dotfiles.performance.monitoring.retention}
        CUTOFF_TIMESTAMP=$(($(date +%s) - (RETENTION_DAYS * 24 * 3600)))
        
        echo "Cleaning data older than $RETENTION_DAYS days (before $(date -d @$CUTOFF_TIMESTAMP))"
        
        ${sqlite}/bin/sqlite3 "$DB_PATH" << EOF
          DELETE FROM system_metrics WHERE timestamp < $CUTOFF_TIMESTAMP;
          DELETE FROM build_metrics WHERE timestamp < $CUTOFF_TIMESTAMP;
          DELETE FROM tool_performance WHERE timestamp < $CUTOFF_TIMESTAMP;
          DELETE FROM performance_alerts WHERE timestamp < $CUTOFF_TIMESTAMP AND acknowledged = 1;
EOF
        
        # Vacuum database
        echo "Optimizing database..."
        ${sqlite}/bin/sqlite3 "$DB_PATH" "VACUUM;"
        
        # Update statistics
        ${sqlite}/bin/sqlite3 "$DB_PATH" "ANALYZE;"
        
        # Get database size after maintenance
        SIZE_AFTER=$(stat -f%z "$DB_PATH" 2>/dev/null || stat -c%s "$DB_PATH" 2>/dev/null || echo "0")
        SIZE_SAVED=$((SIZE_BEFORE - SIZE_AFTER))
        
        echo "Database maintenance completed"
        echo "Size before: $SIZE_BEFORE bytes"
        echo "Size after: $SIZE_AFTER bytes" 
        echo "Space saved: $SIZE_SAVED bytes"
        
        # Show database statistics
        echo
        echo "=== Database Statistics ==="
        ${sqlite}/bin/sqlite3 "$DB_PATH" << 'EOF'
          .mode column
          .headers on
          
          SELECT 
            'System Metrics' as Table,
            COUNT(*) as Records,
            MIN(datetime(timestamp, 'unixepoch', 'localtime')) as Oldest,
            MAX(datetime(timestamp, 'unixepoch', 'localtime')) as Newest
          FROM system_metrics
          
          UNION ALL
          
          SELECT 
            'Build Metrics',
            COUNT(*),
            MIN(datetime(timestamp, 'unixepoch', 'localtime')),
            MAX(datetime(timestamp, 'unixepoch', 'localtime'))
          FROM build_metrics
          
          UNION ALL
          
          SELECT 
            'Tool Performance',
            COUNT(*),
            MIN(datetime(timestamp, 'unixepoch', 'localtime')),
            MAX(datetime(timestamp, 'unixepoch', 'localtime'))
          FROM tool_performance;
EOF
      '')
      
      # Database backup script
      (writeShellScriptBin "dotfiles-backup-database" ''
        #!/bin/bash
        
        # Create backup of performance database
        
        set -euo pipefail
        
        DB_PATH="''${1:-${config.dotfiles.performance.monitoring.storage.databasePath}}"
        BACKUP_DIR="''${2:-/Users/yuki/.local/share/dotfiles-performance/backups}"
        
        if [ ! -f "$DB_PATH" ]; then
          echo "Database not found at $DB_PATH"
          exit 1
        fi
        
        mkdir -p "$BACKUP_DIR"
        
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_FILE="$BACKUP_DIR/performance_backup_$TIMESTAMP.db"
        
        echo "Creating database backup..."
        echo "Source: $DB_PATH"
        echo "Backup: $BACKUP_FILE"
        
        # Create backup using SQLite backup command
        ${sqlite}/bin/sqlite3 "$DB_PATH" ".backup '$BACKUP_FILE'"
        
        # Compress backup
        gzip "$BACKUP_FILE"
        BACKUP_FILE="$BACKUP_FILE.gz"
        
        echo "Backup created: $BACKUP_FILE"
        
        # Clean old backups (keep last 10)
        find "$BACKUP_DIR" -name "performance_backup_*.db.gz" -type f | sort | head -n -10 | xargs rm -f
        
        echo "Old backups cleaned"
        
        # Show backup size
        SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null || echo "0")
        echo "Backup size: $SIZE bytes"
      '')
    ];
    
    # Automated database maintenance via cron/launchd
    launchd.user.agents.dotfiles-database-maintenance = mkIf (platformInfo.isDarwin or false) {
      serviceConfig = {
        Label = "org.dotfiles.database-maintenance";
        ProgramArguments = [
          "${pkgs.writeShellScript "database-maintenance" ''
            #!/bin/bash
            ${getBin pkgs.sqlite}/bin/dotfiles-maintain-database
            ${getBin pkgs.sqlite}/bin/dotfiles-backup-database
          ''}"
        ];
        StartCalendarInterval = {
          Hour = 3;
          Minute = 0;
        };
        StandardErrorPath = "/Users/yuki/.local/share/dotfiles-performance/logs/maintenance-error.log";
        StandardOutPath = "/Users/yuki/.local/share/dotfiles-performance/logs/maintenance-output.log";
      };
    };
  };
}