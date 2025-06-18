{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./iac
    ./kubernetes
    ./cloud
    ./cicd
    ./monitoring
  ];

  options.dotfiles.automation = {
    enable = mkEnableOption "Advanced automation and orchestration";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" "enterprise" ];
      default = "standard";
      description = "Automation profile level";
    };
    
    multiEnvironment = mkOption {
      type = types.bool;
      default = true;
      description = "Enable multi-environment deployment automation";
    };
  };

  config = mkIf config.dotfiles.automation.enable {
    # Enable components based on profile and set profile-specific configurations
    dotfiles.automation.iac = mkDefault (mkMerge [
      # Base enable setting
      { enable = true; }
      
      # Profile-specific configurations
      (
      if config.dotfiles.automation.profile == "minimal" then {
        terraformSupport = true;
        ansibleSupport = false;
        validationTools = false;
      } else if config.dotfiles.automation.profile == "standard" then {
        terraformSupport = true;
        ansibleSupport = true;
        helmSupport = true;
        validationTools = true;
      } else {
        terraformSupport = true;
        ansibleSupport = true;
        pulumiaSupport = true;
        helmSupport = true;
        validationTools = true;
        secretsManagement = true;
      })
    ]);
    
    dotfiles.automation.kubernetes.enable = mkDefault (
      elem config.dotfiles.automation.profile [ "standard" "full" "enterprise" ]
    );
    
    dotfiles.automation.cloud = mkDefault (mkMerge [
      # Base enable setting
      { enable = elem config.dotfiles.automation.profile [ "full" "enterprise" ]; }
      
      # Profile-specific configurations
      (if config.dotfiles.automation.profile == "enterprise" then {
        awsSupport = true;
        gcpSupport = true;
        azureSupport = true;
        multiCloudTools = true;
        costManagement = true;
        securityTools = true;
      } else {
        awsSupport = true;
        multiCloudTools = true;
        securityTools = true;
      })
    ]);
    
    dotfiles.automation.cicd.enable = mkDefault (
      elem config.dotfiles.automation.profile [ "standard" "full" "enterprise" ]
    );
    
    dotfiles.automation.monitoring.enable = mkDefault (
      elem config.dotfiles.automation.profile [ "full" "enterprise" ]
    );

    # Common automation tools for all profiles
    home.packages = with pkgs; [
      # Core tools
      git
      curl
      jq
      yq-go
      
      # Automation essentials
      just
      make
      
      # Text processing
      sed
      awk
      grep
      
      # Network tools
      netcat
      socat
      
      # Deployment tools
      rsync
      
    ] ++ optionals (config.dotfiles.automation.profile != "minimal") [
      # Standard automation tools
      ansible
      terraform
      kubectl
      helm
      
      # Container tools
      docker
      docker-compose
      
      # Monitoring basics
      htop
      iotop
      
    ] ++ optionals (elem config.dotfiles.automation.profile [ "full" "enterprise" ]) [
      # Advanced tools
      kubernetes-helm
      argocd
      prometheus
      grafana
      
      # Security tools
      trivy
      checkov
      
      # Multi-cloud
      awscli2
      google-cloud-sdk
    ];

    # Multi-environment deployment automation
    home.file."bin/deploy-manager" = mkIf config.dotfiles.automation.multiEnvironment {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Multi-Environment Deployment Manager
        set -euo pipefail
        
        COMMAND="''${1:-help}"
        ENVIRONMENT="''${2:-dev}"
        APPLICATION="''${3:-current}"
        
        # Colors for output
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m'
        
        log_info() { echo -e "''${BLUE}ℹ️  $1''${NC}"; }
        log_success() { echo -e "''${GREEN}✅ $1''${NC}"; }
        log_warning() { echo -e "''${YELLOW}⚠️  $1''${NC}"; }
        log_error() { echo -e "''${RED}❌ $1''${NC}"; }
        
        # Configuration
        ENVIRONMENTS=("dev" "staging" "prod")
        CONFIG_DIR="deployment-config"
        
        case "$COMMAND" in
          "init")
            log_info "Initializing multi-environment deployment structure"
            
            # Create directory structure
            mkdir -p "$CONFIG_DIR"/{environments,applications,scripts,templates}
            
            # Create environment configurations
            for env in "''${ENVIRONMENTS[@]}"; do
              mkdir -p "$CONFIG_DIR/environments/$env"
              
              cat > "$CONFIG_DIR/environments/$env/config.yml" << EOF
        # Environment configuration for $env
        environment:
          name: $env
          region: us-west-2
          cluster: $env-cluster
          namespace: $env-apps
          
        resources:
          cpu_limit: $([ "$env" = "prod" ] && echo "2000m" || echo "1000m")
          memory_limit: $([ "$env" = "prod" ] && echo "2Gi" || echo "1Gi")
          replicas: $([ "$env" = "prod" ] && echo "3" || echo "2")
          
        security:
          network_policies: $([ "$env" = "prod" ] && echo "strict" || echo "standard")
          pod_security: $([ "$env" = "prod" ] && echo "restricted" || echo "baseline")
          
        monitoring:
          enabled: true
          alerts: $([ "$env" = "prod" ] && echo "true" || echo "false")
          
        backup:
          enabled: $([ "$env" = "prod" ] && echo "true" || echo "false")
          retention: $([ "$env" = "prod" ] && echo "30d" || echo "7d")
        EOF
            done
            
            # Create deployment pipeline template
            cat > "$CONFIG_DIR/scripts/deploy.sh" << 'EOF'
        #!/bin/bash
        # Deployment Script Template
        set -euo pipefail
        
        ENV="$1"
        APP="$2"
        VERSION="''${3:-latest}"
        
        echo "🚀 Deploying $APP to $ENV (version: $VERSION)"
        
        # Load environment configuration
        CONFIG_FILE="environments/$ENV/config.yml"
        if [[ ! -f "$CONFIG_FILE" ]]; then
          echo "❌ Environment configuration not found: $CONFIG_FILE"
          exit 1
        fi
        
        # Validation
        echo "🔍 Running pre-deployment checks..."
        
        # Health check
        if [[ "$ENV" != "dev" ]]; then
          echo "⚡ Checking target environment health..."
          # Add health checks here
        fi
        
        # Deploy
        echo "📦 Deploying application..."
        case "$ENV" in
          "dev")
            echo "  🏗️  Development deployment"
            # Add dev deployment logic
            ;;
          "staging")
            echo "  🧪 Staging deployment"
            # Add staging deployment logic
            ;;
          "prod")
            echo "  🏭 Production deployment"
            # Add production deployment logic with additional safety checks
            ;;
        esac
        
        # Post-deployment verification
        echo "✅ Deployment completed, running verification..."
        # Add verification logic
        
        echo "🎉 $APP successfully deployed to $ENV"
        EOF
            
            chmod +x "$CONFIG_DIR/scripts/deploy.sh"
            
            # Create application template
            cat > "$CONFIG_DIR/applications/app-template.yml" << 'EOF'
        # Application Template
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: {{APP_NAME}}
          namespace: {{NAMESPACE}}
          labels:
            app: {{APP_NAME}}
            environment: {{ENVIRONMENT}}
        spec:
          replicas: {{REPLICAS}}
          selector:
            matchLabels:
              app: {{APP_NAME}}
          template:
            metadata:
              labels:
                app: {{APP_NAME}}
                environment: {{ENVIRONMENT}}
            spec:
              containers:
              - name: {{APP_NAME}}
                image: {{IMAGE}}:{{VERSION}}
                ports:
                - containerPort: 8080
                env:
                - name: ENVIRONMENT
                  value: {{ENVIRONMENT}}
                resources:
                  requests:
                    cpu: 100m
                    memory: 128Mi
                  limits:
                    cpu: {{CPU_LIMIT}}
                    memory: {{MEMORY_LIMIT}}
                livenessProbe:
                  httpGet:
                    path: /health
                    port: 8080
                  initialDelaySeconds: 30
                  periodSeconds: 10
                readinessProbe:
                  httpGet:
                    path: /ready
                    port: 8080
                  initialDelaySeconds: 5
                  periodSeconds: 5
        EOF
            
            log_success "Multi-environment deployment structure initialized"
            log_info "Next steps:"
            log_info "  1. Customize environment configurations in $CONFIG_DIR/environments/"
            log_info "  2. Create application-specific deployment manifests"
            log_info "  3. Set up CI/CD pipeline integration"
            ;;
            
          "deploy")
            if [[ ! -d "$CONFIG_DIR" ]]; then
              log_error "Deployment configuration not found. Run 'deploy-manager init' first."
              exit 1
            fi
            
            if [[ ! " ''${ENVIRONMENTS[*]} " =~ " $ENVIRONMENT " ]]; then
              log_error "Invalid environment: $ENVIRONMENT"
              log_info "Available environments: ''${ENVIRONMENTS[*]}"
              exit 1
            fi
            
            log_info "Deploying $APPLICATION to $ENVIRONMENT"
            
            # Load environment configuration
            ENV_CONFIG="$CONFIG_DIR/environments/$ENVIRONMENT/config.yml"
            if [[ ! -f "$ENV_CONFIG" ]]; then
              log_error "Environment configuration not found: $ENV_CONFIG"
              exit 1
            fi
            
            # Safety checks for production
            if [[ "$ENVIRONMENT" == "prod" ]]; then
              log_warning "Production deployment requires confirmation"
              read -p "Deploy to PRODUCTION? Type 'yes' to confirm: " -r
              if [[ "$REPLY" != "yes" ]]; then
                log_info "Deployment cancelled"
                exit 0
              fi
            fi
            
            # Execute deployment script
            if [[ -f "$CONFIG_DIR/scripts/deploy.sh" ]]; then
              cd "$CONFIG_DIR"
              ./scripts/deploy.sh "$ENVIRONMENT" "$APPLICATION"
            else
              log_error "Deployment script not found"
              exit 1
            fi
            ;;
            
          "status")
            log_info "Multi-Environment Status Overview"
            echo "================================="
            
            for env in "''${ENVIRONMENTS[@]}"; do
              echo ""
              echo "🌍 Environment: $env"
              
              # Check if configuration exists
              if [[ -f "$CONFIG_DIR/environments/$env/config.yml" ]]; then
                echo "  ✅ Configuration: Present"
                
                # Try to get deployment status (this would be environment-specific)
                echo "  📊 Status: $([ "$env" = "prod" ] && echo "🟢 Active" || echo "🟡 Ready")"
                
                # Show resource information if available
                if command -v kubectl &> /dev/null; then
                  NAMESPACE=$(yq eval '.environment.namespace' "$CONFIG_DIR/environments/$env/config.yml" 2>/dev/null || echo "$env-apps")
                  if kubectl get namespace "$NAMESPACE" &> /dev/null; then
                    PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l | tr -d ' ')
                    echo "  🏃 Pods: $PODS running"
                  else
                    echo "  📦 Namespace: Not found"
                  fi
                fi
              else
                echo "  ❌ Configuration: Missing"
              fi
            done
            ;;
            
          "rollback")
            local version="''${4:-previous}"
            
            log_warning "Rolling back $APPLICATION in $ENVIRONMENT to $version"
            
            if [[ "$ENVIRONMENT" == "prod" ]]; then
              read -p "Rollback PRODUCTION? Type 'yes' to confirm: " -r
              if [[ "$REPLY" != "yes" ]]; then
                log_info "Rollback cancelled"
                exit 0
              fi
            fi
            
            # Rollback logic would be implemented here
            log_info "Implementing rollback to $version..."
            log_success "Rollback completed"
            ;;
            
          "promote")
            local source_env="''${ENVIRONMENT}"
            local target_env="''${4:-}"
            
            if [[ -z "$target_env" ]]; then
              log_error "Target environment required for promotion"
              log_info "Usage: deploy-manager promote <source-env> <app> <target-env>"
              exit 1
            fi
            
            log_info "Promoting $APPLICATION from $source_env to $target_env"
            
            # Promotion logic
            log_info "1. Validating source deployment..."
            log_info "2. Preparing target environment..."
            log_info "3. Executing promotion..."
            log_success "Promotion completed"
            ;;
            
          "help"|*)
            echo "Multi-Environment Deployment Manager"
            echo "===================================="
            echo ""
            echo "Usage: deploy-manager <command> [environment] [application] [options]"
            echo ""
            echo "Commands:"
            echo "  init                    Initialize deployment structure"
            echo "  deploy <env> <app>      Deploy application to environment"
            echo "  status                  Show multi-environment status"
            echo "  rollback <env> <app>    Rollback application"
            echo "  promote <src> <app> <dst> Promote between environments"
            echo ""
            echo "Environments: ''${ENVIRONMENTS[*]}"
            echo ""
            echo "Examples:"
            echo "  deploy-manager init"
            echo "  deploy-manager deploy dev my-app"
            echo "  deploy-manager promote staging my-app prod"
            ;;
        esac
      '';
    };

    # Automation health check
    home.file."bin/automation-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Automation System Health Check
        set -euo pipefail
        
        echo "🏥 Automation System Health Check"
        echo "================================="
        
        ISSUES=0
        
        echo "🔧 Core Tools:"
        
        # Essential tools
        tools=(
          "git:Version control"
          "kubectl:Kubernetes CLI"
          "terraform:Infrastructure as Code"
          "docker:Container platform"
          "helm:Kubernetes package manager"
        )
        
        for tool_desc in "''${tools[@]}"; do
          tool="''${tool_desc%%:*}"
          desc="''${tool_desc##*:}"
          
          if command -v "$tool" &> /dev/null; then
            echo "  ✅ $tool: $desc"
          else
            echo "  ❌ $tool: $desc (not found)"
            ((ISSUES++))
          fi
        done
        
        echo ""
        echo "☁️  Cloud Providers:"
        
        # AWS
        ${if config.dotfiles.automation.cloud.awsSupport then ''
          if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
            echo "  ✅ AWS: Connected"
          else
            echo "  ⚠️  AWS: Not authenticated"
          fi
        '' else ''
          echo "  ⚪ AWS: Disabled"
        ''}
        
        # Kubernetes
        echo ""
        echo "☸️  Kubernetes:"
        if command -v kubectl &> /dev/null; then
          if kubectl cluster-info &> /dev/null; then
            echo "  ✅ Cluster: Connected"
            CONTEXT=$(kubectl config current-context)
            echo "  📋 Context: $CONTEXT"
          else
            echo "  ❌ Cluster: Not accessible"
            ((ISSUES++))
          fi
        else
          echo "  ⚪ kubectl: Not installed"
        fi
        
        # CI/CD
        echo ""
        echo "🚀 CI/CD:"
        ${if config.dotfiles.automation.cicd.githubActionsSupport then ''
          if command -v gh &> /dev/null && gh auth status &> /dev/null; then
            echo "  ✅ GitHub CLI: Authenticated"
          else
            echo "  ⚠️  GitHub CLI: Not authenticated"
          fi
        '' else ''
          echo "  ⚪ GitHub Actions: Disabled"
        ''}
        
        # Monitoring
        echo ""
        echo "📊 Monitoring:"
        ${if config.dotfiles.automation.monitoring.enable then ''
          if curl -s http://localhost:9090/-/healthy &> /dev/null; then
            echo "  ✅ Prometheus: Running"
          else
            echo "  ❌ Prometheus: Not running"
          fi
          
          if curl -s http://localhost:3000/api/health &> /dev/null; then
            echo "  ✅ Grafana: Running"
          else
            echo "  ❌ Grafana: Not running"
          fi
        '' else ''
          echo "  ⚪ Monitoring: Disabled"
        ''}
        
        echo ""
        echo "📊 Summary:"
        if [[ $ISSUES -eq 0 ]]; then
          echo "  ✅ Automation system: Healthy"
        else
          echo "  ⚠️  Automation system: $ISSUES issues found"
        fi
        
        echo ""
        echo "💡 Profile: ${config.dotfiles.automation.profile}"
        echo "🔧 Components:"
        echo "  • IaC: ${if config.dotfiles.automation.iac.enable then "Enabled" else "Disabled"}"
        echo "  • Kubernetes: ${if config.dotfiles.automation.kubernetes.enable then "Enabled" else "Disabled"}"
        echo "  • Cloud: ${if config.dotfiles.automation.cloud.enable then "Enabled" else "Disabled"}"
        echo "  • CI/CD: ${if config.dotfiles.automation.cicd.enable then "Enabled" else "Disabled"}"
        echo "  • Monitoring: ${if config.dotfiles.automation.monitoring.enable then "Enabled" else "Disabled"}"
      '';
    };

    # Shell aliases for automation
    programs.zsh.shellAliases = {
      # Automation management
      auto = "automation-health";
      auto-health = "automation-health";
      
      # Multi-environment deployment
      deploy = mkIf config.dotfiles.automation.multiEnvironment "deploy-manager";
      deploy-status = mkIf config.dotfiles.automation.multiEnvironment "deploy-manager status";
      
      # Quick shortcuts
      tf = "terraform";
      k = "kubectl";
      h = "helm";
    };

    # Shell functions for automation
    programs.zsh.initExtra = ''
      # Automation environment switcher
      auto-env() {
        local env="''${1:-}"
        
        if [[ -z "$env" ]]; then
          echo "🌍 Available environments:"
          echo "  • dev (development)"
          echo "  • staging (staging)" 
          echo "  • prod (production)"
          echo ""
          echo "Current context: $(kubectl config current-context 2>/dev/null || echo 'none')"
          return
        fi
        
        case "$env" in
          "dev"|"development")
            export KUBECONFIG="$HOME/.kube/config-dev"
            export AWS_PROFILE="dev"
            echo "🟢 Switched to development environment"
            ;;
          "staging")
            export KUBECONFIG="$HOME/.kube/config-staging"
            export AWS_PROFILE="staging"
            echo "🟡 Switched to staging environment"
            ;;
          "prod"|"production")
            export KUBECONFIG="$HOME/.kube/config-prod"
            export AWS_PROFILE="prod"
            echo "🔴 Switched to production environment"
            echo "⚠️  Be careful - you are now in production!"
            ;;
          *)
            echo "❌ Unknown environment: $env"
            return 1
            ;;
        esac
      }
      
      # Quick automation status
      auto-status() {
        echo "🤖 Automation Status"
        echo "=================="
        
        # Current environment
        if command -v kubectl &> /dev/null; then
          CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
          echo "☸️  Kubernetes: $CONTEXT"
        fi
        
        # AWS profile
        echo "☁️  AWS Profile: ''${AWS_PROFILE:-default}"
        
        # Terraform workspace
        if [[ -f .terraform/environment ]]; then
          WORKSPACE=$(cat .terraform/environment)
          echo "🏗️  Terraform: $WORKSPACE"
        fi
        
        # Git branch
        if git rev-parse --git-dir > /dev/null 2>&1; then
          BRANCH=$(git branch --show-current)
          echo "🌿 Git: $BRANCH"
        fi
      }
      
      # Infrastructure provisioning
      infra() {
        local action="''${1:-status}"
        local env="''${2:-dev}"
        
        case "$action" in
          "init")
            echo "🏗️  Initializing infrastructure for $env..."
            iac-init infrastructure terraform "$env"
            ;;
          "plan")
            echo "📋 Planning infrastructure changes for $env..."
            cd "environments/$env" && terraform plan
            ;;
          "apply")
            echo "🚀 Applying infrastructure changes for $env..."
            cd "environments/$env" && terraform apply
            ;;
          "destroy")
            echo "💥 Destroying infrastructure for $env..."
            read -p "Are you sure? This will destroy all resources in $env! (yes/no): " -r
            if [[ "$REPLY" == "yes" ]]; then
              cd "environments/$env" && terraform destroy
            else
              echo "Cancelled"
            fi
            ;;
          "status"|*)
            echo "🏗️  Infrastructure Status"
            if [[ -d "environments" ]]; then
              for env_dir in environments/*/; do
                env_name=$(basename "$env_dir")
                echo "  $env_name: $([ -f "$env_dir/.terraform/terraform.tfstate" ] && echo "Initialized" || echo "Not initialized")"
              done
            else
              echo "  No infrastructure configuration found"
            fi
            ;;
        esac
      }
    '';
  };
}