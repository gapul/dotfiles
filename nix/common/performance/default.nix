# Intelligent Performance Monitoring System
# Real-time monitoring, analysis, and optimization for dotfiles environment
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  imports = [
    ./monitoring
    ./monitoring/storage/metrics-db.nix
    ./monitoring/analysis
    ./optimization
  ];

  options.dotfiles.performance = {
    enable = mkEnableOption "Intelligent performance monitoring and optimization";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "comprehensive" "adaptive" ];
      default = "standard";
      description = "Performance monitoring profile";
    };
    
    monitoring = {
      interval = mkOption {
        type = types.int;
        default = 30;
        description = "Monitoring data collection interval in seconds";
      };
      
      retention = mkOption {
        type = types.int;
        default = 30;
        description = "Data retention period in days";
      };
      
      alertThresholds = {
        cpuUsage = mkOption {
          type = types.int;
          default = 80;
          description = "CPU usage alert threshold percentage";
        };
        
        memoryUsage = mkOption {
          type = types.int;
          default = 85;
          description = "Memory usage alert threshold percentage";
        };
        
        buildTimeIncrease = mkOption {
          type = types.int;
          default = 50;
          description = "Build time increase alert threshold percentage";
        };
      };
    };
    
    optimization = {
      autoTuning = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic performance optimization";
      };
      
      nixBuildOptimization = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Nix build process optimization";
      };
      
      resourceManagement = mkOption {
        type = types.bool;
        default = true;
        description = "Enable dynamic resource management";
      };
    };
  };

  config = mkIf config.dotfiles.performance.enable {
    # Enable monitoring based on profile
    dotfiles.performance.monitoring = {
      systemMetrics.enable = mkDefault true;
      buildTimes.enable = mkDefault true;
      toolPerformance.enable = mkDefault (
        elem config.dotfiles.performance.profile [ "standard" "comprehensive" "adaptive" ]
      );
      analysis.enable = mkDefault (
        elem config.dotfiles.performance.profile [ "comprehensive" "adaptive" ]
      );
    };
    
    # Enable optimization based on profile  
    dotfiles.performance.optimization = {
      autoTuning = mkDefault (
        elem config.dotfiles.performance.profile [ "adaptive" ]
      );
      resourceOptimization = mkDefault (
        elem config.dotfiles.performance.profile [ "standard" "comprehensive" "adaptive" ]
      );
    };

    # Performance monitoring packages
    environment.systemPackages = with pkgs; [
      # System monitoring tools
      htop
      
      # System information
      neofetch
      
      # Performance analysis
      time
      
      # Database for metrics storage
      sqlite
      
      # JSON processing for metrics
      jq
      
      # Disk usage analysis
      ncdu
      
      # Math calculation
      bc
      
      # Note: Platform-specific tools are included via system PATH
    ];

    # Create performance monitoring data directory
    system.activationScripts.performanceMonitoring = {
      text = ''
        # Create monitoring data directory
        mkdir -p /var/lib/dotfiles-performance/{metrics,logs,reports}
        chmod 755 /var/lib/dotfiles-performance
        
        # Create user-specific monitoring directory  
        if [ -d "/Users/yuki" ]; then
          mkdir -p "/Users/yuki/.local/share/dotfiles-performance/{metrics,logs,cache}"
          chown -R yuki:staff "/Users/yuki/.local/share/dotfiles-performance"
        fi
        
        # Initialize performance database
        if [ ! -f "/var/lib/dotfiles-performance/metrics/performance.db" ]; then
          ${pkgs.sqlite}/bin/sqlite3 /var/lib/dotfiles-performance/metrics/performance.db << 'EOF'
            CREATE TABLE system_metrics (
              timestamp INTEGER PRIMARY KEY,
              cpu_usage_percent REAL,
              memory_usage_percent REAL,
              disk_usage_percent REAL,
              load_average_1m REAL,
              load_average_5m REAL,
              load_average_15m REAL,
              disk_read_mb_per_sec REAL,
              disk_write_mb_per_sec REAL,
              network_rx_mb_per_sec REAL,
              network_tx_mb_per_sec REAL
            );
            
            CREATE TABLE build_metrics (
              timestamp INTEGER PRIMARY KEY,
              operation_type TEXT,
              duration_seconds REAL,
              success BOOLEAN,
              packages_built INTEGER,
              cache_hit_ratio REAL,
              error_message TEXT
            );
            
            CREATE TABLE tool_performance (
              timestamp INTEGER PRIMARY KEY,
              tool_name TEXT,
              operation TEXT,
              duration_ms INTEGER,
              memory_peak_mb REAL,
              success BOOLEAN
            );
            
            CREATE INDEX idx_system_metrics_timestamp ON system_metrics(timestamp);
            CREATE INDEX idx_build_metrics_timestamp ON build_metrics(timestamp);
            CREATE INDEX idx_tool_performance_timestamp ON tool_performance(timestamp);
            CREATE INDEX idx_tool_performance_tool ON tool_performance(tool_name);
EOF
        fi
        
        echo "Performance monitoring system initialized"
      '';
    };
  };
}