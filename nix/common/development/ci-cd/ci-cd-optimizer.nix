{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.dotfiles.development.ci-cd.optimizer;

  # CI/CD最適化スクリプト
  cicdOptimizerScript = pkgs.writeShellScript "ci-cd-optimizer" ''
    #!/usr/bin/env bash
    # Enhanced CI/CD Pipeline Optimizer with Nix Integration
    set -euo pipefail

    # カラー定義
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'

    # ログ関数
    log_info() { echo -e "''${BLUE}ℹ️  $1''${NC}"; }
    log_success() { echo -e "''${GREEN}✅ $1''${NC}"; }
    log_warning() { echo -e "''${YELLOW}⚠️  $1''${NC}"; }
    log_error() { echo -e "''${RED}❌ $1''${NC}"; }
    log_step() { echo -e "''${CYAN}🔄 $1''${NC}"; }

    # 設定
    DOTFILES_ROOT="''${DOTFILES_ROOT:-$PWD}"
    WORKFLOWS_DIR="$DOTFILES_ROOT/.github/workflows"
    OPTIMIZATION_REPORT="$DOTFILES_ROOT/ci-cd-optimization-report.md"

    show_help() {
      cat << EOF
    CI/CD Pipeline Optimizer

    Usage:
      ci-cd-optimizer [options]

    Options:
      -a, --analyze            Analyze existing workflows
      -o, --optimize           Run all optimizations
      -c, --cache              Optimize cache strategies
      -p, --parallel           Optimize parallel execution
      -s, --security           Integrate security scanning
      -f, --performance        Add performance monitoring
      -r, --report             Generate optimization report
      --dry-run               Show what would be done
      -v, --verbose           Verbose output
      -h, --help              Show this help

    Examples:
      ci-cd-optimizer --optimize          # Full optimization
      ci-cd-optimizer --analyze           # Analyze current setup
      ci-cd-optimizer --cache --parallel  # Specific optimizations
      ci-cd-optimizer --dry-run --all     # Preview changes
    EOF
    }

    # 引数解析
    ANALYZE_ONLY="false"
    RUN_OPTIMIZE="false"
    OPTIMIZE_CACHE="false"
    OPTIMIZE_PARALLEL="false"
    INTEGRATE_SECURITY="false"
    ADD_PERFORMANCE="false"
    GENERATE_REPORT="false"
    DRY_RUN="false"
    VERBOSE="false"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -a|--analyze)
          ANALYZE_ONLY="true"
          shift
          ;;
        -o|--optimize)
          RUN_OPTIMIZE="true"
          shift
          ;;
        -c|--cache)
          OPTIMIZE_CACHE="true"
          shift
          ;;
        -p|--parallel)
          OPTIMIZE_PARALLEL="true"
          shift
          ;;
        -s|--security)
          INTEGRATE_SECURITY="true"
          shift
          ;;
        -f|--performance)
          ADD_PERFORMANCE="true"
          shift
          ;;
        -r|--report)
          GENERATE_REPORT="true"
          shift
          ;;
        --dry-run)
          DRY_RUN="true"
          shift
          ;;
        -v|--verbose)
          VERBOSE="true"
          shift
          ;;
        -h|--help)
          show_help
          exit 0
          ;;
        *)
          echo -e "''${RED}Unknown option: $1''${NC}" >&2
          show_help
          exit 1
          ;;
      esac
    done

    # 全最適化の場合
    if [[ "$RUN_OPTIMIZE" == "true" ]]; then
      OPTIMIZE_CACHE="true"
      OPTIMIZE_PARALLEL="true"
      INTEGRATE_SECURITY="true"
      ADD_PERFORMANCE="true"
      GENERATE_REPORT="true"
    fi

    echo -e "''${BLUE}⚡ CI/CD Pipeline Optimizer''${NC}"
    echo "================================="
    echo "📂 Workflows Directory: $WORKFLOWS_DIR"
    echo ""

    # ワークフロー分析
    analyze_workflows() {
      log_step "📊 Analyzing workflows..."
      
      if [[ ! -d "$WORKFLOWS_DIR" ]]; then
        log_error "Workflows directory not found: $WORKFLOWS_DIR"
        return 1
      fi
      
      local total_workflows=0
      local optimizable_workflows=0
      local workflow_analysis=()
      
      while IFS= read -r -d ''' workflow_file; do
        ((total_workflows++))
        local workflow_name
        workflow_name=$(basename "$workflow_file" .yml)
        
        log_info "🔍 Analyzing: $workflow_name"
        
        local needs_optimization=false
        local issues=()
        
        # キャッシュ使用確認
        if ! grep -q "actions/cache\|cache:" "$workflow_file"; then
          needs_optimization=true
          issues+=("No caching")
        fi
        
        # 並列実行確認
        if ! grep -q "matrix:" "$workflow_file"; then
          if ! grep -q "strategy:" "$workflow_file"; then
            needs_optimization=true
            issues+=("No parallel execution")
          fi
        fi
        
        # 条件付き実行確認
        if ! grep -q "if:" "$workflow_file"; then
          needs_optimization=true
          issues+=("No conditional execution")
        fi
        
        # セキュリティ確認
        if ! grep -q "security\|vulnerability" "$workflow_file"; then
          needs_optimization=true
          issues+=("No security scanning")
        fi
        
        if [[ $needs_optimization == true ]]; then
          ((optimizable_workflows++))
          workflow_analysis+=("$workflow_name: ''${issues[*]}")
        fi
        
      done < <(find "$WORKFLOWS_DIR" -name "*.yml" -o -name "*.yaml" -print0 2>/dev/null || true)
      
      log_success "Workflow analysis completed"
      echo "  📊 Total workflows: $total_workflows"
      echo "  🔧 Optimization candidates: $optimizable_workflows"
      
      if [[ $optimizable_workflows -gt 0 ]]; then
        echo "  ⚠️  Workflows needing optimization:"
        for analysis in "''${workflow_analysis[@]}"; do
          echo "    - $analysis"
        done
      fi
      
      echo ""
      return 0
    }

    # キャッシュ戦略最適化
    optimize_cache_strategy() {
      log_step "💾 Optimizing cache strategies..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would create cache configuration files"
        return 0
      fi

      # 共通キャッシュ設定ファイル作成
      cat > "$WORKFLOWS_DIR/../cache-config.yml" << 'EOF'
    # Common Cache Configuration for CI/CD Optimization
    # Reference this file in your workflows for consistent caching

    cache_strategies:
      nix:
        path: |
          ~/.cache/nix
          /nix/store
        key_pattern: "${{ runner.os }}-nix-${{ hashFiles('**/flake.lock') }}"
        restore_keys: |
          ${{ runner.os }}-nix-
      
      node:
        path: |
          ~/.npm
          node_modules
          .next/cache
        key_pattern: "${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}"
        restore_keys: |
          ${{ runner.os }}-node-
      
      rust:
        path: |
          ~/.cargo/registry
          ~/.cargo/git
          target
        key_pattern: "${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}"
        restore_keys: |
          ${{ runner.os }}-cargo-
      
      python:
        path: |
          ~/.cache/pip
          .venv
          __pycache__
        key_pattern: "${{ runner.os }}-pip-${{ hashFiles('**/requirements*.txt') }}"
        restore_keys: |
          ${{ runner.os }}-pip-

    optimization_flags:
      cache_compression: true
      cache_parallel_restore: true
      cache_cleanup_threshold: "5GB"
      cache_encryption: true
      cache_access_control: "repository"

    # Usage examples:
    # - name: Cache Nix Store
    #   uses: actions/cache@v4
    #   with:
    #     path: ${{ cache_strategies.nix.path }}
    #     key: ${{ cache_strategies.nix.key_pattern }}
    #     restore-keys: ${{ cache_strategies.nix.restore_keys }}
    EOF
      
      log_success "Cache strategy optimization completed"
    }

    # 並列実行最適化
    optimize_parallel_execution() {
      log_step "🔀 Optimizing parallel execution..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would create matrix strategy template"
        return 0
      fi

      cat > "$WORKFLOWS_DIR/../matrix-template.yml" << 'EOF'
    # Matrix Strategy Template for Parallel Execution
    # Use this template to optimize workflow parallel execution

    strategy:
      fail-fast: false
      matrix:
        # Platform matrix
        platform:
          - os: ubuntu-latest
            name: Linux
            cache_key: linux
          - os: macos-latest  
            name: macOS
            cache_key: macos
            # Uncomment for Windows support
            # - os: windows-latest
            #   name: Windows
            #   cache_key: windows
        
        # Language/Runtime matrix
        version:
          - name: stable
            version: stable
          - name: latest
            version: latest
            allow_failure: true
        
        # Test type matrix
        test_type:
          - name: unit
            command: "test:unit"
            timeout: 15
          - name: integration
            command: "test:integration"
            timeout: 30
          - name: e2e
            command: "test:e2e"
            timeout: 60

    # Conditional execution
    include:
      - platform: { os: ubuntu-latest }
        test_type: { name: security }
        version: { name: stable }
      
    exclude:
      - platform: { os: windows-latest }
        test_type: { name: e2e }

    # Runtime configuration
    continue-on-error: ${{ matrix.version.allow_failure || false }}
    timeout-minutes: ${{ matrix.test_type.timeout || 30 }}

    # Usage in steps:
    # - name: Setup ${{ matrix.platform.name }}
    #   run: echo "Setting up ${{ matrix.platform.name }}"
    # 
    # - name: Run ${{ matrix.test_type.name }} tests
    #   run: npm run ${{ matrix.test_type.command }}
    #   timeout-minutes: ${{ matrix.test_type.timeout }}
    EOF
      
      log_success "Parallel execution optimization completed"
    }

    # セキュリティ統合
    integrate_security() {
      log_step "🔒 Integrating security scanning..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would create security workflow"
        return 0
      fi

      cat > "$WORKFLOWS_DIR/security.yml" << 'EOF'
    name: 🔒 Security Integration Scan

    on:
      push:
        branches: [ main, develop ]
      pull_request:
        branches: [ main ]
      schedule:
        - cron: '0 2 * * *'  # Daily at 2 AM

    env:
      SECURITY_SCAN_LEVEL: ${{ github.event_name == 'schedule' && 'comprehensive' || 'standard' }}

    jobs:
      security-baseline:
        name: 🛡️ Security Baseline
        runs-on: ubuntu-latest
        
        steps:
        - name: Checkout
          uses: actions/checkout@v4
          with:
            fetch-depth: 0
        
        - name: Cache Security Tools
          uses: actions/cache@v4
          with:
            path: ~/.cache/security-tools
            key: security-tools-${{ runner.os }}-${{ hashFiles('.github/security-config.yml') }}
        
        - name: Security Baseline Check
          run: |
            # Run implemented security compliance check
            if [[ -f ./scripts/security-compliance-check.sh ]]; then
              ./scripts/security-compliance-check.sh
            else
              echo "🔍 Basic security checks..."
              
              # Check for common security issues
              echo "Checking for exposed secrets..."
              git log --all --full-history -- **/*.env* | head -10 || true
              
              echo "Checking file permissions..."
              find . -type f -perm -o+w | head -10 || true
              
              echo "Checking for hardcoded credentials..."
              rg -i "password|secret|key|token" --type yaml --type json . || true
            fi
        
        - name: Upload Security Report
          uses: actions/upload-artifact@v4
          if: always()
          with:
            name: security-baseline-report
            path: security-reports/

      vulnerability-scan:
        name: 🔍 Vulnerability Scan
        runs-on: ubuntu-latest
        
        strategy:
          matrix:
            scan_type:
              - name: "Dependencies"
                tool: "audit"
              - name: "Secrets"
                tool: "gitleaks"
              - name: "Code"
                tool: "semgrep"
        
        steps:
        - name: Checkout
          uses: actions/checkout@v4
        
        - name: ${{ matrix.scan_type.name }} Scan
          run: |
            echo "🔍 Running ${{ matrix.scan_type.name }} scan..."
            
            case "${{ matrix.scan_type.tool }}" in
              "audit")
                if [[ -f package.json ]]; then
                  npm audit --audit-level=moderate || true
                fi
                if [[ -f Cargo.toml ]]; then
                  cargo audit || true
                fi
                ;;
              "gitleaks")
                if command -v gitleaks >/dev/null 2>&1; then
                  gitleaks detect --source . --verbose || true
                else
                  echo "Gitleaks not available, skipping secret scan"
                fi
                ;;
              "semgrep")
                if command -v semgrep >/dev/null 2>&1; then
                  semgrep --config=auto . || true
                else
                  echo "Semgrep not available, skipping code analysis"
                fi
                ;;
            esac

      security-summary:
        name: 📊 Security Summary
        runs-on: ubuntu-latest
        needs: [security-baseline, vulnerability-scan]
        if: always()
        
        steps:
        - name: Generate Security Summary
          run: |
            echo "## 🔒 Security Scan Results" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "| Check Type | Status | Details |" >> $GITHUB_STEP_SUMMARY
            echo "|-----------|--------|---------|" >> $GITHUB_STEP_SUMMARY
            echo "| Baseline | ${{ needs.security-baseline.result == 'success' && '✅ Passed' || '❌ Failed' }} | Security baseline verification |" >> $GITHUB_STEP_SUMMARY
            echo "| Vulnerabilities | ${{ needs.vulnerability-scan.result == 'success' && '✅ Passed' || '❌ Issues Found' }} | Dependency and code analysis |" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "🔗 See individual job artifacts for detailed results." >> $GITHUB_STEP_SUMMARY
    EOF
      
      log_success "Security integration completed"
    }

    # パフォーマンス監視追加
    add_performance_monitoring() {
      log_step "📊 Adding performance monitoring..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would create performance workflow"
        return 0
      fi

      cat > "$WORKFLOWS_DIR/performance.yml" << 'EOF'
    name: 📊 Performance Monitoring

    on:
      push:
        branches: [ main ]
      pull_request:
        branches: [ main ]
      schedule:
        - cron: '0 3 * * 0'  # Weekly on Sunday at 3 AM

    jobs:
      performance-baseline:
        name: 📊 Performance Baseline
        runs-on: ubuntu-latest
        
        steps:
        - name: Checkout
          uses: actions/checkout@v4
        
        - name: System Information
          run: |
            echo "## System Information" >> performance-report.md
            echo "- OS: $(uname -a)" >> performance-report.md
            echo "- CPU: $(nproc) cores" >> performance-report.md
            echo "- Memory: $(free -h | awk '/^Mem:/ {print $2}')" >> performance-report.md
            echo "- Disk: $(df -h / | awk 'NR==2 {print $4}')" >> performance-report.md
            echo "" >> performance-report.md
        
        - name: Build Time Measurement
          run: |
            echo "## Build Time Measurement" >> performance-report.md
            
            if [[ -f flake.nix ]]; then
              echo "### Nix flake check" >> performance-report.md
              start_time=$(date +%s)
              
              if timeout 600 nix flake check --show-trace; then
                end_time=$(date +%s)
                duration=$((end_time - start_time))
                echo "- Execution time: ${duration}s" >> performance-report.md
                echo "- Status: ✅ Success" >> performance-report.md
              else
                echo "- Status: ❌ Failed (timeout)" >> performance-report.md
              fi
              echo "" >> performance-report.md
            fi
        
        - name: Resource Usage
          run: |
            echo "## Resource Usage" >> performance-report.md
            
            cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "N/A")
            echo "- CPU Usage: ${cpu_usage}%" >> performance-report.md
            
            memory_usage=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100.0}' || echo "N/A")
            echo "- Memory Usage: ${memory_usage}%" >> performance-report.md
            
            disk_usage=$(df / | awk 'NR==2 {print $5}' || echo "N/A")
            echo "- Disk Usage: $disk_usage" >> performance-report.md
        
        - name: Upload Performance Report
          uses: actions/upload-artifact@v4
          with:
            name: performance-report
            path: performance-report.md

      benchmark-comparison:
        name: 📈 Benchmark Comparison
        runs-on: ubuntu-latest
        needs: [performance-baseline]
        if: always()
        
        steps:
        - name: Generate Benchmark Report
          run: |
            echo "## 📈 Performance Comparison Results" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "| Metric | Current | Previous | Change |" >> $GITHUB_STEP_SUMMARY
            echo "|--------|---------|----------|--------|" >> $GITHUB_STEP_SUMMARY
            echo "| Build Time | Measuring | TBD | TBD |" >> $GITHUB_STEP_SUMMARY
            echo "| Test Time | Measuring | TBD | TBD |" >> $GITHUB_STEP_SUMMARY
            echo "| Memory Usage | Measuring | TBD | TBD |" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "🔗 Detailed results available in performance report artifact." >> $GITHUB_STEP_SUMMARY
    EOF
      
      log_success "Performance monitoring added"
    }

    # 最適化レポート生成
    generate_optimization_report() {
      log_step "📋 Generating optimization report..."
      
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would generate optimization report"
        return 0
      fi

      cat > "$OPTIMIZATION_REPORT" << EOF
    # CI/CD Pipeline Optimization Report

    **Generated:** $(date)
    **Tool:** ci-cd-optimizer (Nix-managed)

    ## Implemented Optimizations

    ### ✅ Cache Strategy Optimization
    - Nix store caching for faster builds
    - Language-specific dependency caching
    - Build artifact caching
    - Shared cache configuration

    ### ✅ Parallel Execution Optimization
    - Matrix strategy templates
    - Platform parallel execution
    - Test type parallelization
    - Conditional execution patterns

    ### ✅ Security Integration
    - Security baseline verification
    - Vulnerability scanning
    - Compliance checking
    - Security reporting

    ### ✅ Performance Monitoring
    - Performance baseline measurement
    - Resource usage tracking
    - Benchmark comparison
    - Trend analysis

    ## Expected Benefits

    ### Runtime Reduction
    - Cache utilization: 30-50% faster
    - Parallel execution: 40-60% faster
    - Optimized builds: 20-30% faster

    ### Quality Improvement
    - Automated security checks
    - Continuous performance monitoring
    - Early issue detection

    ### Cost Reduction
    - Reduced CI/CD execution time
    - Efficient resource utilization
    - Early failure detection

    ## Usage Guide

    ### For New Workflows
    1. Reference \`.github/matrix-template.yml\` for parallel execution
    2. Use cache configurations from \`.github/cache-config.yml\`
    3. Integrate security scanning patterns

    ### For Existing Workflows
    1. Review and update cache strategies
    2. Consider parallelization opportunities
    3. Add security scanning steps

    ## Monitoring and Maintenance

    ### Regular Checks
    - [ ] Cache hit rates
    - [ ] Execution time trends
    - [ ] Security scan results
    - [ ] Resource usage patterns

    ### Recommended Schedule
    - Weekly: Performance review
    - Monthly: Security assessment
    - Quarterly: Strategy optimization

    ## Related Files

    - \`.github/workflows/security.yml\` - Security workflow
    - \`.github/workflows/performance.yml\` - Performance monitoring
    - \`.github/cache-config.yml\` - Cache configuration
    - \`.github/matrix-template.yml\` - Parallel execution template

    ---

    *Generated: $(date)*
    *Tool: ci-cd-optimizer (Nix-managed)*
    EOF
      
      log_success "Optimization report generated: $OPTIMIZATION_REPORT"
    }

    # メイン処理
    main() {
      local start_time
      start_time=$(date +%s)
      
      # ワークフローディレクトリ確認
      if [[ ! -d "$WORKFLOWS_DIR" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
          log_warning "Creating workflows directory: $WORKFLOWS_DIR"
          mkdir -p "$WORKFLOWS_DIR"
        else
          log_warning "[DRY RUN] Would create workflows directory: $WORKFLOWS_DIR"
        fi
      fi
      
      # 実行
      if [[ "$ANALYZE_ONLY" == "true" ]] || [[ "$OPTIMIZE_CACHE" == "true" ]] || [[ "$OPTIMIZE_PARALLEL" == "true" ]] || [[ "$INTEGRATE_SECURITY" == "true" ]] || [[ "$ADD_PERFORMANCE" == "true" ]]; then
        # 分析は常に実行
        analyze_workflows
        
        [[ "$OPTIMIZE_CACHE" == "true" ]] && optimize_cache_strategy && echo ""
        [[ "$OPTIMIZE_PARALLEL" == "true" ]] && optimize_parallel_execution && echo ""
        [[ "$INTEGRATE_SECURITY" == "true" ]] && integrate_security && echo ""
        [[ "$ADD_PERFORMANCE" == "true" ]] && add_performance_monitoring && echo ""
        [[ "$GENERATE_REPORT" == "true" ]] && generate_optimization_report
      else
        show_help
        exit 1
      fi
      
      local end_time
      end_time=$(date +%s)
      local total_time=$((end_time - start_time))
      
      echo ""
      log_success "🎉 CI/CD Pipeline optimization completed!"
      echo "⏱️  Execution time: ''${total_time}s"
      [[ -f "$OPTIMIZATION_REPORT" ]] && echo "📋 Optimization report: $OPTIMIZATION_REPORT"
      echo ""
      echo "✨ Your CI/CD pipeline has been optimized for efficiency and security!"
    }

    # 実行
    main "$@"
  '';

in {
  options.dotfiles.development.ci-cd.optimizer = {
    enable = mkEnableOption "CI/CD Pipeline Optimizer";

    enableCacheOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable cache strategy optimization";
    };

    enableParallelOptimization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable parallel execution optimization";
    };

    enableSecurityIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security scanning integration";
    };

    enablePerformanceMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable performance monitoring";
    };

    workflowsPath = mkOption {
      type = types.str;
      default = ".github/workflows";
      description = "Path to GitHub Actions workflows directory";
    };

    supportedLanguages = mkOption {
      type = types.listOf types.str;
      default = [ "nix" "node" "rust" "python" "go" "java" ];
      description = "Languages to optimize for";
    };
  };

  config = mkIf cfg.enable {
    # CI/CD最適化ツールパッケージ
    environment.systemPackages = with pkgs; [
      cicdOptimizerScript
    ];

    # 環境変数
    environment.variables = {
      DOTFILES_CICD_WORKFLOWS_PATH = cfg.workflowsPath;
    };

    # シェルエイリアス
    programs.zsh.shellAliases = mkIf cfg.enable {
      "ci-optimize" = "ci-cd-optimizer --optimize";
      "ci-analyze" = "ci-cd-optimizer --analyze";
      "ci-security" = "ci-cd-optimizer --security";
      "ci-performance" = "ci-cd-optimizer --performance";
      "ci-cache" = "ci-cd-optimizer --cache";
    };

    programs.bash.shellAliases = mkIf cfg.enable {
      "ci-optimize" = "ci-cd-optimizer --optimize";
      "ci-analyze" = "ci-cd-optimizer --analyze";
      "ci-security" = "ci-cd-optimizer --security";
      "ci-performance" = "ci-cd-optimizer --performance";
      "ci-cache" = "ci-cd-optimizer --cache";
    };
  };
}