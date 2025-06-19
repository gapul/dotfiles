{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.automation.monitoring;
in
{
  options.dotfiles.automation.monitoring = {
    enable = mkEnableOption "Monitoring and logging system integration";
    
    prometheusStack = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Prometheus monitoring stack";
    };
    
    grafanaSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Grafana dashboards";
    };
    
    elkStack = mkOption {
      type = types.bool;
      default = false;
      description = "Enable ELK (Elasticsearch, Logstash, Kibana) stack";
    };
    
    lokiStack = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Loki logging stack";
    };
    
    jaegerTracing = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Jaeger distributed tracing";
    };
    
    alertmanagerSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Alertmanager for notifications";
    };
    
    nodeExporter = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Node Exporter for system metrics";
    };
    
    cloudMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable cloud provider monitoring tools";
    };
  };

  config = mkIf cfg.enable {
    # Monitoring tools
    home-manager.users.yuki.home.packages = with pkgs; [
      # Core monitoring
      curl
      jq
      
      # Prometheus ecosystem
    ] ++ optionals cfg.prometheusStack [
      prometheus
      # promtool is included with prometheus package
      prometheus-pushgateway
    ] ++ optionals cfg.grafanaSupport [
      grafana
    ] ++ optionals cfg.lokiStack [
      grafana-loki
      promtail
      # logcli is included with grafana-loki
    ] ++ optionals cfg.alertmanagerSupport [
      prometheus-alertmanager
    ] ++ optionals cfg.nodeExporter [
      prometheus-node-exporter
    ] ++ optionals cfg.jaegerTracing [
      jaeger
    ] ++ optionals cfg.cloudMonitoring [
      # Cloud monitoring tools
      awscli2  # CloudWatch
    ];

    # Monitoring stack initialization
    home-manager.users.yuki.home.file."bin/monitoring-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Monitoring Stack Initialization
        set -euo pipefail
        
        STACK_TYPE="''${1:-prometheus}"
        ENVIRONMENT="''${2:-development}"
        
        echo "📊 Monitoring Stack Initialization"
        echo "================================="
        echo "Stack: $STACK_TYPE"
        echo "Environment: $ENVIRONMENT"
        echo ""
        
        case "$STACK_TYPE" in
          "prometheus")
            echo "🔥 Setting up Prometheus monitoring stack..."
            
            # Create directory structure
            mkdir -p monitoring/{prometheus,grafana,alertmanager}/{config,data}
            
            # Prometheus configuration
            cat > monitoring/prometheus/config/prometheus.yml << 'EOF'
        global:
          scrape_interval: 15s
          evaluation_interval: 15s
        
        rule_files:
          - "alerts/*.yml"
        
        alerting:
          alertmanagers:
            - static_configs:
                - targets:
                  - alertmanager:9093
        
        scrape_configs:
          - job_name: 'prometheus'
            static_configs:
              - targets: ['localhost:9090']
        
          - job_name: 'node-exporter'
            static_configs:
              - targets: ['localhost:9100']
        
          - job_name: 'application'
            static_configs:
              - targets: ['localhost:8080']
            metrics_path: /metrics
            scrape_interval: 30s
        
          # Kubernetes monitoring (if applicable)
          - job_name: 'kubernetes-pods'
            kubernetes_sd_configs:
              - role: pod
            relabel_configs:
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                action: keep
                regex: true
        EOF
            
            # Alerting rules
            mkdir -p monitoring/prometheus/config/alerts
            cat > monitoring/prometheus/config/alerts/basic.yml << 'EOF'
        groups:
          - name: basic-alerts
            rules:
              - alert: InstanceDown
                expr: up == 0
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "Instance {{ $labels.instance }} down"
                  description: "{{ $labels.instance }} has been down for more than 5 minutes."
        
              - alert: HighCPUUsage
                expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
                for: 10m
                labels:
                  severity: warning
                annotations:
                  summary: "High CPU usage on {{ $labels.instance }}"
                  description: "CPU usage is above 80% for more than 10 minutes."
        
              - alert: HighMemoryUsage
                expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
                for: 10m
                labels:
                  severity: warning
                annotations:
                  summary: "High memory usage on {{ $labels.instance }}"
                  description: "Memory usage is above 85% for more than 10 minutes."
        
              - alert: DiskSpaceLow
                expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "Low disk space on {{ $labels.instance }}"
                  description: "Disk space is below 10% on {{ $labels.mountpoint }}."
        EOF
            
            # Grafana configuration
            cat > monitoring/grafana/config/grafana.ini << 'EOF'
        [server]
        http_port = 3000
        domain = localhost
        
        [database]
        type = sqlite3
        path = /var/lib/grafana/grafana.db
        
        [security]
        admin_user = admin
        admin_password = admin
        
        [users]
        allow_sign_up = false
        
        [auth.anonymous]
        enabled = false
        
        [dashboards]
        default_home_dashboard_path = /etc/grafana/provisioning/dashboards/default.json
        EOF
            
            # Alertmanager configuration
            cat > monitoring/alertmanager/config/alertmanager.yml << 'EOF'
        global:
          smtp_smarthost: 'localhost:587'
          smtp_from: 'alertmanager@example.com'
        
        route:
          group_by: ['alertname']
          group_wait: 10s
          group_interval: 10s
          repeat_interval: 1h
          receiver: 'web.hook'
        
        receivers:
          - name: 'web.hook'
            webhook_configs:
              - url: 'http://localhost:5001/'
        
          - name: 'slack'
            slack_configs:
              - api_url: 'YOUR_SLACK_WEBHOOK_URL'
                channel: '#alerts'
                text: 'Alert: {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
        
          - name: 'email'
            email_configs:
              - to: 'admin@example.com'
                subject: 'Alert: {{ .GroupLabels.alertname }}'
                body: |
                  {{ range .Alerts }}
                  Alert: {{ .Annotations.summary }}
                  Description: {{ .Annotations.description }}
                  {{ end }}
        EOF
            
            # Docker Compose for the stack
            cat > monitoring/docker-compose.yml << 'EOF'
        version: '3.8'
        
        services:
          prometheus:
            image: prom/prometheus:latest
            container_name: prometheus
            ports:
              - "9090:9090"
            volumes:
              - ./prometheus/config:/etc/prometheus
              - ./prometheus/data:/prometheus
            command:
              - '--config.file=/etc/prometheus/prometheus.yml'
              - '--storage.tsdb.path=/prometheus'
              - '--web.console.libraries=/etc/prometheus/console_libraries'
              - '--web.console.templates=/etc/prometheus/consoles'
              - '--web.enable-lifecycle'
              - '--web.enable-admin-api'
        
          grafana:
            image: grafana/grafana:latest
            container_name: grafana
            ports:
              - "3000:3000"
            volumes:
              - ./grafana/config:/etc/grafana
              - ./grafana/data:/var/lib/grafana
            environment:
              - GF_SECURITY_ADMIN_PASSWORD=admin
        
          alertmanager:
            image: prom/alertmanager:latest
            container_name: alertmanager
            ports:
              - "9093:9093"
            volumes:
              - ./alertmanager/config:/etc/alertmanager
        
          node-exporter:
            image: prom/node-exporter:latest
            container_name: node-exporter
            ports:
              - "9100:9100"
            volumes:
              - /proc:/host/proc:ro
              - /sys:/host/sys:ro
              - /:/rootfs:ro
            command:
              - '--path.procfs=/host/proc'
              - '--path.rootfs=/rootfs'
              - '--path.sysfs=/host/sys'
              - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
        EOF
            
            echo "✅ Prometheus monitoring stack configured"
            echo "📋 Start with: cd monitoring && docker-compose up -d"
            echo "🌐 Access Grafana at: http://localhost:3000 (admin/admin)"
            echo "🔥 Access Prometheus at: http://localhost:9090"
            ;;
            
          "loki")
            echo "📋 Setting up Loki logging stack..."
            
            mkdir -p logging/{loki,promtail}/{config,data}
            
            # Loki configuration
            cat > logging/loki/config/loki.yml << 'EOF'
        auth_enabled: false
        
        server:
          http_listen_port: 3100
          grpc_listen_port: 9096
        
        common:
          path_prefix: /loki
          storage:
            filesystem:
              chunks_directory: /loki/chunks
              rules_directory: /loki/rules
          replication_factor: 1
          ring:
            instance_addr: 127.0.0.1
            kvstore:
              store: inmemory
        
        schema_config:
          configs:
            - from: 2020-10-24
              store: boltdb-shipper
              object_store: filesystem
              schema: v11
              index:
                prefix: index_
                period: 24h
        
        ruler:
          alertmanager_url: http://localhost:9093
        EOF
            
            # Promtail configuration
            cat > logging/promtail/config/promtail.yml << 'EOF'
        server:
          http_listen_port: 9080
          grpc_listen_port: 0
        
        positions:
          filename: /tmp/positions.yaml
        
        clients:
          - url: http://loki:3100/loki/api/v1/push
        
        scrape_configs:
          - job_name: system
            static_configs:
              - targets:
                  - localhost
                labels:
                  job: varlogs
                  __path__: /var/log/*log
        
          - job_name: containers
            docker_sd_configs:
              - host: unix:///var/run/docker.sock
                refresh_interval: 5s
            relabel_configs:
              - source_labels: ['__meta_docker_container_name']
                target_label: 'container'
        EOF
            
            # Docker Compose for Loki stack
            cat > logging/docker-compose.yml << 'EOF'
        version: '3.8'
        
        services:
          loki:
            image: grafana/loki:latest
            container_name: loki
            ports:
              - "3100:3100"
            volumes:
              - ./loki/config:/etc/loki
              - ./loki/data:/loki
            command: -config.file=/etc/loki/loki.yml
        
          promtail:
            image: grafana/promtail:latest
            container_name: promtail
            volumes:
              - ./promtail/config:/etc/promtail
              - /var/log:/var/log:ro
              - /var/run/docker.sock:/var/run/docker.sock
            command: -config.file=/etc/promtail/promtail.yml
        
          grafana:
            image: grafana/grafana:latest
            container_name: grafana-loki
            ports:
              - "3001:3000"
            environment:
              - GF_SECURITY_ADMIN_PASSWORD=admin
            volumes:
              - grafana-storage:/var/lib/grafana
        
        volumes:
          grafana-storage:
        EOF
            
            echo "✅ Loki logging stack configured"
            echo "📋 Start with: cd logging && docker-compose up -d"
            ;;
        esac
        
        echo ""
        echo "🎉 Monitoring stack initialization completed!"
        echo ""
        echo "Next steps:"
        echo "1. Review and customize the configurations"
        echo "2. Set up proper authentication and security"
        echo "3. Configure data sources in Grafana"
        echo "4. Import relevant dashboards"
        echo "5. Set up alerting channels"
      '';
    };

    # Monitoring dashboard manager
    home-manager.users.yuki.home.file."bin/monitoring-dashboard" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Monitoring Dashboard Manager
        set -euo pipefail
        
        COMMAND="''${1:-status}"
        
        case "$COMMAND" in
          "status")
            echo "📊 Monitoring Dashboard Status"
            echo "============================="
            
            # Check Grafana
            if curl -s http://localhost:3000/api/health &> /dev/null; then
              echo "✅ Grafana: Running (http://localhost:3000)"
            else
              echo "❌ Grafana: Not accessible"
            fi
            
            # Check Prometheus
            if curl -s http://localhost:9090/-/healthy &> /dev/null; then
              echo "✅ Prometheus: Running (http://localhost:9090)"
            else
              echo "❌ Prometheus: Not accessible"
            fi
            
            # Check Alertmanager
            if curl -s http://localhost:9093/-/healthy &> /dev/null; then
              echo "✅ Alertmanager: Running (http://localhost:9093)"
            else
              echo "❌ Alertmanager: Not accessible"
            fi
            
            # Check Loki
            if curl -s http://localhost:3100/ready &> /dev/null; then
              echo "✅ Loki: Running (http://localhost:3100)"
            else
              echo "❌ Loki: Not accessible"
            fi
            ;;
            
          "metrics")
            echo "📈 System Metrics Overview"
            echo "========================="
            
            # CPU usage
            if command -v top &> /dev/null; then
              CPU=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo "N/A")
              echo "💻 CPU Usage: $CPU%"
            fi
            
            # Memory usage
            if command -v vm_stat &> /dev/null; then
              MEMORY=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//' || echo "N/A")
              echo "🧠 Memory: $MEMORY pages free"
            fi
            
            # Disk usage
            echo "💾 Disk Usage:"
            df -h | grep -E '^/dev/' | awk '{print "  " $1 ": " $5 " used (" $4 " free)"}'
            
            # Network connections
            if command -v netstat &> /dev/null; then
              CONNECTIONS=$(netstat -an | grep ESTABLISHED | wc -l | tr -d ' ')
              echo "🌐 Network Connections: $CONNECTIONS"
            fi
            ;;
            
          "alerts")
            echo "🚨 Active Alerts"
            echo "==============="
            
            if curl -s http://localhost:9093/api/v1/alerts &> /dev/null; then
              curl -s http://localhost:9093/api/v1/alerts | jq -r '.data[] | "Alert: " + .labels.alertname + " (" + .status.state + ")"' 2>/dev/null || echo "No alerts API response"
            else
              echo "❌ Cannot connect to Alertmanager"
            fi
            ;;
            
          "logs")
            local service="''${2:-all}"
            echo "📋 Recent Logs for: $service"
            
            case "$service" in
              "prometheus")
                docker logs prometheus --tail 50 2>/dev/null || echo "Prometheus container not found"
                ;;
              "grafana")
                docker logs grafana --tail 50 2>/dev/null || echo "Grafana container not found"
                ;;
              "loki")
                docker logs loki --tail 50 2>/dev/null || echo "Loki container not found"
                ;;
              "all"|*)
                echo "Available services: prometheus, grafana, loki"
                echo ""
                echo "Container logs:"
                docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(prometheus|grafana|loki|alertmanager)" || echo "No monitoring containers running"
                ;;
            esac
            ;;
            
          "backup")
            echo "💾 Monitoring Data Backup"
            echo "========================"
            
            BACKUP_DIR="monitoring-backup-$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$BACKUP_DIR"
            
            # Backup Grafana dashboards
            if curl -s http://localhost:3000/api/health &> /dev/null; then
              echo "📊 Backing up Grafana dashboards..."
              # Note: This requires API key setup
              echo "  ⚠️  Manual backup required - use Grafana export feature"
            fi
            
            # Backup Prometheus data
            if [[ -d "monitoring/prometheus/data" ]]; then
              echo "🔥 Backing up Prometheus data..."
              cp -r monitoring/prometheus/data "$BACKUP_DIR/prometheus-data"
            fi
            
            # Backup configurations
            if [[ -d "monitoring" ]]; then
              echo "⚙️  Backing up configurations..."
              cp -r monitoring "$BACKUP_DIR/config"
            fi
            
            echo "✅ Backup completed: $BACKUP_DIR"
            ;;
            
          *)
            echo "Usage: monitoring-dashboard <command> [options]"
            echo ""
            echo "Commands:"
            echo "  status       Show dashboard status"
            echo "  metrics      Show system metrics"
            echo "  alerts       Show active alerts"
            echo "  logs [svc]   Show service logs"
            echo "  backup       Backup monitoring data"
            ;;
        esac
      '';
    };

    # Shell aliases for monitoring
    home-manager.users.yuki.programs.zsh.shellAliases = {
      # Monitoring shortcuts
      mon = "monitoring-dashboard";
      mon-status = "monitoring-dashboard status";
      mon-metrics = "monitoring-dashboard metrics";
      mon-alerts = "monitoring-dashboard alerts";
      
      # Grafana
      grafana = "open http://localhost:3000";
      prometheus = "open http://localhost:9090";
      
      # Log viewing
      logs = "monitoring-dashboard logs";
    };

    # Shell functions for monitoring
    home-manager.users.yuki.programs.zsh.initExtra = ''
      # Quick metrics
      metrics() {
        echo "⚡ Quick System Metrics"
        echo "======================"
        
        # System load
        if command -v uptime &> /dev/null; then
          echo "📊 Load: $(uptime | awk -F'load average:' '{print $2}')"
        fi
        
        # Top processes
        echo ""
        echo "🔝 Top Processes:"
        ps aux --sort=-%cpu | head -6 | awk 'NR==1{print "  " $0} NR>1{printf "  %-8s %5s %5s %s\n", $1, $3"%", $4"%", $11}'
        
        # Disk usage
        echo ""
        echo "💾 Disk Usage:"
        df -h | grep -E '^/dev/' | awk '{printf "  %-20s %5s used (%s free)\n", $1, $5, $4}'
      }
      
      # Alert testing
      test-alert() {
        local alert_name="''${1:-test-alert}"
        
        echo "🚨 Testing alert: $alert_name"
        
        # Send test alert to Alertmanager
        curl -XPOST http://localhost:9093/api/v1/alerts -H "Content-Type: application/json" -d "[
          {
            \"labels\": {
              \"alertname\": \"$alert_name\",
              \"severity\": \"warning\",
              \"instance\": \"localhost:9090\"
            },
            \"annotations\": {
              \"summary\": \"Test alert from monitoring system\",
              \"description\": \"This is a test alert triggered manually\"
            },
            \"startsAt\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
            \"endsAt\": \"$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%S.000Z)\"
          }
        ]" 2>/dev/null && echo "✅ Test alert sent" || echo "❌ Failed to send test alert"
      }
      
      # Quick dashboard setup
      setup-monitoring() {
        echo "🚀 Setting up monitoring stack..."
        
        if [[ ! -d "monitoring" ]]; then
          monitoring-init prometheus
        fi
        
        echo "📊 Starting monitoring stack..."
        cd monitoring && docker-compose up -d
        
        echo "⏳ Waiting for services to start..."
        sleep 10
        
        monitoring-dashboard status
      }
    '';
  };
}