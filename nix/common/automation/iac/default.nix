{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.automation.iac;
in
{
  options.dotfiles.automation.iac = {
    enable = mkEnableOption "Infrastructure as Code tools integration";
    
    terraformSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Terraform support";
    };
    
    ansibleSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Ansible support";
    };
    
    pulumiaSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Pulumi support";
    };
    
    cdkSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable AWS CDK support";
    };
    
    crossplaneSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Crossplane support";
    };
    
    helmSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Helm support";
    };
    
    kustomizeSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Kustomize support";
    };
    
    validationTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable validation and linting tools";
    };
    
    secretsManagement = mkOption {
      type = types.bool;
      default = true;
      description = "Enable secrets management integration";
    };
    
    templatePath = mkOption {
      type = types.str;
      default = "$HOME/.config/iac-templates";
      description = "Path to IaC templates directory";
    };
  };

  config = mkIf cfg.enable {
    # Core IaC tools
    home.packages = with pkgs; [
      # Essential tools
      jq
      yq-go
      curl
      git
      
      # Terraform ecosystem
    ] ++ optionals cfg.terraformSupport [
      terraform
      terragrunt
      terraform-docs
      tflint
      tfsec
      terraformer
      terrascan
      checkov
    ] ++ optionals cfg.ansibleSupport [
      ansible
      ansible-lint
      # ansible-core  # Conflicts with ansible on some platforms
    ] ++ optionals cfg.pulumiaSupport [
      pulumi
      pulumictl
    ] ++ optionals cfg.cdkSupport [
      nodePackages.aws-cdk
      nodePackages.cdktf-cli
    ] ++ optionals cfg.helmSupport [
      kubernetes-helm
      helmfile
      helm-docs
    ] ++ optionals cfg.kustomizeSupport [
      kustomize
      kubectl
    ] ++ optionals cfg.validationTools [
      # Policy and validation
      open-policy-agent
      conftest
      kubeval
      
      # Security scanning
      trivy
      grype
      
      # YAML/JSON tools
      yamllint
      jsonlint
    ] ++ optionals cfg.secretsManagement [
      sops
      age
      gnupg
      vault
      sealed-secrets
    ];

    # Terraform configuration
    home.file.".terraformrc" = mkIf cfg.terraformSupport {
      text = ''
        # Terraform CLI configuration
        disable_checkpoint = true
        disable_checkpoint_signature = true
        
        # Plugin cache
        plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"
        
        # Credentials (managed via environment variables)
        # TF_CLI_CONFIG_FILE can override this
      '';
    };

    # Ansible configuration
    home.file.".ansible.cfg" = mkIf cfg.ansibleSupport {
      text = ''
        [defaults]
        host_key_checking = False
        retry_files_enabled = False
        inventory = ./inventory
        roles_path = ./roles:~/.ansible/roles:/etc/ansible/roles
        gathering = smart
        fact_caching = memory
        callback_whitelist = timer, profile_tasks
        
        [inventory]
        enable_plugins = host_list, script, auto, yaml, ini, toml
        
        [ssh_connection]
        ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=/tmp/ansible-ssh-%h-%p-%r
        pipelining = True
      '';
    };

    # IaC project templates
    home.file."${cfg.templatePath}" = {
      recursive = true;
      source = ./templates;
    };

    # Shell aliases for IaC tools
    programs.zsh.shellAliases = {
      # Terraform
      tf = mkIf cfg.terraformSupport "terraform";
      tfi = mkIf cfg.terraformSupport "terraform init";
      tfp = mkIf cfg.terraformSupport "terraform plan";
      tfa = mkIf cfg.terraformSupport "terraform apply";
      tfd = mkIf cfg.terraformSupport "terraform destroy";
      tfv = mkIf cfg.terraformSupport "terraform validate";
      tff = mkIf cfg.terraformSupport "terraform fmt";
      
      # Ansible
      ap = mkIf cfg.ansibleSupport "ansible-playbook";
      av = mkIf cfg.ansibleSupport "ansible-vault";
      ag = mkIf cfg.ansibleSupport "ansible-galaxy";
      
      # Kubernetes
      k = "kubectl";
      kgp = "kubectl get pods";
      kgs = "kubectl get services";
      kgd = "kubectl get deployments";
      kdp = "kubectl describe pod";
      kl = "kubectl logs";
      kex = "kubectl exec -it";
      
      # Helm
      h = mkIf cfg.helmSupport "helm";
      hi = mkIf cfg.helmSupport "helm install";
      hu = mkIf cfg.helmSupport "helm upgrade";
      hd = mkIf cfg.helmSupport "helm delete";
      hl = mkIf cfg.helmSupport "helm list";
    };

    # IaC project initialization script
    home.file."bin/iac-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Infrastructure as Code Project Initialization
        set -euo pipefail
        
        PROJECT_NAME="$1"
        IaC_TYPE="''${2:-terraform}"
        PROJECT_DIR="''${3:-./}"
        CLOUD_PROVIDER="''${4:-aws}"
        
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
        
        # Create project directory
        if [[ ! -d "$PROJECT_DIR" ]]; then
          mkdir -p "$PROJECT_DIR"
        fi
        
        cd "$PROJECT_DIR"
        
        log_info "Initializing $IaC_TYPE project: $PROJECT_NAME for $CLOUD_PROVIDER"
        
        case "$IaC_TYPE" in
          "terraform")
            # Create Terraform project structure
            mkdir -p {environments/{dev,staging,prod},modules,templates}
            
            # Main configuration
            cat > main.tf << 'EOF'
        # Main Terraform configuration for {{PROJECT_NAME}}
        terraform {
          required_version = ">= 1.0"
          
          required_providers {
            {{CLOUD_PROVIDER}} = {
              source  = "hashicorp/{{CLOUD_PROVIDER}}"
              version = "~> 5.0"
            }
          }
          
          # Backend configuration (uncomment and configure for remote state)
          # backend "s3" {
          #   bucket = "your-terraform-state-bucket"
          #   key    = "{{PROJECT_NAME}}/terraform.tfstate"
          #   region = "us-west-2"
          # }
        }
        
        # Provider configuration
        provider "{{CLOUD_PROVIDER}}" {
          region = var.aws_region
        }
        
        # Local values
        locals {
          project_name = "{{PROJECT_NAME}}"
          environment  = var.environment
          
          common_tags = {
            Project     = local.project_name
            Environment = local.environment
            ManagedBy   = "terraform"
            Owner       = var.owner
          }
        }
        EOF
            
            # Variables
            cat > variables.tf << 'EOF'
        # Variables for {{PROJECT_NAME}}
        variable "aws_region" {
          description = "AWS region"
          type        = string
          default     = "us-west-2"
        }
        
        variable "environment" {
          description = "Environment name"
          type        = string
          default     = "dev"
        }
        
        variable "owner" {
          description = "Project owner"
          type        = string
          default     = "infrastructure-team"
        }
        
        variable "project_name" {
          description = "Project name"
          type        = string
          default     = "{{PROJECT_NAME}}"
        }
        EOF
            
            # Outputs
            cat > outputs.tf << 'EOF'
        # Outputs for {{PROJECT_NAME}}
        output "project_info" {
          description = "Project information"
          value = {
            name        = local.project_name
            environment = local.environment
            region      = var.aws_region
          }
        }
        EOF
            
            # Environment-specific configs
            for env in dev staging prod; do
              cat > "environments/$env/terraform.tfvars" << EOF
        # Environment: $env
        environment = "$env"
        aws_region  = "us-west-2"
        owner       = "infrastructure-team"
        
        # Environment-specific variables
        EOF
            done
            
            # Terraform validation and formatting
            cat > validate.sh << 'EOF'
        #!/bin/bash
        set -e
        
        echo "🔍 Validating Terraform configuration..."
        
        # Format check
        if ! terraform fmt -check -recursive; then
          echo "❌ Terraform formatting issues found. Run 'terraform fmt -recursive' to fix."
          exit 1
        fi
        
        # Validate configuration
        terraform validate
        
        # Security scan with tfsec
        if command -v tfsec &> /dev/null; then
          tfsec .
        fi
        
        # Policy check with OPA if available
        if command -v conftest &> /dev/null && [[ -d policy ]]; then
          conftest verify --policy policy .
        fi
        
        echo "✅ Terraform validation completed successfully!"
        EOF
            chmod +x validate.sh
            
            # Replace placeholders
            sed -i.bak "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" *.tf validate.sh
            sed -i.bak "s/{{CLOUD_PROVIDER}}/$CLOUD_PROVIDER/g" *.tf
            rm -f *.bak
            
            log_success "Terraform project structure created"
            ;;
            
          "ansible")
            # Create Ansible project structure
            mkdir -p {playbooks,roles,inventory/{group_vars,host_vars},files,templates,vars}
            
            # Main playbook
            cat > playbooks/site.yml << 'EOF'
        ---
        # Main playbook for {{PROJECT_NAME}}
        - name: Configure infrastructure
          hosts: all
          become: yes
          gather_facts: yes
          
          vars:
            project_name: "{{PROJECT_NAME}}"
            
          pre_tasks:
            - name: Update package cache
              package:
                update_cache: yes
              when: ansible_os_family in ['Debian', 'RedHat']
          
          roles:
            - common
            - security
            
          post_tasks:
            - name: Verify deployment
              debug:
                msg: "Deployment completed for {{ project_name }}"
        EOF
            
            # Inventory
            cat > inventory/hosts.yml << 'EOF'
        ---
        all:
          children:
            web:
              hosts:
                web01:
                  ansible_host: 10.0.1.10
                web02:
                  ansible_host: 10.0.1.11
            database:
              hosts:
                db01:
                  ansible_host: 10.0.2.10
          vars:
            ansible_user: ubuntu
            ansible_ssh_private_key_file: ~/.ssh/id_rsa
        EOF
            
            # Group variables
            cat > inventory/group_vars/all.yml << 'EOF'
        ---
        # Global variables for {{PROJECT_NAME}}
        project_name: "{{PROJECT_NAME}}"
        environment: "{{ env | default('dev') }}"
        
        # Common packages
        common_packages:
          - htop
          - curl
          - git
          - vim
        
        # Security settings
        security_ssh_port: 22
        security_fail2ban_enabled: true
        EOF
            
            # Create basic roles
            for role in common security; do
              mkdir -p "roles/$role"/{tasks,handlers,vars,defaults,files,templates,meta}
              
              cat > "roles/$role/tasks/main.yml" << EOF
        ---
        # Tasks for $role role
        - name: Include $role tasks
          debug:
            msg: "Executing $role role for {{ project_name }}"
        EOF
              
              cat > "roles/$role/meta/main.yml" << EOF
        ---
        galaxy_info:
          author: Infrastructure Team
          description: $role role for $PROJECT_NAME
          min_ansible_version: 2.9
          platforms:
            - name: Ubuntu
              versions:
                - focal
                - jammy
        dependencies: []
        EOF
            done
            
            # Ansible configuration validation
            cat > validate.sh << 'EOF'
        #!/bin/bash
        set -e
        
        echo "🔍 Validating Ansible configuration..."
        
        # Syntax check
        ansible-playbook --syntax-check playbooks/site.yml
        
        # Lint check
        if command -v ansible-lint &> /dev/null; then
          ansible-lint playbooks/site.yml
        fi
        
        # Inventory validation
        ansible-inventory --list > /dev/null
        
        echo "✅ Ansible validation completed successfully!"
        EOF
            chmod +x validate.sh
            
            # Replace placeholders
            find . -name "*.yml" -o -name "*.yaml" | xargs sed -i.bak "s/{{PROJECT_NAME}}/$PROJECT_NAME/g"
            rm -f $(find . -name "*.bak")
            
            log_success "Ansible project structure created"
            ;;
            
          "kubernetes")
            # Create Kubernetes project structure
            mkdir -p {manifests/{base,overlays/{dev,staging,prod}},helm,policies,scripts}
            
            # Base Kustomization
            cat > manifests/base/kustomization.yaml << 'EOF'
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        
        metadata:
          name: {{PROJECT_NAME}}-base
        
        resources:
          - deployment.yaml
          - service.yaml
          - configmap.yaml
        
        commonLabels:
          app: {{PROJECT_NAME}}
          version: v1.0.0
        
        images:
          - name: app
            newTag: latest
        EOF
            
            # Base deployment
            cat > manifests/base/deployment.yaml << 'EOF'
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: {{PROJECT_NAME}}
        spec:
          replicas: 3
          selector:
            matchLabels:
              app: {{PROJECT_NAME}}
          template:
            metadata:
              labels:
                app: {{PROJECT_NAME}}
            spec:
              containers:
              - name: app
                image: app:latest
                ports:
                - containerPort: 8080
                env:
                - name: ENVIRONMENT
                  value: "production"
                resources:
                  requests:
                    memory: "64Mi"
                    cpu: "250m"
                  limits:
                    memory: "128Mi"
                    cpu: "500m"
        EOF
            
            # Environment overlays
            for env in dev staging prod; do
              cat > "manifests/overlays/$env/kustomization.yaml" << EOF
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        
        metadata:
          name: {{PROJECT_NAME}}-$env
        
        resources:
          - ../../base
        
        patchesStrategicMerge:
          - deployment-patch.yaml
        
        images:
          - name: app
            newTag: $env-latest
        EOF
              
              cat > "manifests/overlays/$env/deployment-patch.yaml" << EOF
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: {{PROJECT_NAME}}
        spec:
          replicas: $([ "$env" = "prod" ] && echo 5 || echo 2)
          template:
            spec:
              containers:
              - name: app
                env:
                - name: ENVIRONMENT
                  value: "$env"
        EOF
            done
            
            # Helm chart
            mkdir -p helm/{{PROJECT_NAME}}/{templates,charts}
            cat > helm/{{PROJECT_NAME}}/Chart.yaml << 'EOF'
        apiVersion: v2
        name: {{PROJECT_NAME}}
        description: A Helm chart for {{PROJECT_NAME}}
        type: application
        version: 0.1.0
        appVersion: "1.0.0"
        EOF
            
            # Replace placeholders
            find . -name "*.yaml" -o -name "*.yml" | xargs sed -i.bak "s/{{PROJECT_NAME}}/$PROJECT_NAME/g"
            rm -f $(find . -name "*.bak")
            
            log_success "Kubernetes project structure created"
            ;;
            
          *)
            log_error "Unsupported IaC type: $IaC_TYPE"
            exit 1
            ;;
        esac
        
        # Create common files
        cat > README.md << EOF
        # $PROJECT_NAME Infrastructure
        
        This project contains the Infrastructure as Code (IaC) configuration for $PROJECT_NAME using $IaC_TYPE.
        
        ## Getting Started
        
        ### Prerequisites
        
        - $IaC_TYPE installed
        - $CLOUD_PROVIDER CLI configured
        - Access to target infrastructure
        
        ### Quick Start
        
        1. Initialize the project:
           \`\`\`bash
           # For Terraform
           terraform init
           
           # For Ansible
           ansible-galaxy install -r requirements.yml
           
           # For Kubernetes
           kubectl apply -k manifests/overlays/dev
           \`\`\`
        
        2. Validate configuration:
           \`\`\`bash
           ./validate.sh
           \`\`\`
        
        3. Deploy infrastructure:
           \`\`\`bash
           # See specific deployment instructions below
           \`\`\`
        
        ## Project Structure
        
        \`\`\`
        $(tree -I '__pycache__|*.pyc|.terraform|.git' || find . -type d | head -20)
        \`\`\`
        
        ## Deployment
        
        ### Development Environment
        
        \`\`\`bash
        # Add environment-specific deployment commands
        \`\`\`
        
        ### Production Environment
        
        \`\`\`bash
        # Add production deployment commands
        \`\`\`
        
        ## Security
        
        - Secrets are managed via SOPS/Vault
        - Infrastructure follows security best practices
        - Regular security scanning with appropriate tools
        
        ## Monitoring
        
        - Infrastructure monitoring via CloudWatch/Prometheus
        - Logging aggregation via ELK/Loki
        - Alerting via PagerDuty/Slack
        
        ## Contributing
        
        1. Follow the established patterns
        2. Validate changes with \`./validate.sh\`
        3. Test in development environment first
        4. Document any new resources or variables
        
        EOF
        
        # Create .gitignore
        cat > .gitignore << 'EOF'
        # Terraform
        .terraform/
        *.tfstate
        *.tfstate.*
        *.tfplan
        *.tfvars.backup
        .terraformrc
        terraform.rc
        
        # Ansible
        *.retry
        .vault_pass
        
        # Kubernetes
        .kube/
        
        # IDE
        .vscode/
        .idea/
        
        # OS
        .DS_Store
        Thumbs.db
        
        # Logs
        *.log
        
        # Secrets
        secrets.yaml
        .env
        .env.local
        EOF
        
        # Initialize git repository
        if [[ ! -d .git ]]; then
          git init
          git add .
          git commit -m "Initial $IaC_TYPE infrastructure setup for $PROJECT_NAME"
          log_success "Git repository initialized"
        fi
        
        log_success "IaC project '$PROJECT_NAME' initialized successfully!"
        log_info "Next steps:"
        log_info "  1. cd $(pwd)"
        log_info "  2. ./validate.sh"
        log_info "  3. Review and customize the configuration"
        log_info "  4. Initialize and deploy your infrastructure"
      '';
    };

    # IaC validation and automation script
    home.file."bin/iac-validate" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # IaC Validation and Quality Assurance
        set -euo pipefail
        
        TARGET_DIR="''${1:-.}"
        VALIDATION_TYPE="''${2:-auto}"
        
        cd "$TARGET_DIR"
        
        echo "🔍 IaC Validation and Quality Check"
        echo "=================================="
        echo "Directory: $(pwd)"
        echo "Type: $VALIDATION_TYPE"
        echo ""
        
        # Auto-detect IaC type if not specified
        if [[ "$VALIDATION_TYPE" == "auto" ]]; then
          if [[ -f "main.tf" ]] || [[ -f "terraform.tf" ]]; then
            VALIDATION_TYPE="terraform"
          elif [[ -f "playbook.yml" ]] || [[ -f "site.yml" ]] || [[ -d "playbooks" ]]; then
            VALIDATION_TYPE="ansible"
          elif [[ -f "kustomization.yaml" ]] || [[ -f "kustomization.yml" ]]; then
            VALIDATION_TYPE="kubernetes"
          elif [[ -f "Chart.yaml" ]]; then
            VALIDATION_TYPE="helm"
          else
            echo "❌ Could not auto-detect IaC type"
            exit 1
          fi
          echo "🔍 Detected type: $VALIDATION_TYPE"
        fi
        
        ERRORS=0
        
        # Type-specific validation
        case "$VALIDATION_TYPE" in
          "terraform")
            echo "📋 Terraform Validation"
            echo "----------------------"
            
            # Format check
            if terraform fmt -check -recursive; then
              echo "✅ Terraform formatting is correct"
            else
              echo "❌ Terraform formatting issues found"
              ((ERRORS++))
            fi
            
            # Validation
            if terraform validate; then
              echo "✅ Terraform configuration is valid"
            else
              echo "❌ Terraform validation failed"
              ((ERRORS++))
            fi
            
            # Security scan
            ${if cfg.validationTools then ''
              if command -v tfsec &> /dev/null; then
                if tfsec --no-color .; then
                  echo "✅ Security scan passed"
                else
                  echo "⚠️  Security issues found"
                fi
              fi
              
              if command -v checkov &> /dev/null; then
                if checkov -d . --quiet; then
                  echo "✅ Policy compliance check passed"
                else
                  echo "⚠️  Policy violations found"
                fi
              fi
            '' else "echo '⚪ Security scanning disabled'"}
            ;;
            
          "ansible")
            echo "📋 Ansible Validation"
            echo "--------------------"
            
            # Find playbooks
            PLAYBOOKS=$(find . -name "*.yml" -o -name "*.yaml" | grep -E "(playbook|site|main)" | head -5)
            
            if [[ -n "$PLAYBOOKS" ]]; then
              for playbook in $PLAYBOOKS; do
                if ansible-playbook --syntax-check "$playbook"; then
                  echo "✅ $playbook syntax is correct"
                else
                  echo "❌ $playbook syntax check failed"
                  ((ERRORS++))
                fi
              done
            fi
            
            # Ansible lint
            ${if cfg.validationTools then ''
              if command -v ansible-lint &> /dev/null && [[ -n "$PLAYBOOKS" ]]; then
                for playbook in $PLAYBOOKS; do
                  if ansible-lint "$playbook"; then
                    echo "✅ $playbook lint check passed"
                  else
                    echo "⚠️  $playbook lint issues found"
                  fi
                done
              fi
            '' else "echo '⚪ Ansible linting disabled'"}
            ;;
            
          "kubernetes")
            echo "📋 Kubernetes Validation"
            echo "-----------------------"
            
            # Kustomize validation
            if command -v kustomize &> /dev/null; then
              if kustomize build . > /dev/null; then
                echo "✅ Kustomize build successful"
              else
                echo "❌ Kustomize build failed"
                ((ERRORS++))
              fi
            fi
            
            # Kubeval validation
            ${if cfg.validationTools then ''
              if command -v kubeval &> /dev/null; then
                if find . -name "*.yaml" -o -name "*.yml" | xargs kubeval; then
                  echo "✅ Kubernetes manifest validation passed"
                else
                  echo "❌ Kubernetes manifest validation failed"
                  ((ERRORS++))
                fi
              fi
            '' else "echo '⚪ Kubeval disabled'"}
            ;;
            
          "helm")
            echo "📋 Helm Validation"
            echo "-----------------"
            
            if helm lint .; then
              echo "✅ Helm chart lint passed"
            else
              echo "❌ Helm chart lint failed"
              ((ERRORS++))
            fi
            
            if helm template . > /dev/null; then
              echo "✅ Helm template rendering successful"
            else
              echo "❌ Helm template rendering failed"
              ((ERRORS++))
            fi
            ;;
        esac
        
        # General file validation
        echo ""
        echo "📋 General Validation"
        echo "-------------------"
        
        # YAML validation
        if command -v yamllint &> /dev/null; then
          if find . -name "*.yaml" -o -name "*.yml" | xargs yamllint -d relaxed; then
            echo "✅ YAML syntax validation passed"
          else
            echo "⚠️  YAML syntax issues found"
          fi
        fi
        
        # JSON validation
        if command -v jsonlint &> /dev/null; then
          if find . -name "*.json" | xargs -I {} sh -c 'jsonlint-php {} || exit 1'; then
            echo "✅ JSON syntax validation passed"
          else
            echo "❌ JSON syntax validation failed"
            ((ERRORS++))
          fi
        fi
        
        # Security scanning
        ${if cfg.validationTools then ''
          if command -v trivy &> /dev/null; then
            if trivy config .; then
              echo "✅ Configuration security scan passed"
            else
              echo "⚠️  Security vulnerabilities found"
            fi
          fi
        '' else ""}
        
        # Summary
        echo ""
        echo "📊 Validation Summary"
        echo "===================="
        
        if [[ $ERRORS -eq 0 ]]; then
          echo "✅ All validations passed successfully!"
          exit 0
        else
          echo "❌ $ERRORS validation errors found"
          exit 1
        fi
      '';
    };

    # Shell functions for IaC management
    programs.zsh.initContent = ''
      # IaC environment management
      iac-env() {
        local env="$1"
        if [[ -d "environments/$env" ]]; then
          echo "🔄 Switching to environment: $env"
          cd "environments/$env"
          if [[ -f "terraform.tfvars" ]]; then
            export TF_VAR_FILE="terraform.tfvars"
          fi
        else
          echo "❌ Environment '$env' not found"
        fi
      }
      
      # Quick IaC status
      iac-status() {
        echo "🏗️  Infrastructure as Code Status"
        echo "================================"
        
        # Detect project type
        if [[ -f "main.tf" ]]; then
          echo "📋 Type: Terraform"
          if terraform --version &> /dev/null; then
            echo "🔧 Version: $(terraform --version | head -1)"
          fi
          if [[ -f ".terraform.lock.hcl" ]]; then
            echo "🔒 State: Initialized"
          else
            echo "⚠️  State: Not initialized"
          fi
        elif [[ -f "site.yml" ]] || [[ -d "playbooks" ]]; then
          echo "📋 Type: Ansible"
          if ansible --version &> /dev/null; then
            echo "🔧 Version: $(ansible --version | head -1)"
          fi
        elif [[ -f "kustomization.yaml" ]]; then
          echo "📋 Type: Kubernetes (Kustomize)"
        fi
        
        echo "📁 Directory: $(pwd)"
        echo "🌿 Git: $(git branch --show-current 2>/dev/null || echo 'Not a git repository')"
      }
      
      # IaC deployment helper
      iac-deploy() {
        local env="''${1:-dev}"
        local action="''${2:-plan}"
        
        echo "🚀 IaC Deployment"
        echo "Environment: $env"
        echo "Action: $action"
        
        # Validation first
        if ! iac-validate .; then
          echo "❌ Validation failed. Aborting deployment."
          return 1
        fi
        
        # Environment-specific deployment
        if [[ -d "environments/$env" ]]; then
          cd "environments/$env"
        fi
        
        case "$action" in
          "plan")
            if [[ -f "main.tf" ]]; then
              terraform plan -var-file="terraform.tfvars"
            fi
            ;;
          "apply")
            if [[ -f "main.tf" ]]; then
              terraform apply -var-file="terraform.tfvars"
            elif [[ -f "site.yml" ]]; then
              ansible-playbook site.yml -i inventory
            fi
            ;;
          "destroy")
            if [[ -f "main.tf" ]]; then
              terraform destroy -var-file="terraform.tfvars"
            fi
            ;;
        esac
      }
    '';
  };
}