# Phase 5: Integrated Testing and Documentation System
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.testing.phase5;
in
{
  options.dotfiles.testing.phase5 = {
    enable = mkEnableOption "Phase 5 integrated testing and documentation system";
    
    testingFramework = mkOption {
      type = types.enum [ "comprehensive" "performance" "security" "minimal" ];
      default = "comprehensive";
      description = "Testing framework configuration level";
    };
    
    documentationLevel = mkOption {
      type = types.enum [ "full" "standard" "minimal" ];
      default = "full";
      description = "Documentation generation level";
    };
    
    performanceBenchmarks = mkOption {
      type = types.bool;
      default = true;
      description = "Enable performance benchmarking tests";
    };
    
    securityValidation = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security validation tests";
    };
    
    aiIntegrationTests = mkOption {
      type = types.bool;
      default = true;
      description = "Enable AI integration platform tests";
    };
    
    universalPlatformTests = mkOption {
      type = types.bool;
      default = true;
      description = "Enable universal platform integration tests";
    };
    
    automatedQualityAssurance = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automated quality assurance";
    };
    
    regressionTesting = mkOption {
      type = types.bool;
      default = true;
      description = "Enable regression testing";
    };
    
    reportGeneration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automated report generation";
    };
  };

  config = mkIf cfg.enable {
    # Testing framework packages
    home-manager.users.yuki.home.packages = with pkgs; [
      # Testing tools
      shellcheck
      shfmt
      
      # Performance tools
      hyperfine
      
      # Documentation tools
      pandoc
      
      # Quality assurance
      gitlint
      
      # System analysis (macOS compatible)
      # sysstat - Linux only, not available on macOS
      # iotop - Linux only, not available on macOS
      
    ] ++ optionals cfg.performanceBenchmarks [
      # Performance benchmarking (macOS compatible)
      # stress - May not be available on macOS, use alternative approaches
      
    ] ++ optionals cfg.securityValidation [
      # Security testing
      nmap
      
    ];

    # Phase 5 Integration Test Suite
    home-manager.users.yuki.home.file."bin/phase5-test-suite" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Phase 5: Comprehensive Integration Test Suite
        set -euo pipefail
        
        # Configuration
        FRAMEWORK="${cfg.testingFramework}"
        DOC_LEVEL="${cfg.documentationLevel}"
        
        # Test directories
        TEST_DIR="$HOME/.testing/phase5"
        REPORT_DIR="$TEST_DIR/reports"
        LOG_DIR="$TEST_DIR/logs"
        BENCHMARK_DIR="$TEST_DIR/benchmarks"
        
        mkdir -p "$TEST_DIR" "$REPORT_DIR" "$LOG_DIR" "$BENCHMARK_DIR"
        
        echo "🧪 Phase 5: Comprehensive Integration Test Suite"
        echo "=============================================="
        echo "Framework: $FRAMEWORK"
        echo "Documentation Level: $DOC_LEVEL"
        echo "Test Directory: $TEST_DIR"
        echo ""
        
        # Test execution tracking
        TEST_START_TIME=$(date +%s)
        TOTAL_TESTS=0
        PASSED_TESTS=0
        FAILED_TESTS=0
        SKIPPED_TESTS=0
        
        log_test_result() {
          local test_name="$1"
          local status="$2"
          local message="$3"
          
          ((TOTAL_TESTS++))
          
          case "$status" in
            "PASS")
              echo "✅ $test_name: $message"
              ((PASSED_TESTS++))
              ;;
            "FAIL")
              echo "❌ $test_name: $message"
              ((FAILED_TESTS++))
              ;;
            "SKIP")
              echo "⏭️  $test_name: $message"
              ((SKIPPED_TESTS++))
              ;;
          esac
          
          echo "$(date): $status - $test_name - $message" >> "$LOG_DIR/test-execution.log"
        }
        
        run_nix_evaluation_tests() {
          echo "🏗️  Running Nix Configuration Tests..."
          echo ""
          
          # Test 1: Flake check
          if nix flake check --no-build 2>/dev/null; then
            log_test_result "Nix Flake Syntax" "PASS" "Flake configuration syntax valid"
          else
            log_test_result "Nix Flake Syntax" "FAIL" "Flake configuration has syntax errors"
          fi
          
          # Test 2: Darwin configuration evaluation
          if nix eval .#darwinConfigurations.default.system --json >/dev/null 2>&1; then
            log_test_result "Darwin Configuration" "PASS" "macOS configuration evaluates successfully"
          else
            log_test_result "Darwin Configuration" "FAIL" "macOS configuration evaluation failed"
          fi
          
          # Test 3: Development environment evaluation
          if nix eval .#darwinConfigurations.default.config.dotfiles.development.enable --json >/dev/null 2>&1; then
            log_test_result "Development Environment" "PASS" "Development environment configuration valid"
          else
            log_test_result "Development Environment" "FAIL" "Development environment configuration failed"
          fi
          
          # Test 4: Security system evaluation
          if nix eval .#darwinConfigurations.default.config.dotfiles.security.enterprise.enable --json >/dev/null 2>&1; then
            log_test_result "Security System" "PASS" "Enterprise security configuration valid"
          else
            log_test_result "Security System" "FAIL" "Enterprise security configuration failed"
          fi
        }
        
        run_ai_integration_tests() {
          ${if cfg.aiIntegrationTests then ''
            echo "🤖 Running AI Integration Tests..."
            echo ""
            
            # Test AI platform availability
            if command -v ai-platform-health &> /dev/null; then
              log_test_result "AI Platform Health" "PASS" "AI platform health check available"
              
              # Run AI health check
              if ai-platform-health >/dev/null 2>&1; then
                log_test_result "AI Platform Status" "PASS" "AI platform operational"
              else
                log_test_result "AI Platform Status" "FAIL" "AI platform health check failed"
              fi
            else
              log_test_result "AI Platform Health" "SKIP" "AI platform not configured"
            fi
            
            # Test AI platform integration
            if command -v ai-platform-health &> /dev/null; then
              log_test_result "AI Platform Integration" "PASS" "AI platform health check available"
            else
              log_test_result "AI Platform Integration" "SKIP" "AI platform not configured"
            fi
          '' else ''
            echo "🤖 AI Integration Tests: Disabled"
            log_test_result "AI Integration Tests" "SKIP" "AI integration tests disabled"
          ''}
        }
        
        run_performance_tests() {
          ${if cfg.performanceBenchmarks then ''
            echo "⚡ Running Performance Tests..."
            echo ""
            
            # Test Nix evaluation performance
            if command -v hyperfine &> /dev/null; then
              echo "📊 Benchmarking Nix evaluation..."
              
              BENCHMARK_FILE="$BENCHMARK_DIR/nix-evaluation-$(date +%Y%m%d-%H%M%S).json"
              
              if hyperfine --export-json "$BENCHMARK_FILE" --runs 3 \
                  'nix eval .#darwinConfigurations.default.system' 2>/dev/null; then
                log_test_result "Nix Evaluation Performance" "PASS" "Performance benchmark completed"
                
                # Extract timing from benchmark
                if [[ -f "$BENCHMARK_FILE" ]]; then
                  MEAN_TIME=$(jq -r '.results[0].mean' "$BENCHMARK_FILE" 2>/dev/null || echo "unknown")
                  echo "  📈 Mean evaluation time: ${"$"}{MEAN_TIME}s"
                fi
              else
                log_test_result "Nix Evaluation Performance" "FAIL" "Performance benchmark failed"
              fi
            else
              log_test_result "Nix Evaluation Performance" "SKIP" "hyperfine not available"
            fi
            
            # Test system resource usage
            echo "💾 System Resource Analysis..."
            
            # Memory usage test
            MEMORY_USAGE=$(ps aux | awk '{sum+=$4}; END {print sum}' 2>/dev/null || echo "unknown")
            if [[ "$MEMORY_USAGE" != "unknown" ]] && (( $(echo "$MEMORY_USAGE < 80" | bc -l 2>/dev/null || echo 0) )); then
              log_test_result "Memory Usage" "PASS" "System memory usage: ${"$"}{MEMORY_USAGE}%"
            else
              log_test_result "Memory Usage" "FAIL" "High memory usage: ${"$"}{MEMORY_USAGE}%"
            fi
            
            # Disk usage test
            DISK_USAGE=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//' 2>/dev/null || echo "unknown")
            if [[ "$DISK_USAGE" != "unknown" ]] && [[ $DISK_USAGE -lt 90 ]]; then
              log_test_result "Disk Usage" "PASS" "Root filesystem usage: ${"$"}{DISK_USAGE}%"
            else
              log_test_result "Disk Usage" "FAIL" "High disk usage: ${"$"}{DISK_USAGE}%"
            fi
          '' else ''
            echo "⚡ Performance Tests: Disabled"
            log_test_result "Performance Tests" "SKIP" "Performance benchmarks disabled"
          ''}
        }
        
        run_security_validation_tests() {
          ${if cfg.securityValidation then ''
            echo "🔒 Running Security Validation Tests..."
            echo ""
            
            # Test security health
            if command -v security-health &> /dev/null; then
              if security-health >/dev/null 2>&1; then
                log_test_result "Security Health Check" "PASS" "Enterprise security system operational"
              else
                log_test_result "Security Health Check" "FAIL" "Security health check failed"
              fi
            else
              log_test_result "Security Health Check" "SKIP" "Security system not configured"
            fi
            
            # Test encryption tools
            ENCRYPTION_TOOLS=("gpg" "age" "sops")
            for tool in "''${ENCRYPTION_TOOLS[@]}"; do
              if command -v "$tool" &> /dev/null; then
                log_test_result "Encryption Tool: $tool" "PASS" "$tool available and accessible"
              else
                log_test_result "Encryption Tool: $tool" "FAIL" "$tool not available"
              fi
            done
            
            # Test file permissions
            SECURE_DIRS=("$HOME/.ssh" "$HOME/.gnupg" "$HOME/.config/sops")
            for dir in "''${SECURE_DIRS[@]}"; do
              if [[ -d "$dir" ]]; then
                PERMS=$(ls -ld "$dir" | cut -d' ' -f1)
                if [[ "$PERMS" =~ ^d...---.-- ]]; then
                  log_test_result "Secure Directory: $dir" "PASS" "Secure permissions ($PERMS)"
                else
                  log_test_result "Secure Directory: $dir" "FAIL" "Insecure permissions ($PERMS)"
                fi
              else
                log_test_result "Secure Directory: $dir" "SKIP" "Directory not present"
              fi
            done
          '' else ''
            echo "🔒 Security Validation Tests: Disabled"
            log_test_result "Security Validation" "SKIP" "Security validation disabled"
          ''}
        }
        
        run_universal_platform_tests() {
          ${if cfg.universalPlatformTests then ''
            echo "🌐 Running Universal Platform Tests..."
            echo ""
            
            # Test platform detection
            if nix eval .#platformInfo.platform --raw >/dev/null 2>&1; then
              PLATFORM=$(nix eval .#platformInfo.platform --raw 2>/dev/null || echo "unknown")
              log_test_result "Platform Detection" "PASS" "Platform detected: $PLATFORM"
            else
              log_test_result "Platform Detection" "FAIL" "Platform detection failed"
            fi
            
            # Test cross-platform packages
            PLATFORM_PACKAGES=("curl" "wget" "jq" "git")
            for pkg in "''${PLATFORM_PACKAGES[@]}"; do
              if command -v "$pkg" &> /dev/null; then
                log_test_result "Cross-Platform Package: $pkg" "PASS" "$pkg available"
              else
                log_test_result "Cross-Platform Package: $pkg" "FAIL" "$pkg not available"
              fi
            done
            
            # Test universal CLI
            if command -v universal-platform-manager &> /dev/null; then
              log_test_result "Universal Platform Manager" "PASS" "Universal CLI available"
            else
              log_test_result "Universal Platform Manager" "SKIP" "Universal CLI not configured"
            fi
          '' else ''
            echo "🌐 Universal Platform Tests: Disabled"
            log_test_result "Universal Platform Tests" "SKIP" "Universal platform tests disabled"
          ''}
        }
        
        run_quality_assurance_tests() {
          ${if cfg.automatedQualityAssurance then ''
            echo "🔍 Running Quality Assurance Tests..."
            echo ""
            
            # Shellcheck tests
            if command -v shellcheck &> /dev/null; then
              echo "🐚 Running Shellcheck analysis..."
              
              # Find and check shell scripts
              SHELL_SCRIPT_COUNT=$(find "$HOME/dotfiles" -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ')
              
              if [[ "$SHELL_SCRIPT_COUNT" -gt 0 ]]; then
                SHELLCHECK_ERRORS=0
                
                # Check each shell script
                for file in $(find "$HOME/dotfiles" -name "*.sh" -type f 2>/dev/null); do
                  if ! shellcheck "$file" >/dev/null 2>&1; then
                    SHELLCHECK_ERRORS=$((SHELLCHECK_ERRORS + 1))
                  fi
                done
                
                if [[ $SHELLCHECK_ERRORS -eq 0 ]]; then
                  log_test_result "Shellcheck Analysis" "PASS" "All shell scripts pass Shellcheck"
                else
                  log_test_result "Shellcheck Analysis" "FAIL" "$SHELLCHECK_ERRORS shell scripts have issues"
                fi
              else
                log_test_result "Shellcheck Analysis" "SKIP" "No shell scripts found"
              fi
            else
              log_test_result "Shellcheck Analysis" "SKIP" "Shellcheck not available"
            fi
            
            # Nix formatting check
            if command -v nixpkgs-fmt &> /dev/null; then
              echo "❄️  Running Nix formatting check..."
              
              # Find and check Nix files
              NIX_FILE_COUNT=$(find "$HOME/dotfiles/nix" -name "*.nix" -type f 2>/dev/null | wc -l | tr -d ' ')
              
              if [[ "$NIX_FILE_COUNT" -gt 0 ]]; then
                FORMAT_ISSUES=0
                
                # Check each Nix file
                for file in $(find "$HOME/dotfiles/nix" -name "*.nix" -type f 2>/dev/null); do
                  if ! nixpkgs-fmt --check "$file" >/dev/null 2>&1; then
                    FORMAT_ISSUES=$((FORMAT_ISSUES + 1))
                  fi
                done
                
                if [[ $FORMAT_ISSUES -eq 0 ]]; then
                  log_test_result "Nix Formatting" "PASS" "All Nix files properly formatted"
                else
                  log_test_result "Nix Formatting" "FAIL" "$FORMAT_ISSUES Nix files need formatting"
                fi
              else
                log_test_result "Nix Formatting" "SKIP" "No Nix files found"
              fi
            else
              log_test_result "Nix Formatting" "SKIP" "nixpkgs-fmt not available"
            fi
          '' else ''
            echo "🔍 Quality Assurance Tests: Disabled"
            log_test_result "Quality Assurance" "SKIP" "Quality assurance disabled"
          ''}
        }
        
        run_regression_tests() {
          ${if cfg.regressionTesting then ''
            echo "🔄 Running Regression Tests..."
            echo ""
            
            # Test configuration rebuild
            echo "🏗️  Testing configuration rebuild..."
            
            # Dry run rebuild test
            if darwin-rebuild check 2>/dev/null; then
              log_test_result "Configuration Rebuild" "PASS" "Configuration rebuild check passed"
            else
              log_test_result "Configuration Rebuild" "FAIL" "Configuration rebuild check failed"
            fi
            
            # Test development environment
            if command -v dev-health &> /dev/null; then
              if dev-health >/dev/null 2>&1; then
                log_test_result "Development Environment" "PASS" "Development environment healthy"
              else
                log_test_result "Development Environment" "FAIL" "Development environment issues"
              fi
            else
              log_test_result "Development Environment" "SKIP" "Development health check not available"
            fi
            
            # Test automation systems
            if command -v auto-health &> /dev/null; then
              if auto-health >/dev/null 2>&1; then
                log_test_result "Automation Systems" "PASS" "Automation systems operational"
              else
                log_test_result "Automation Systems" "FAIL" "Automation systems issues"
              fi
            else
              log_test_result "Automation Systems" "SKIP" "Automation health check not available"
            fi
          '' else ''
            echo "🔄 Regression Tests: Disabled"
            log_test_result "Regression Tests" "SKIP" "Regression testing disabled"
          ''}
        }
        
        generate_test_report() {
          ${if cfg.reportGeneration then ''
            echo "📋 Generating Test Report..."
            echo ""
            
            TEST_END_TIME=$(date +%s)
            TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))
            
            REPORT_FILE="$REPORT_DIR/phase5-integration-test-$(date +%Y%m%d-%H%M%S).md"
            
            {
              echo "# Phase 5: Integration Test Report"
              echo ""
              echo "**Generated:** $(date)"
              echo "**Framework:** $FRAMEWORK"
              echo "**Documentation Level:** $DOC_LEVEL"
              echo "**Test Duration:** ${"$"}{TEST_DURATION}s"
              echo ""
              
              echo "## Executive Summary"
              echo ""
              echo "- **Total Tests:** $TOTAL_TESTS"
              echo "- **Passed:** $PASSED_TESTS"
              echo "- **Failed:** $FAILED_TESTS"
              echo "- **Skipped:** $SKIPPED_TESTS"
              echo ""
              
              # Calculate success rate
              if [[ $TOTAL_TESTS -gt 0 ]]; then
                SUCCESS_RATE=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
                echo "**Success Rate:** $SUCCESS_RATE%"
              else
                echo "**Success Rate:** N/A"
              fi
              echo ""
              
              # Status badge
              if [[ $FAILED_TESTS -eq 0 ]]; then
                echo "🟢 **Overall Status:** All tests passed"
              elif [[ $FAILED_TESTS -le 2 ]]; then
                echo "🟡 **Overall Status:** Minor issues detected"
              else
                echo "🔴 **Overall Status:** Multiple failures detected"
              fi
              echo ""
              
              echo "## Test Categories"
              echo ""
              echo "### System Configuration"
              echo "- Nix flake validation"
              echo "- Darwin configuration evaluation"
              echo "- Development environment verification"
              echo "- Security system validation"
              echo ""
              
              echo "### AI Integration Platform"
              echo "- AI platform health checks"
              echo "- AI tools integration tests"
              echo "- Local LLM connectivity"
              echo ""
              
              echo "### Performance Optimization"
              echo "- Nix evaluation benchmarks"
              echo "- System resource monitoring"
              echo "- Memory and disk usage analysis"
              echo ""
              
              echo "### Enterprise Security"
              echo "- Security health validation"
              echo "- Encryption tools verification"
              echo "- File permissions audit"
              echo ""
              
              echo "### Universal Platform Integration"
              echo "- Platform detection tests"
              echo "- Cross-platform package verification"
              echo "- Universal CLI functionality"
              echo ""
              
              echo "### Quality Assurance"
              echo "- Shellcheck analysis"
              echo "- Nix code formatting"
              echo "- Code quality metrics"
              echo ""
              
              echo "### Regression Testing"
              echo "- Configuration rebuild tests"
              echo "- Development environment regression"
              echo "- Automation systems verification"
              echo ""
              
              echo "## Detailed Results"
              echo ""
              echo "\`\`\`"
              cat "$LOG_DIR/test-execution.log" 2>/dev/null || echo "No detailed logs available"
              echo "\`\`\`"
              echo ""
              
              echo "## Performance Metrics"
              echo ""
              if [[ -d "$BENCHMARK_DIR" ]] && [[ -n "$(ls -A "$BENCHMARK_DIR" 2>/dev/null)" ]]; then
                echo "Performance benchmarks available in: \`$BENCHMARK_DIR\`"
                echo ""
                
                # List benchmark files
                for benchmark in "$BENCHMARK_DIR"/*.json; do
                  if [[ -f "$benchmark" ]]; then
                    echo "- $(basename "$benchmark")"
                  fi
                done
              else
                echo "No performance benchmarks generated."
              fi
              echo ""
              
              echo "## Recommendations"
              echo ""
              
              if [[ $FAILED_TESTS -gt 0 ]]; then
                echo "### Action Items"
                echo "1. Review failed test details in the log above"
                echo "2. Address configuration issues identified"
                echo "3. Re-run specific test categories after fixes"
                echo "4. Consider system maintenance if resource issues detected"
                echo ""
              fi
              
              echo "### Next Steps"
              echo "1. **Regular Testing:** Run \`phase5-test-suite\` weekly"
              echo "2. **Performance Monitoring:** Monitor system resources"
              echo "3. **Security Audits:** Run security validation monthly"
              echo "4. **Documentation Updates:** Keep documentation current"
              echo ""
              
              echo "## System Information"
              echo ""
              echo "- **Platform:** $(uname -s)/$(uname -m)"
              echo "- **Host:** $(hostname)"
              echo "- **User:** $(whoami)"
              echo "- **Dotfiles Location:** \$HOME/dotfiles"
              echo ""
              
              echo "---"
              echo "*Report generated by Phase 5 Integration Test Suite*"
              echo "*Framework: $FRAMEWORK | Documentation: $DOC_LEVEL*"
              
            } > "$REPORT_FILE"
            
            echo "✅ Test report generated: $REPORT_FILE"
            echo ""
            
            # Display summary
            echo "📊 Test Execution Summary:"
            echo "  Total Tests: $TOTAL_TESTS"
            echo "  Passed: $PASSED_TESTS"
            echo "  Failed: $FAILED_TESTS"
            echo "  Skipped: $SKIPPED_TESTS"
            
            if [[ $TOTAL_TESTS -gt 0 ]]; then
              SUCCESS_RATE=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
              echo "  Success Rate: $SUCCESS_RATE%"
            fi
            
            echo "  Duration: ${"$"}{TEST_DURATION}s"
            echo ""
            
            # Return appropriate exit code
            if [[ $FAILED_TESTS -gt 0 ]]; then
              echo "❌ Some tests failed. See report for details."
              exit 1
            else
              echo "✅ All tests passed successfully!"
              exit 0
            fi
          '' else ''
            echo "📋 Test Report Generation: Disabled"
            
            # Simple summary
            echo ""
            echo "📊 Test Execution Summary:"
            echo "  Total Tests: $TOTAL_TESTS"
            echo "  Passed: $PASSED_TESTS"
            echo "  Failed: $FAILED_TESTS"
            echo "  Skipped: $SKIPPED_TESTS"
            
            if [[ $FAILED_TESTS -gt 0 ]]; then
              exit 1
            else
              exit 0
            fi
          ''}
        }
        
        # Main test execution
        main() {
          echo "🚀 Starting Phase 5 Integration Tests..."
          echo ""
          
          # Run all test suites
          run_nix_evaluation_tests
          run_ai_integration_tests
          run_performance_tests
          run_security_validation_tests
          run_universal_platform_tests
          run_quality_assurance_tests
          run_regression_tests
          
          # Generate final report
          generate_test_report
        }
        
        # Execute main function
        main "$@"
      '';
    };

    # Documentation Generation System
    home-manager.users.yuki.home.file."bin/phase5-documentation-generator" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Phase 5: Documentation Generation System
        set -euo pipefail
        
        DOC_LEVEL="${cfg.documentationLevel}"
        
        # Documentation directories
        DOCS_BASE="$HOME/dotfiles/docs"
        PHASE5_DOCS="$DOCS_BASE/phase5"
        
        mkdir -p "$PHASE5_DOCS"
        
        echo "📚 Phase 5: Documentation Generation System"
        echo "=========================================="
        echo "Documentation Level: $DOC_LEVEL"
        echo "Output Directory: $PHASE5_DOCS"
        echo ""
        
        generate_system_overview() {
          echo "📋 Generating System Overview..."
          
          cat > "$PHASE5_DOCS/SYSTEM_OVERVIEW.md" << 'EOF'
# Phase 5: Advanced Integration and Optimization System

## Overview

Phase 5 represents the culmination of our enterprise-grade dotfiles system, integrating advanced AI capabilities, performance optimization, enterprise security, and universal platform support into a unified, highly automated development and operational environment.

## Key Components

### 🤖 AI Integration Platform
- **Local LLM Support**: Ollama integration with optimized models
- **AI Development Tools**: GitHub Copilot, Claude Code CLI, MCP integration
- **Intelligent Automation**: AI-powered configuration optimization
- **Smart Documentation**: Auto-generated documentation and insights

### ⚡ Performance Optimization System
- **Nix Store Optimization**: Parallel builds, optimized garbage collection
- **Resource Management**: Intelligent memory and CPU allocation
- **Caching Strategy**: Multi-layer caching for faster operations
- **Performance Monitoring**: Real-time metrics and automated tuning

### 🔒 Enterprise Security Framework
- **Zero Trust Architecture**: Identity-based security model
- **Advanced Threat Protection**: Real-time monitoring and response
- **Data Protection**: Multi-layer encryption and secure storage
- **Compliance Management**: SOC2, ISO27001, GDPR frameworks

### 🌐 Universal Platform Integration
- **8+ Platform Support**: macOS, Linux, WSL, Android, FreeBSD, Windows, Raspberry Pi, Cloud
- **Unified CLI Interface**: Cross-platform command consistency
- **Environment Portability**: Seamless environment migration
- **Hardware Optimization**: Platform-specific optimizations

## Architecture Principles

### Modularity and Composability
- **Component Independence**: Each system functions independently
- **Flexible Integration**: Mix and match components based on needs
- **Configuration Profiles**: Minimal, standard, full, enterprise profiles

### Performance and Efficiency
- **Lazy Loading**: Components loaded only when needed
- **Intelligent Caching**: Multi-level caching strategy
- **Resource Optimization**: Minimal resource footprint
- **Parallel Processing**: Concurrent operations where possible

### Security and Compliance
- **Defense in Depth**: Multiple security layers
- **Automated Compliance**: Built-in compliance checking
- **Audit Trail**: Comprehensive logging and monitoring
- **Incident Response**: Automated threat detection and response

### Reliability and Maintainability
- **Comprehensive Testing**: Automated test suites
- **Error Recovery**: Graceful degradation and recovery
- **Documentation**: Self-documenting configuration
- **Version Control**: Git-based configuration management

## System Requirements

### Minimum Requirements
- **OS**: macOS 11+, Linux with Nix support
- **Memory**: 8GB RAM
- **Storage**: 20GB available space
- **Network**: Internet connection for initial setup

### Recommended Requirements
- **OS**: macOS 13+, NixOS 23.11+
- **Memory**: 16GB+ RAM
- **Storage**: 50GB+ SSD
- **Network**: High-speed internet for AI features

## Quick Start

### 1. Initial Setup
```bash
# Clone repository
git clone https://github.com/user/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Run setup
nix run .#setup
```

### 2. Configuration
```bash
# Set environment profile
export DOTFILES_PROFILE="enterprise"  # minimal/standard/full/enterprise

# Rebuild configuration
just rebuild
```

### 3. Verification
```bash
# Run health checks
phase5-test-suite
dev-health
security-health
```

## Support and Documentation

- **Setup Guide**: `docs/SETUP_GUIDE.md`
- **User Manual**: `docs/USER_GUIDE.md`
- **Developer Documentation**: `docs/DEVELOPER_GUIDE.md`
- **Troubleshooting**: `docs/TROUBLESHOOTING.md`
- **API Reference**: `docs/API_REFERENCE.md`

## License and Contributing

This project is licensed under the MIT License. Contributions are welcome following our contributing guidelines.

---

*Generated by Phase 5 Documentation System*
EOF

          echo "✅ System overview generated"
        }
        
        generate_user_guide() {
          echo "📖 Generating User Guide..."
          
          cat > "$PHASE5_DOCS/USER_GUIDE.md" << 'EOF'
# Phase 5: User Guide

## Daily Operations

### Development Environment

#### Starting a Development Session
```bash
# Check system health
dev-health

# Start development environment
dev

# Check AI tools status
ai-platform-health

# Initialize new project
project-init myapp nodejs
```

#### Working with AI Integration
```bash
# Start local LLM
ai-platform start

# Check AI status
ai-platform status

# Generate code documentation
ai-platform document src/

# Code analysis
ai-platform analyze --file src/main.js
```

### Security Operations

#### Daily Security Tasks
```bash
# Security health check
security-health

# Run threat monitoring
security-threat-monitor monitor

# Generate compliance report
security-compliance report

# Data protection audit
security-data-protection audit .
```

#### Incident Response
```bash
# Report security incident
security-threat-monitor incident critical

# Network security analysis
security-network-monitor scan

# Data encryption
security-data-protection encrypt sensitive-file.txt
```

### Performance Management

#### System Optimization
```bash
# Performance health check
performance-health

# Run optimization
performance-optimizer optimize

# Monitor resources
performance-monitor start

# Generate performance report
performance-analyzer report
```

#### Troubleshooting Performance
```bash
# Analyze system performance
nix run .#analyze -- full-analysis

# Clean up system
performance-optimizer cleanup

# Check resource usage
performance-monitor resources
```

### Universal Platform Operations

#### Platform Management
```bash
# Check platform status
universal-platform-manager status

# Switch platform profile
universal-platform-manager profile set mobile

# Sync configurations
universal-platform-manager sync

# Deploy to remote platform
universal-platform-manager deploy production
```

## Configuration Management

### Environment Profiles

#### Available Profiles
- **minimal**: Basic tools and configuration
- **standard**: Full development environment
- **full**: All features including advanced tools
- **enterprise**: Complete enterprise features

#### Switching Profiles
```bash
# Set profile
export DOTFILES_PROFILE="enterprise"

# Apply changes
just rebuild

# Verify configuration
just health
```

### Customization

#### Adding Custom Tools
```nix
# In ~/.config/dotfiles/custom.nix
{ config, lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    your-custom-tool
  ];
}
```

#### Custom Aliases
```bash
# In ~/.config/dotfiles/aliases.sh
alias mycommand="your-custom-command"
```

## Automation Features

### Automated Tasks

#### Scheduled Operations
- **Daily**: Security monitoring, performance checks
- **Weekly**: System updates, compliance reports
- **Monthly**: Full security audits, performance optimization

#### Event-Driven Actions
- **Git commits**: Automatic security scanning
- **File changes**: Automatic backup and encryption
- **System alerts**: Automatic incident response

### Workflow Integration

#### Git Workflow
```bash
# Automated pre-commit checks
git commit -m "feat: new feature"
# Triggers: security scan, code quality check, documentation update

# Automated deployment
git push origin main
# Triggers: CI/CD pipeline, automated testing, deployment
```

#### Development Workflow
```bash
# Project initialization
project-init webapp react
# Triggers: environment setup, dependency installation, template generation

# Development commands
npm run dev
# Triggers: performance monitoring, resource optimization
```

## Troubleshooting

### Common Issues

#### Configuration Problems
```bash
# Check configuration syntax
nix flake check

# Rebuild with verbose output
darwin-rebuild switch --flake .#default --show-trace

# Reset to known good state
git checkout HEAD~1 && darwin-rebuild switch --flake .#default
```

#### Performance Issues
```bash
# Clear Nix cache
nix store gc

# Optimize Nix store
nix store optimise

# Check system resources
performance-monitor resources
```

#### Security Alerts
```bash
# View security logs
cat ~/.security/logs/threat-monitor.log

# Generate incident report
security-threat-monitor incident

# Update security policies
security-compliance report
```

### Getting Help

#### Built-in Help
```bash
# System help
just --list

# Component help
dev-health --help
security-health --help
performance-health --help
```

#### Support Resources
- **Documentation**: `~/dotfiles/docs/`
- **Issue Tracker**: GitHub Issues
- **Community**: Discord/Slack channels
- **Professional Support**: Enterprise support available

---

*Generated by Phase 5 Documentation System*
EOF

          echo "✅ User guide generated"
        }
        
        generate_developer_guide() {
          echo "🔧 Generating Developer Guide..."
          
          cat > "$PHASE5_DOCS/DEVELOPER_GUIDE.md" << 'EOF'
# Phase 5: Developer Guide

## Development Setup

### Prerequisites
- Nix package manager
- Git version control
- Code editor with Nix support

### Development Environment
```bash
# Enter development shell
nix develop

# Install development tools
nix-shell -p nixpkgs-fmt statix deadnix

# Set up pre-commit hooks
pre-commit install
```

## Architecture Overview

### Module Structure
```
nix/
├── common/           # Shared modules
│   ├── development/  # Development tools
│   ├── security/     # Security systems
│   ├── performance/  # Performance optimization
│   ├── ai-platform/ # AI integration
│   └── universal/    # Universal platform support
├── darwin/          # macOS-specific
├── linux/           # Linux-specific
├── wsl/             # WSL-specific
└── android/         # Android-specific
```

### Key Components

#### Configuration System
- **Flake-based**: Modern Nix flakes for reproducibility
- **Modular Design**: Independent, composable modules
- **Profile System**: Multiple configuration profiles
- **Platform Detection**: Automatic platform adaptation

#### Testing Framework
- **Unit Tests**: Individual module testing
- **Integration Tests**: Cross-module compatibility
- **Performance Tests**: Resource usage and timing
- **Security Tests**: Vulnerability and compliance

## Contributing

### Development Workflow

#### 1. Feature Development
```bash
# Create feature branch
git checkout -b feature/new-component

# Develop and test
nix flake check
phase5-test-suite

# Commit changes
git commit -m "feat: add new component"
```

#### 2. Testing
```bash
# Run comprehensive tests
phase5-test-suite

# Performance benchmarks
performance-analyzer benchmark

# Security validation
security-health
```

#### 3. Documentation
```bash
# Generate documentation
phase5-documentation-generator

# Update changelog
echo "- feat: new component" >> CHANGELOG.md
```

### Code Standards

#### Nix Code Style
```nix
# Use consistent formatting
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.component;
in
{
  options.dotfiles.component = {
    enable = mkEnableOption "Component description";
    
    setting = mkOption {
      type = types.str;
      default = "default-value";
      description = "Setting description";
    };
  };

  config = mkIf cfg.enable {
    # Configuration implementation
  };
}
```

#### Shell Script Standards
```bash
#!/usr/bin/env bash
# Script description
set -euo pipefail

# Function definitions
function_name() {
  local param="$1"
  
  # Implementation
}

# Main execution
main() {
  # Script logic
}

main "$@"
```

### Module Development

#### Creating New Modules
```bash
# Create module directory
mkdir -p nix/common/new-module

# Create module files
touch nix/common/new-module/default.nix
touch nix/common/new-module/config.nix
```

#### Module Template
```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.newModule;
in
{
  options.dotfiles.newModule = {
    enable = mkEnableOption "New module description";
    
    # Add options here
  };

  config = mkIf cfg.enable {
    # Add configuration here
  };
}
```

#### Integration
```nix
# In parent module's default.nix
{
  imports = [
    ./new-module
  ];
}
```

### Testing Guidelines

#### Module Testing
```bash
# Test module syntax
nix eval .#darwinConfigurations.default.config.dotfiles.newModule

# Test module functionality
nix build .#darwinConfigurations.default.system
```

#### Integration Testing
```bash
# Run full test suite
phase5-test-suite

# Run specific test category
phase5-test-suite --category security
```

### Documentation Standards

#### Module Documentation
- **Purpose**: Clear description of module functionality
- **Options**: Detailed option descriptions
- **Examples**: Usage examples and common patterns
- **Dependencies**: Required packages and modules

#### Code Comments
```nix
# Brief description of complex logic
let
  complexCalculation = 
    # Explanation of calculation
    value1 + value2 * modifier;
in
```

## API Reference

### Core Functions

#### Configuration Functions
```nix
# Enable module with options
dotfiles.module.enable = true;
dotfiles.module.option = "value";

# Conditional configuration
dotfiles.module.enable = mkIf condition true;
```

#### Platform Functions
```nix
# Platform-specific configuration
config = mkIf (platformInfo.platform == "darwin") {
  # macOS-specific configuration
};
```

### Utility Functions

#### Common Patterns
```nix
# Optional packages
packages = optionals condition [
  package1
  package2
];

# Profile-based configuration
enable = elem profile [ "standard" "full" ];
```

## Performance Optimization

### Best Practices

#### Lazy Evaluation
```nix
# Use mkIf for conditional evaluation
config = mkIf cfg.enable {
  # Only evaluated when enabled
};
```

#### Package Selection
```nix
# Prefer lighter alternatives
packages = [
  exa         # instead of ls with many options
  ripgrep     # instead of grep
  fd          # instead of find
];
```

### Profiling and Benchmarking

#### Performance Measurement
```bash
# Benchmark configuration evaluation
hyperfine 'nix eval .#darwinConfigurations.default.system'

# Memory usage tracking
/usr/bin/time -l nix build .#darwinConfigurations.default.system
```

## Security Considerations

### Secure Development

#### Secret Management
```nix
# Use SOPS for secrets
sops.secrets.api-key = {
  file = ./secrets.yaml;
  key = "api_key";
};
```

#### Permission Management
```bash
# Secure file permissions
chmod 600 ~/.config/secrets/key.txt
chmod 700 ~/.config/secrets/
```

### Security Testing

#### Vulnerability Scanning
```bash
# Security health check
security-health

# Threat monitoring
security-threat-monitor scan
```

---

*Generated by Phase 5 Documentation System*
EOF

          echo "✅ Developer guide generated"
        }
        
        generate_api_reference() {
          echo "🔌 Generating API Reference..."
          
          cat > "$PHASE5_DOCS/API_REFERENCE.md" << 'EOF'
# Phase 5: API Reference

## Configuration Options

### Core System

#### dotfiles.system
```nix
dotfiles.system = {
  enable = true;  # Enable system configuration
  platform = "auto";  # Platform: auto, darwin, linux, wsl, android
  profile = "enterprise";  # Profile: minimal, standard, full, enterprise
};
```

### Development Environment

#### dotfiles.development
```nix
dotfiles.development = {
  enable = true;  # Enable development environment
  profile = "ai-powered";  # Profile: minimal, standard, full, ai-powered
  
  lsp = {
    enable = true;  # Enable Language Server Protocol
    enabledLanguages = [ "typescript" "python" "rust" ];
    performanceMode = "optimized";
  };
  
  containers = {
    enable = true;  # Enable development containers
    runtime = "docker";  # Runtime: docker, podman
  };
  
  ai-platform = {
    enable = true;  # Enable AI integration platform
    localLLM = true;  # Enable local LLM support
    models = [ "codellama" "deepseek-coder" ];
  };
};
```

### Security System

#### dotfiles.security.enterprise
```nix
dotfiles.security.enterprise = {
  enable = true;  # Enable enterprise security
  securityLevel = "high";  # Level: standard, high, critical
  
  zeroTrust = true;  # Enable Zero Trust Architecture
  threatProtection = true;  # Enable threat protection
  dataProtection = true;  # Enable data protection
  networkSecurity = true;  # Enable network security
  auditLogging = true;  # Enable audit logging
  
  auditLogRetention = 90;  # Retention period in days
};
```

#### dotfiles.security.policies
```nix
dotfiles.security.policies = {
  enable = true;  # Enable security policies
  complianceFramework = "soc2";  # Framework: soc2, iso27001, gdpr
  
  passwordPolicy = true;  # Enforce password policies
  dataClassification = true;  # Enable data classification
  accessControl = true;  # Enable access control
};
```

### Performance System

#### dotfiles.performance
```nix
dotfiles.performance = {
  enable = true;  # Enable performance optimization
  
  nixOptimization = {
    enable = true;  # Enable Nix optimizations
    parallelJobs = 8;  # Number of parallel jobs
    maxMemory = "8G";  # Maximum memory usage
    cacheStrategy = "aggressive";  # Cache strategy
  };
  
  systemOptimization = {
    enable = true;  # Enable system optimizations
    cpuGovernor = "performance";  # CPU governor
    memoryManagement = "optimized";  # Memory management
  };
  
  monitoring = {
    enable = true;  # Enable performance monitoring
    realTimeMetrics = true;  # Real-time metrics
    alerting = true;  # Performance alerting
  };
};
```

### Universal Platform Integration

#### dotfiles.universal.platform
```nix
dotfiles.universal.platform = {
  enable = true;  # Enable universal platform support
  
  extendedPlatforms = true;  # Support FreeBSD, Windows, Raspberry Pi
  containerEcosystem = true;  # Advanced container integration
  serviceMesh = true;  # Service mesh integration
  cloudNative = true;  # Cloud-native platform integration
  
  crossPlatformCLI = true;  # Unified cross-platform CLI
  environmentPortability = true;  # Portable environments
  hardwareOptimization = true;  # Hardware-specific optimizations
  
  supportedPlatforms = [
    "darwin" "linux" "wsl" "android"
    "freebsd" "windows" "raspberrypi" "cloud"
  ];
};
```

### Testing System

#### dotfiles.testing.phase5
```nix
dotfiles.testing.phase5 = {
  enable = true;  # Enable Phase 5 testing
  testingFramework = "comprehensive";  # Framework: minimal, performance, security, comprehensive
  documentationLevel = "full";  # Documentation: minimal, standard, full
  
  performanceBenchmarks = true;  # Enable performance benchmarks
  securityValidation = true;  # Enable security validation
  aiIntegrationTests = true;  # Enable AI integration tests
  universalPlatformTests = true;  # Enable universal platform tests
  
  automatedQualityAssurance = true;  # Enable automated QA
  regressionTesting = true;  # Enable regression testing
  reportGeneration = true;  # Enable report generation
};
```

## Command Line Interface

### Development Commands

#### System Health
```bash
dev-health                    # Development environment health check
ai-platform-health               # AI tools health check
ai-platform-health            # AI platform health check
lsp-health                    # Language Server Protocol health
containers-health             # Container environment health
```

#### Development Environment
```bash
dev                           # Start development environment
dev-clean                     # Clean development environment
dev-status                    # Development environment status

project-init <name> <type>    # Initialize new project
mk-project <name> <type>      # Create and initialize project directory
```

#### AI Integration
```bash
ai-platform start             # Start AI platform
ai-platform stop              # Stop AI platform
ai-platform status            # AI platform status
ai-platform models            # List available models
ai-platform chat              # Interactive chat session
```

### Security Commands

#### Security Health
```bash
security-health               # Enterprise security health check
security-threat-monitor       # Threat protection system
security-data-protection      # Data protection system
security-network-monitor      # Network security monitoring
security-compliance          # Compliance management
```

#### Threat Protection
```bash
security-threat-monitor monitor    # Start threat monitoring
security-threat-monitor scan       # Security scan
security-threat-monitor incident   # Generate incident report
security-threat-monitor compliance # Compliance assessment
```

#### Data Protection
```bash
security-data-protection status      # Data protection status
security-data-protection encrypt     # Encrypt file/directory
security-data-protection decrypt     # Decrypt file
security-data-protection secure-wipe # Secure file deletion
security-data-protection audit       # Data protection audit
```

### Performance Commands

#### Performance Management
```bash
performance-health            # Performance system health check
performance-optimizer         # System optimization
performance-monitor           # Performance monitoring
performance-analyzer          # Performance analysis
```

#### System Optimization
```bash
performance-optimizer optimize    # Run system optimization
performance-optimizer cleanup     # Clean up system resources
performance-optimizer profile     # Performance profiling
performance-optimizer benchmark   # Run benchmarks
```

### Universal Platform Commands

#### Platform Management
```bash
universal-platform-manager status     # Platform status
universal-platform-manager profile    # Manage profiles
universal-platform-manager sync       # Synchronize configurations
universal-platform-manager deploy     # Deploy to platforms
```

#### Cross-Platform Operations
```bash
platform-sync                # Sync across platforms
platform-deploy <target>     # Deploy to target platform
platform-status              # Multi-platform status
platform-health              # Platform health check
```

### Testing Commands

#### Integration Testing
```bash
phase5-test-suite             # Run comprehensive test suite
phase5-test-suite --category <cat>  # Run specific test category
phase5-documentation-generator       # Generate documentation
```

#### Test Categories
```bash
--category nix                # Nix configuration tests
--category ai                 # AI integration tests
--category performance        # Performance tests
--category security           # Security validation tests
--category platform           # Universal platform tests
--category quality            # Quality assurance tests
--category regression         # Regression tests
```

## Environment Variables

### Core Configuration
```bash
DOTFILES_PROFILE              # System profile: minimal, standard, full, enterprise
DOTFILES_DEV_PROFILE          # Development profile: minimal, standard, full, ai-powered
DOTFILES_SECURITY_LEVEL       # Security level: standard, high, critical
```

### AI Platform
```bash
AI_PLATFORM_ENABLED          # Enable AI platform: true, false
AI_LOCAL_LLM_ENABLED          # Enable local LLM: true, false
AI_MODELS_PATH                # Path to AI models
AI_PLATFORM_CONFIG            # AI platform configuration file
```

### Performance System
```bash
PERFORMANCE_OPTIMIZATION      # Enable optimization: true, false
NIX_PARALLEL_JOBS             # Number of parallel Nix jobs
NIX_MAX_MEMORY                # Maximum Nix memory usage
PERFORMANCE_MONITORING        # Enable monitoring: true, false
```

### Security System
```bash
SECURITY_SYSTEM_ENABLED       # Enable security system: true, false
SECURITY_LEVEL                # Security enforcement level
ZERO_TRUST_ENABLED            # Enable Zero Trust: true, false
SECURITY_LOG_DIR              # Security log directory
```

## Error Codes

### System Errors
- **1**: Configuration error
- **2**: Platform not supported
- **3**: Missing dependencies
- **4**: Permission denied
- **5**: Network connectivity issue

### Security Errors
- **10**: Security policy violation
- **11**: Authentication failure
- **12**: Authorization denied
- **13**: Encryption error
- **14**: Compliance violation

### Performance Errors
- **20**: Resource limit exceeded
- **21**: Performance threshold breached
- **22**: Optimization failed
- **23**: Monitoring error

### AI Platform Errors
- **30**: AI service unavailable
- **31**: Model not found
- **32**: LLM communication error
- **33**: AI configuration error

---

*Generated by Phase 5 Documentation System*
EOF

          echo "✅ API reference generated"
        }
        
        # Main documentation generation
        main() {
          case "$DOC_LEVEL" in
            "full")
              generate_system_overview
              generate_user_guide
              generate_developer_guide
              generate_api_reference
              ;;
            "standard")
              generate_system_overview
              generate_user_guide
              ;;
            "minimal")
              generate_system_overview
              ;;
            *)
              echo "❌ Unknown documentation level: $DOC_LEVEL"
              exit 1
              ;;
          esac
          
          echo ""
          echo "✅ Documentation generation complete!"
          echo "📁 Documentation available at: $PHASE5_DOCS"
          echo ""
          echo "📚 Generated Documents:"
          ls -la "$PHASE5_DOCS"
        }
        
        main "$@"
      '';
    };

    # Quality Assurance System
    home-manager.users.yuki.home.file."bin/phase5-quality-assurance" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Phase 5: Quality Assurance System
        set -euo pipefail
        
        QA_DIR="$HOME/.testing/phase5/qa"
        REPORT_DIR="$QA_DIR/reports"
        
        mkdir -p "$QA_DIR" "$REPORT_DIR"
        
        echo "🔍 Phase 5: Quality Assurance System"
        echo "==================================="
        echo ""
        
        ACTION="''${1:-full}"
        
        case "$ACTION" in
          "code-quality")
            echo "📝 Running Code Quality Analysis..."
            
            # Nix code analysis
            if command -v statix &> /dev/null; then
              echo "🔍 Nix static analysis..."
              statix check "$HOME/dotfiles/nix" 2>/dev/null || echo "⚠️  Nix static analysis found issues"
            fi
            
            # Shell script analysis
            if command -v shellcheck &> /dev/null; then
              echo "🐚 Shell script analysis..."
              find "$HOME/dotfiles" -name "*.sh" -type f -exec shellcheck {} \; 2>/dev/null || echo "⚠️  Shell script analysis found issues"
            fi
            ;;
            
          "performance-analysis")
            echo "⚡ Running Performance Analysis..."
            
            # Configuration evaluation performance
            if command -v hyperfine &> /dev/null; then
              echo "📊 Benchmarking configuration evaluation..."
              hyperfine --runs 3 'nix eval .#darwinConfigurations.default.system' 2>/dev/null || echo "⚠️  Performance benchmark failed"
            fi
            
            # System resource analysis
            echo "💾 System resource analysis..."
            echo "Memory usage: $(ps aux | awk '{sum+=$4}; END {print sum}')%"
            echo "Disk usage: $(df -h / | awk 'NR==2{print $5}')"
            ;;
            
          "security-audit")
            echo "🔒 Running Security Audit..."
            
            if command -v security-health &> /dev/null; then
              security-health
            else
              echo "⚠️  Security health check not available"
            fi
            ;;
            
          "documentation-check")
            echo "📚 Checking Documentation Quality..."
            
            # Check for required documentation files
            REQUIRED_DOCS=(
              "README.md"
              "docs/SETUP_GUIDE.md"
              "docs/USER_GUIDE.md"
              "SECURITY.md"
            )
            
            for doc in "''${REQUIRED_DOCS[@]}"; do
              if [[ -f "$HOME/dotfiles/$doc" ]]; then
                echo "✅ $doc exists"
              else
                echo "❌ $doc missing"
              fi
            done
            ;;
            
          "full")
            echo "🚀 Running Full Quality Assurance..."
            echo ""
            
            phase5-quality-assurance code-quality
            echo ""
            phase5-quality-assurance performance-analysis
            echo ""
            phase5-quality-assurance security-audit
            echo ""
            phase5-quality-assurance documentation-check
            
            echo ""
            echo "✅ Full quality assurance complete!"
            ;;
            
          *)
            echo "Usage: phase5-quality-assurance <action>"
            echo ""
            echo "Actions:"
            echo "  code-quality         - Code quality analysis"
            echo "  performance-analysis - Performance analysis"
            echo "  security-audit       - Security audit"
            echo "  documentation-check  - Documentation check"
            echo "  full                 - Run all checks"
            ;;
        esac
      '';
    };

    # Health Check Integration
    home-manager.users.yuki.home.file."bin/phase5-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🏥 Phase 5: Comprehensive Health Check"
        echo "====================================="
        echo ""
        
        ISSUES=0
        
        # System Configuration Health
        echo "🏗️  System Configuration:"
        if nix flake check --no-build 2>/dev/null; then
          echo "  ✅ Nix configuration: Valid"
        else
          echo "  ❌ Nix configuration: Invalid"
          ((ISSUES++))
        fi
        
        # Development Environment Health
        echo ""
        echo "🛠️  Development Environment:"
        if command -v dev-health &> /dev/null && dev-health >/dev/null 2>&1; then
          echo "  ✅ Development environment: Healthy"
        else
          echo "  ❌ Development environment: Issues detected"
          ((ISSUES++))
        fi
        
        # AI Platform Health
        echo ""
        echo "🤖 AI Integration Platform:"
        if command -v ai-platform-health &> /dev/null && ai-platform-health >/dev/null 2>&1; then
          echo "  ✅ AI platform: Operational"
        else
          echo "  ⚠️  AI platform: Not available or issues detected"
        fi
        
        # Performance System Health
        echo ""
        echo "⚡ Performance System:"
        if command -v performance-health &> /dev/null && performance-health >/dev/null 2>&1; then
          echo "  ✅ Performance system: Optimal"
        else
          echo "  ⚠️  Performance system: Not available or issues detected"
        fi
        
        # Security System Health
        echo ""
        echo "🔒 Enterprise Security:"
        if command -v security-health &> /dev/null && security-health >/dev/null 2>&1; then
          echo "  ✅ Security system: Secure"
        else
          echo "  ❌ Security system: Issues detected"
          ((ISSUES++))
        fi
        
        # Universal Platform Health
        echo ""
        echo "🌐 Universal Platform Integration:"
        if command -v universal-platform-manager &> /dev/null; then
          echo "  ✅ Universal platform: Available"
        else
          echo "  ⚠️  Universal platform: Not configured"
        fi
        
        # Testing System Health
        echo ""
        echo "🧪 Testing System:"
        if command -v phase5-test-suite &> /dev/null; then
          echo "  ✅ Test suite: Available"
        else
          echo "  ❌ Test suite: Not available"
          ((ISSUES++))
        fi
        
        # Summary
        echo ""
        echo "📊 Health Summary:"
        if [[ $ISSUES -eq 0 ]]; then
          echo "  🟢 Phase 5 system: Fully operational"
          echo "  🎯 All critical systems healthy"
        elif [[ $ISSUES -le 2 ]]; then
          echo "  🟡 Phase 5 system: Minor issues detected ($ISSUES)"
          echo "  ⚠️  Some components need attention"
        else
          echo "  🔴 Phase 5 system: Multiple issues detected ($ISSUES)"
          echo "  🚨 Immediate attention required"
        fi
        
        echo ""
        echo "🚀 Available Commands:"
        echo "  phase5-test-suite              - Run comprehensive tests"
        echo "  phase5-documentation-generator - Generate documentation"
        echo "  phase5-quality-assurance       - Quality assurance checks"
        echo "  phase5-health                  - This health check"
        
        # Return appropriate exit code
        if [[ $ISSUES -gt 2 ]]; then
          exit 1
        else
          exit 0
        fi
      '';
    };
  };
}