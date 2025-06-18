{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.automation.cloud;
in
{
  options.dotfiles.automation.cloud = {
    enable = mkEnableOption "Cloud provider integration";
    
    awsSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AWS tools and integration";
    };
    
    gcpSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Google Cloud Platform tools";
    };
    
    azureSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Microsoft Azure tools";
    };
    
    digitaloceanSupport = mkOption {
      type = types.bool;
      default = false;
      description = "Enable DigitalOcean tools";
    };
    
    multiCloudTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable multi-cloud management tools";
    };
    
    costManagement = mkOption {
      type = types.bool;
      default = true;
      description = "Enable cloud cost management tools";
    };
    
    securityTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable cloud security scanning tools";
    };
    
    backupTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable cloud backup and disaster recovery tools";
    };
  };

  config = mkIf cfg.enable {
    # Core cloud tools
    home.packages = with pkgs; [
      # Universal tools
      curl
      jq
      yq-go
      
      # AWS tools
    ] ++ optionals cfg.awsSupport [
      awscli2
      aws-vault
      aws-iam-authenticator
      eksctl
      aws-sam-cli
      # aws-cdk available as nodePackages.aws-cdk
      nodePackages.aws-cdk
      ssm-session-manager-plugin
    ] ++ optionals cfg.gcpSupport [
      google-cloud-sdk
      google-cloud-sql-proxy
    ] ++ optionals cfg.azureSupport [
      azure-cli
      azure-functions-core-tools
    ] ++ optionals cfg.digitaloceanSupport [
      doctl
    ] ++ optionals cfg.multiCloudTools [
      terraform
      pulumi
      crossplane-cli
    ] ++ optionals cfg.costManagement [
      # Cost management tools would be added here
      # Most are web-based or require specific installation
    ] ++ optionals cfg.securityTools [
      trivy
      checkov
      tfsec
    ] ++ optionals cfg.backupTools [
      restic
      rclone
    ];

    # AWS configuration
    home.file.".aws/config.template" = mkIf cfg.awsSupport {
      text = ''
        # AWS CLI configuration template
        # Copy to ~/.aws/config and customize
        
        [default]
        region = us-west-2
        output = json
        cli_pager = 
        
        [profile dev]
        region = us-west-2
        output = json
        
        [profile staging]
        region = us-west-2
        output = json
        
        [profile production]
        region = us-west-2
        output = json
        
        # SSO configuration example
        # [profile sso-dev]
        # sso_start_url = https://your-org.awsapps.com/start
        # sso_region = us-east-1
        # sso_account_id = 123456789012
        # sso_role_name = DeveloperAccess
        # region = us-west-2
        # output = json
      '';
    };

    # GCP configuration
    home.file.".config/gcloud/configurations/config_default.template" = mkIf cfg.gcpSupport {
      text = ''
        # Google Cloud SDK configuration template
        [core]
        account = your-email@example.com
        project = your-project-id
        
        [compute]
        region = us-central1
        zone = us-central1-a
        
        [container]
        cluster = your-cluster-name
        use_client_certificate = False
      '';
    };

    # Shell aliases for cloud tools
    programs.zsh.shellAliases = {
      # AWS shortcuts
      aws-whoami = mkIf cfg.awsSupport "aws sts get-caller-identity";
      aws-regions = mkIf cfg.awsSupport "aws ec2 describe-regions --query 'Regions[].RegionName' --output table";
      aws-profiles = mkIf cfg.awsSupport "aws configure list-profiles";
      
      # GCP shortcuts
      gcp-projects = mkIf cfg.gcpSupport "gcloud projects list";
      gcp-whoami = mkIf cfg.gcpSupport "gcloud auth list";
      gcp-config = mkIf cfg.gcpSupport "gcloud config list";
      
      # Azure shortcuts
      az-account = mkIf cfg.azureSupport "az account show";
      az-subscriptions = mkIf cfg.azureSupport "az account list --output table";
      
      # Multi-cloud
      cloud-status = "cloud-check-status";
    };

    # Cloud management scripts
    home.file."bin/cloud-check-status" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Cloud Provider Status Check
        set -euo pipefail
        
        echo "☁️  Cloud Provider Status Check"
        echo "==============================="
        
        ${if cfg.awsSupport then ''
          # AWS Status
          echo "🟠 AWS:"
          if command -v aws &> /dev/null; then
            if aws sts get-caller-identity &> /dev/null; then
              ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Unknown")
              USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null | cut -d'/' -f2 || echo "Unknown")
              REGION=$(aws configure get region 2>/dev/null || echo "Not set")
              echo "  ✅ Authenticated as: $USER"
              echo "  📋 Account: $ACCOUNT"
              echo "  🌍 Region: $REGION"
              
              # Check profile
              PROFILE=$(aws configure list-profiles | head -1 || echo "default")
              echo "  👤 Profile: $PROFILE"
            else
              echo "  ❌ Not authenticated"
            fi
          else
            echo "  ⚪ AWS CLI not installed"
          fi
        '' else ''
          echo "🟠 AWS: Disabled"
        ''}
        
        ${if cfg.gcpSupport then ''
          echo ""
          echo "🔵 Google Cloud:"
          if command -v gcloud &> /dev/null; then
            if gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
              ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
              PROJECT=$(gcloud config get-value project 2>/dev/null || echo "Not set")
              REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "Not set")
              echo "  ✅ Authenticated as: $ACCOUNT"
              echo "  📋 Project: $PROJECT"
              echo "  🌍 Region: $REGION"
            else
              echo "  ❌ Not authenticated"
            fi
          else
            echo "  ⚪ Google Cloud SDK not installed"
          fi
        '' else ''
          echo ""
          echo "🔵 Google Cloud: Disabled"
        ''}
        
        ${if cfg.azureSupport then ''
          echo ""
          echo "🔷 Microsoft Azure:"
          if command -v az &> /dev/null; then
            if az account show &> /dev/null; then
              ACCOUNT=$(az account show --query user.name --output tsv 2>/dev/null || echo "Unknown")
              SUBSCRIPTION=$(az account show --query name --output tsv 2>/dev/null || echo "Unknown")
              echo "  ✅ Authenticated as: $ACCOUNT"
              echo "  📋 Subscription: $SUBSCRIPTION"
            else
              echo "  ❌ Not authenticated"
            fi
          else
            echo "  ⚪ Azure CLI not installed"
          fi
        '' else ''
          echo ""
          echo "🔷 Microsoft Azure: Disabled"
        ''}
        
        ${if cfg.digitaloceanSupport then ''
          echo ""
          echo "🌊 DigitalOcean:"
          if command -v doctl &> /dev/null; then
            if doctl account get &> /dev/null; then
              EMAIL=$(doctl account get --format Email --no-header 2>/dev/null || echo "Unknown")
              echo "  ✅ Authenticated as: $EMAIL"
            else
              echo "  ❌ Not authenticated"
            fi
          else
            echo "  ⚪ doctl not installed"
          fi
        '' else ''
          echo ""
          echo "🌊 DigitalOcean: Disabled"
        ''}
        
        echo ""
        echo "🛠️  Multi-cloud Tools:"
        if command -v terraform &> /dev/null; then
          echo "  ✅ Terraform: $(terraform version | head -1)"
        else
          echo "  ⚪ Terraform: Not installed"
        fi
        
        if command -v pulumi &> /dev/null; then
          echo "  ✅ Pulumi: $(pulumi version)"
        else
          echo "  ⚪ Pulumi: Not installed"
        fi
      '';
    };

    # Cloud cost management script
    home.file."bin/cloud-costs" = mkIf cfg.costManagement {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Cloud Cost Management
        set -euo pipefail
        
        PROVIDER="''${1:-all}"
        PERIOD="''${2:-month}"
        
        echo "💰 Cloud Cost Analysis"
        echo "====================="
        echo "Provider: $PROVIDER"
        echo "Period: $PERIOD"
        echo ""
        
        case "$PROVIDER" in
          "aws"|"all")
            ${if cfg.awsSupport then ''
              if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
                echo "🟠 AWS Costs:"
                
                # Get current month costs
                START_DATE=$(date -d "$(date +%Y-%m-01)" +%Y-%m-%d)
                END_DATE=$(date +%Y-%m-%d)
                
                echo "  📅 Period: $START_DATE to $END_DATE"
                
                # Monthly costs by service
                aws ce get-cost-and-usage \
                  --time-period Start=$START_DATE,End=$END_DATE \
                  --granularity MONTHLY \
                  --metrics BlendedCost \
                  --group-by Type=DIMENSION,Key=SERVICE \
                  --query 'ResultsByTime[0].Groups[?Metrics.BlendedCost.Amount>`0`].[Keys[0],Metrics.BlendedCost.Amount]' \
                  --output table 2>/dev/null || echo "  ⚠️  Could not retrieve cost data"
                
                # Budget alerts if available
                aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) \
                  --query 'Budgets[].BudgetName' --output table 2>/dev/null && echo "  📊 Active budgets found" || echo "  ⚪ No budgets configured"
              else
                echo "🟠 AWS: Not available (authentication required)"
              fi
              echo ""
            '' else ''
              echo "🟠 AWS: Disabled"
              echo ""
            ''}
            ;;
        esac
        
        case "$PROVIDER" in
          "gcp"|"all")
            ${if cfg.gcpSupport then ''
              if command -v gcloud &> /dev/null && gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
                echo "🔵 Google Cloud Costs:"
                PROJECT=$(gcloud config get-value project 2>/dev/null)
                
                if [[ -n "$PROJECT" ]]; then
                  echo "  📋 Project: $PROJECT"
                  # Note: Billing data requires billing API and specific permissions
                  echo "  ℹ️  Use Google Cloud Console for detailed billing information"
                  echo "  🔗 https://console.cloud.google.com/billing"
                else
                  echo "  ⚠️  No project configured"
                fi
              else
                echo "🔵 Google Cloud: Not available (authentication required)"
              fi
              echo ""
            '' else ''
              echo "🔵 Google Cloud: Disabled"
              echo ""
            ''}
            ;;
        esac
        
        echo "💡 Cost Optimization Tips:"
        echo "  • Review unused resources regularly"
        echo "  • Set up billing alerts and budgets"
        echo "  • Use auto-scaling and scheduled shutdowns"
        echo "  • Consider reserved instances for stable workloads"
        echo "  • Monitor and optimize storage usage"
      '';
    };

    # Cloud security scanner
    home.file."bin/cloud-security-scan" = mkIf cfg.securityTools {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Cloud Security Scanning
        set -euo pipefail
        
        SCAN_TARGET="''${1:-.}"
        SCAN_TYPE="''${2:-all}"
        
        echo "🔒 Cloud Security Scanning"
        echo "========================="
        echo "Target: $SCAN_TARGET"
        echo "Type: $SCAN_TYPE"
        echo ""
        
        ISSUES=0
        
        # Terraform security scanning
        if [[ "$SCAN_TYPE" == "terraform" ]] || [[ "$SCAN_TYPE" == "all" ]]; then
          if find "$SCAN_TARGET" -name "*.tf" | head -1 &> /dev/null; then
            echo "📋 Terraform Security Scan:"
            
            # tfsec scan
            if command -v tfsec &> /dev/null; then
              if tfsec "$SCAN_TARGET" --no-color; then
                echo "  ✅ tfsec: No issues found"
              else
                echo "  ⚠️  tfsec: Issues detected"
                ((ISSUES++))
              fi
            fi
            
            # Checkov scan
            if command -v checkov &> /dev/null; then
              if checkov -d "$SCAN_TARGET" --quiet; then
                echo "  ✅ Checkov: No issues found"
              else
                echo "  ⚠️  Checkov: Issues detected"
                ((ISSUES++))
              fi
            fi
            
            echo ""
          fi
        fi
        
        # Container security scanning
        if [[ "$SCAN_TYPE" == "containers" ]] || [[ "$SCAN_TYPE" == "all" ]]; then
          if find "$SCAN_TARGET" -name "Dockerfile" | head -1 &> /dev/null; then
            echo "🐳 Container Security Scan:"
            
            # Trivy scan
            if command -v trivy &> /dev/null; then
              find "$SCAN_TARGET" -name "Dockerfile" | while read dockerfile; do
                echo "  📋 Scanning: $dockerfile"
                if trivy config "$dockerfile"; then
                  echo "  ✅ Trivy: No issues in $dockerfile"
                else
                  echo "  ⚠️  Trivy: Issues in $dockerfile"
                  ((ISSUES++))
                fi
              done
            fi
            
            echo ""
          fi
        fi
        
        # Kubernetes security scanning
        if [[ "$SCAN_TYPE" == "kubernetes" ]] || [[ "$SCAN_TYPE" == "all" ]]; then
          if find "$SCAN_TARGET" -name "*.yaml" -o -name "*.yml" | grep -v ".github" | head -1 &> /dev/null; then
            echo "☸️  Kubernetes Security Scan:"
            
            # Kubesec scan
            if command -v kubesec &> /dev/null; then
              find "$SCAN_TARGET" -name "*.yaml" -o -name "*.yml" | grep -E "(deployment|pod|service)" | head -5 | while read manifest; do
                echo "  📋 Scanning: $manifest"
                if kubesec scan "$manifest" | jq '.score' | grep -q '^[1-9]'; then
                  echo "  ✅ Kubesec: Good security score for $manifest"
                else
                  echo "  ⚠️  Kubesec: Security improvements needed for $manifest"
                fi
              done
            fi
            
            echo ""
          fi
        fi
        
        # AWS security scanning
        if [[ "$SCAN_TYPE" == "aws" ]] || [[ "$SCAN_TYPE" == "all" ]]; then
          ${if cfg.awsSupport then ''
            if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
              echo "🟠 AWS Security Check:"
              
              # Check for default VPC
              if aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text | grep -q "vpc-"; then
                echo "  ⚠️  Default VPC detected (consider using custom VPC)"
              else
                echo "  ✅ No default VPC in use"
              fi
              
              # Check for security groups with wide open access
              OPEN_SG=$(aws ec2 describe-security-groups --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]].GroupId' --output text)
              if [[ -n "$OPEN_SG" ]]; then
                echo "  ⚠️  Security groups with 0.0.0.0/0 access detected"
              else
                echo "  ✅ No overly permissive security groups found"
              fi
              
              # Check for IAM users without MFA
              if aws iam get-account-summary --query 'SummaryMap.UsersQuota' --output text | grep -q "[1-9]"; then
                echo "  ℹ️  IAM users detected - verify MFA is enabled"
              fi
              
              echo ""
            fi
          '' else ''
            echo "🟠 AWS: Security scanning disabled"
            echo ""
          ''}
        fi
        
        # Summary
        echo "📊 Security Scan Summary:"
        if [[ $ISSUES -eq 0 ]]; then
          echo "  ✅ No critical security issues found"
        else
          echo "  ⚠️  $ISSUES potential security issues detected"
          echo "  💡 Review the scan results and apply security best practices"
        fi
        
        echo ""
        echo "🔗 Security Resources:"
        echo "  • AWS Security Best Practices: https://aws.amazon.com/security/security-resources/"
        echo "  • CIS Benchmarks: https://www.cisecurity.org/cis-benchmarks/"
        echo "  • OWASP Cloud Security: https://owasp.org/www-project-cloud-security/"
      '';
    };

    # Shell functions for cloud management
    programs.zsh.initExtra = ''
      # AWS profile switching
      aws-profile() {
        if [[ -z "''${1:-}" ]]; then
          echo "Current AWS profile: ''${AWS_PROFILE:-default}"
          echo "Available profiles:"
          aws configure list-profiles
        else
          export AWS_PROFILE="$1"
          echo "Switched to AWS profile: $1"
        fi
      }
      
      # AWS region switching
      aws-region() {
        if [[ -z "''${1:-}" ]]; then
          echo "Current region: $(aws configure get region)"
        else
          aws configure set region "$1"
          echo "Switched to region: $1"
        fi
      }
      
      # Quick cloud resource listing
      cloud-resources() {
        local provider="''${1:-aws}"
        
        case "$provider" in
          "aws")
            ${if cfg.awsSupport then ''
              echo "🟠 AWS Resources:"
              echo "EC2 Instances:"
              aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType]' --output table
              echo ""
              echo "S3 Buckets:"
              aws s3 ls
            '' else ''
              echo "AWS support disabled"
            ''}
            ;;
          "gcp")
            ${if cfg.gcpSupport then ''
              echo "🔵 GCP Resources:"
              echo "Compute Instances:"
              gcloud compute instances list
              echo ""
              echo "Storage Buckets:"
              gcloud storage buckets list
            '' else ''
              echo "GCP support disabled"
            ''}
            ;;
        esac
      }
      
      # Cloud cost estimation
      cloud-estimate() {
        echo "💰 Cloud Cost Estimation"
        echo "======================="
        echo "Use cloud provider calculators:"
        echo "• AWS: https://calculator.aws/"
        echo "• GCP: https://cloud.google.com/products/calculator"
        echo "• Azure: https://azure.microsoft.com/en-us/pricing/calculator/"
      }
      
      # Quick backup
      cloud-backup() {
        local source="''${1:-.}"
        local destination="''${2:-s3://your-backup-bucket}"
        
        echo "☁️  Starting cloud backup..."
        
        ${if cfg.backupTools then ''
          if command -v rclone &> /dev/null; then
            rclone copy "$source" "$destination" --progress
          elif command -v aws &> /dev/null && [[ "$destination" == s3://* ]]; then
            aws s3 sync "$source" "$destination"
          else
            echo "No suitable backup tool found"
          fi
        '' else ''
          echo "Backup tools not enabled"
        ''}
      }
    '';
  };
}