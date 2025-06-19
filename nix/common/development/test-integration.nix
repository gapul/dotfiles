# Development Environment Integration Testing and Optimization
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development;
in
{
  config = mkIf cfg.enable {
    # Comprehensive development environment health check
    home-manager.users.yuki.home.file."bin/dev-integration-test" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Development Environment Integration Test
        set -euo pipefail
        
        # Colors
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        PURPLE='\033[0;35m'
        NC='\033[0m'
        
        log_header() { echo -e "''${PURPLE}🚀 $1''${NC}"; }
        log_info() { echo -e "''${BLUE}ℹ️  $1''${NC}"; }
        log_success() { echo -e "''${GREEN}✅ $1''${NC}"; }
        log_warning() { echo -e "''${YELLOW}⚠️  $1''${NC}"; }
        log_error() { echo -e "''${RED}❌ $1''${NC}"; }
        
        # Test results tracking
        TOTAL_TESTS=0
        PASSED_TESTS=0
        FAILED_TESTS=0
        
        run_test() {
          local test_name="$1"
          local test_command="$2"
          
          TOTAL_TESTS=$((TOTAL_TESTS + 1))
          
          if eval "$test_command" &>/dev/null; then
            log_success "$test_name"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
          else
            log_error "$test_name"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
          fi
        }
        
        log_header "Phase 4.4: Advanced Development Environment Integration Test"
        echo "============================================================="
        echo ""
        
        # Test 1: Development Containers Integration
        log_header "1. Development Containers Integration"
        echo "-----------------------------------"
        
        ${if cfg.containers.enable then ''
          run_test "DevContainer Templates Available" "command -v devcontainer-templates"
          run_test "DevContainer Images Manager" "command -v devcontainer-images"
          run_test "Docker Integration" "command -v docker"
          run_test "VS Code Dev Containers Config" "[[ -f ~/.vscode/settings.json ]]"
        '' else ''
          log_warning "Development Containers: Disabled in configuration"
        ''}
        
        echo ""
        
        # Test 2: LSP Complete Integration
        log_header "2. Language Server Protocol (LSP) Complete Integration"
        echo "-----------------------------------------------------"
        
        ${if cfg.lsp.enable then ''
          run_test "LSP Health Check Available" "command -v lsp-health"
          run_test "LSP Auto-Config Available" "command -v lsp-auto-config"
          run_test "LSP Performance Tools" "command -v lsp-benchmark"
          run_test "LSP Configuration Found" "[[ -f ~/.config/lsp/config.json ]]"
          
          # Test specific language servers
          ${concatStringsSep "\n" (map (lang: ''
            if command -v ${lang} &>/dev/null; then
              run_test "LSP Server: ${lang}" "command -v ${lang}"
            fi
          '') (cfg.lsp.enabledLanguages or [ "typescript-language-server" "rust-analyzer" "gopls" "pylsp" ]))}
        '' else ''
          log_warning "LSP Integration: Disabled in configuration"
        ''}
        
        echo ""
        
        # Test 3: AI Development Tools Integration
        log_header "3. AI Development Tools Integration"
        echo "---------------------------------"
        
        ${if cfg.ai-tools.enable then ''
          run_test "AI Tools Configuration" "[[ -f ~/.config/ai-tools/config.json ]]"
          run_test "AI Models Manager" "command -v ai-models"
          run_test "Claude Dev Helper" "command -v claude-dev"
          run_test "AI Health Check" "command -v ai-tools-health"
          run_test "GitHub CLI Available" "command -v gh"
          
          # Test Claude Code CLI
          if command -v claude &>/dev/null; then
            run_test "Claude Code CLI" "claude --version"
          else
            log_warning "Claude Code CLI: Not found (install with npm)"
          fi
          
          # Test local AI models (Ollama managed via Homebrew casks)
          if command -v ollama &>/dev/null; then
            run_test "Ollama Available" "command -v ollama"
          else
            log_info "Ollama: Not available (install via: brew install --cask ollama)"
          fi
        '' else ''
          log_warning "AI Tools Integration: Disabled in configuration"
        ''}
        
        echo ""
        
        # Test 4: Project Environment Auto-Setup
        log_header "4. Project Environment Auto-Setup"
        echo "--------------------------------"
        
        ${if cfg.project-env.enable then ''
          run_test "Project Init Available" "command -v project-init"
          run_test "Project Health Check" "command -v project-env-health"
          
          # Test direnv integration
          ${if cfg.project-env.direnvIntegration then ''
            run_test "Direnv Available" "command -v direnv"
            run_test "Nix-Direnv Integration" "direnv --version | grep -q nix"
          '' else ''
            log_info "Direnv: Disabled in configuration"
          ''}
        '' else ''
          log_warning "Project Environment: Disabled in configuration"
        ''}
        
        echo ""
        
        # Test 5: Performance and Optimization
        log_header "5. Performance and Optimization"
        echo "------------------------------"
        
        # Test development tools performance
        run_test "Nix Available" "command -v nix"
        run_test "Git Available" "command -v git"
        run_test "Shell Integration" "[[ -n \"\$ZSH_VERSION\" ]]"
        run_test "Starship Prompt" "command -v starship"
        
        # Check memory usage of development tools
        DEV_PROCESSES=$(ps aux | grep -E '(language-server|lsp|rust-analyzer|gopls|nil)' | grep -v grep | wc -l || echo "0")
        if [[ $DEV_PROCESSES -lt 10 ]]; then
          log_success "Development Process Count: $DEV_PROCESSES (reasonable)"
        else
          log_warning "Development Process Count: $DEV_PROCESSES (high)"
        fi
        
        echo ""
        
        # Test 6: Integration Testing
        log_header "6. Cross-Component Integration"
        echo "-----------------------------"
        
        # Test if LSP auto-config works with project detection
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        
        # Create a test Node.js project
        if command -v npm &>/dev/null; then
          npm init -y >/dev/null 2>&1
          
          # Test LSP auto-detection
          if command -v lsp-detect &>/dev/null; then
            run_test "LSP Auto-Detection" "lsp-detect ."
          fi
          
          # Test project environment setup
          if command -v project-init &>/dev/null; then
            run_test "Project Auto-Setup" "project-init test-project nodejs ."
          fi
          
          # Test DevContainer template creation
          if command -v devcontainer-templates &>/dev/null; then
            run_test "DevContainer Template Creation" "devcontainer-templates create . node"
          fi
        fi
        
        # Cleanup
        cd - >/dev/null
        rm -rf "$TEMP_DIR"
        
        echo ""
        
        # Test 7: Documentation and Help Systems
        log_header "7. Documentation and Help Systems"
        echo "--------------------------------"
        
        # Test help commands
        run_test "Development Health Check" "command -v dev-health"
        run_test "LSP Health Available" "command -v lsp-health"
        run_test "AI Health Available" "command -v ai-tools-health"
        run_test "Project Health Available" "command -v project-env-health"
        
        echo ""
        
        # Performance Benchmarking
        log_header "8. Performance Benchmarking"
        echo "--------------------------"
        
        # Measure startup times
        if command -v time &>/dev/null; then
          log_info "Running performance benchmarks..."
          
          # Test shell startup time
          SHELL_TIME=$(time (zsh -c 'exit') 2>&1 | grep real | awk '{print $2}' || echo "unknown")
          log_info "Shell startup time: $SHELL_TIME"
          
          # Test LSP server startup times (if available)
          if command -v lsp-benchmark &>/dev/null; then
            log_info "Running LSP benchmark..."
            lsp-benchmark /tmp/lsp-benchmark-test >/dev/null 2>&1 || true
          fi
        fi
        
        echo ""
        
        # Summary Report
        log_header "Test Summary Report"
        echo "==================="
        echo ""
        echo "📊 Results:"
        echo "  Total Tests: $TOTAL_TESTS"
        echo "  Passed: $PASSED_TESTS"
        echo "  Failed: $FAILED_TESTS"
        echo "  Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
        echo ""
        
        # Configuration Summary
        echo "⚙️  Configuration:"
        echo "  Development Profile: ${cfg.profile}"
        echo "  Containers: ${if cfg.containers.enable then "Enabled" else "Disabled"}"
        echo "  LSP: ${if cfg.lsp.enable then "Enabled" else "Disabled"}"
        echo "  AI Tools: ${if cfg.ai-tools.enable then "Enabled" else "Disabled"}"
        echo "  Project Env: ${if cfg.project-env.enable then "Enabled" else "Disabled"}"
        echo ""
        
        # Recommendations
        echo "💡 Recommendations:"
        if [[ $FAILED_TESTS -gt 0 ]]; then
          echo "  - Review failed tests and install missing components"
          echo "  - Run 'nix run nix-darwin -- switch --flake .' to update configuration"
          echo "  - Check individual health commands for detailed diagnostics"
        else
          echo "  ✅ All tests passed! Development environment is fully functional"
        fi
        
        echo "  - Run individual health checks for detailed status:"
        echo "    • dev-health - Overall development environment"
        echo "    • lsp-health - Language server status"
        echo "    • ai-tools-health - AI tools status"
        echo "    • project-env-health - Project environment status"
        
        echo ""
        echo "🎉 Phase 4.4: Advanced Development Environment Integration Test Complete!"
        
        # Return appropriate exit code
        if [[ $FAILED_TESTS -eq 0 ]]; then
          exit 0
        else
          exit 1
        fi
      '';
    };

    # Development environment optimization script
    home-manager.users.yuki.home.file."bin/dev-optimize" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Development Environment Optimization
        set -euo pipefail
        
        ACTION="''${1:-all}"
        
        echo "🚀 Development Environment Optimization"
        echo "======================================"
        
        case "$ACTION" in
          "memory"|"all")
            echo ""
            echo "🧠 Memory Optimization..."
            
            # Clean Nix store
            if command -v nix &>/dev/null; then
              echo "  Cleaning Nix store..."
              nix store gc --verbose >/dev/null 2>&1 || true
            fi
            
            # Clean LSP caches
            echo "  Cleaning LSP caches..."
            find ~/.cache -name "*lsp*" -type d -exec rm -rf {} + 2>/dev/null || true
            find ~/.local/share -name "*lsp*" -type d -exec rm -rf {} + 2>/dev/null || true
            
            # Clean AI model caches (if present)
            # if [[ -d ~/.ollama ]]; then
            #   echo "  Optimizing AI model storage..."
            #   # Clean temporary files
            #   find ~/.ollama -name "*.tmp" -delete 2>/dev/null || true
            #   find ~/.ollama -name "*.partial" -delete 2>/dev/null || true
            # fi
            ;;
        esac
        
        case "$ACTION" in
          "performance"|"all")
            echo ""
            echo "⚡ Performance Optimization..."
            
            # Optimize shell configuration
            if command -v zsh &>/dev/null; then
              echo "  Recompiling zsh configuration..."
              zsh -c 'autoload -U compinit && compinit' 2>/dev/null || true
            fi
            
            # Preload commonly used tools
            if command -v lsp-health &>/dev/null; then
              echo "  Preloading LSP servers..."
              lsp-health >/dev/null 2>&1 || true
            fi
            ;;
        esac
        
        case "$ACTION" in
          "update"|"all")
            echo ""
            echo "🔄 Update Optimization..."
            
            # Update development tools
            if command -v ai-models &>/dev/null; then
              echo "  Updating AI models..."
              ai-models update >/dev/null 2>&1 || true
            fi
            ;;
        esac
        
        echo ""
        echo "✅ Optimization complete!"
        echo ""
        echo "💡 Run 'dev-integration-test' to verify optimizations"
      '';
    };

    # Development environment documentation generator
    home-manager.users.yuki.home.file."bin/dev-docs" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Development Environment Documentation Generator
        set -euo pipefail
        
        OUTPUT_FILE="''${1:-DEV_ENVIRONMENT.md}"
        
        echo "📚 Generating development environment documentation..."
        
        cat > "$OUTPUT_FILE" << 'EOF'
        # Advanced Development Environment (Phase 4.4)
        
        This document describes the complete advanced development environment setup with integrated tools and automation.
        
        ## Overview
        
        The development environment provides:
        - **Development Containers**: Docker-based isolated environments
        - **LSP Integration**: Complete language server support for all major languages
        - **AI Tools**: GitHub Copilot, Claude Code, and local AI models
        - **Project Auto-Setup**: Automatic environment detection and configuration
        
        ## Components
        
        ### 1. Development Containers
        
        #### Features
        - Pre-configured templates for major languages
        - VS Code Dev Containers integration
        - Automatic image management
        - Resource optimization
        
        #### Commands
        ```bash
        # List available templates
        devcontainer-templates list
        
        # Create DevContainer for project
        devcontainer-templates create . nodejs
        
        # Check container status
        devcontainer-templates status
        
        # Manage container images
        devcontainer-images status
        devcontainer-images pull
        ```
        
        ### 2. Language Server Protocol (LSP)
        
        #### Supported Languages
        - TypeScript/JavaScript
        - Python
        - Rust
        - Go
        - C/C++
        - Java
        - PHP
        - Ruby
        - Lua
        - Nix
        - YAML/JSON/Markdown
        
        #### Commands
        ```bash
        # Check LSP health
        lsp-health
        
        # Auto-configure for project
        lsp-auto-config
        
        # Performance benchmark
        lsp-benchmark
        
        # Performance tuning
        lsp-tune optimize
        ```
        
        ### 3. AI Development Tools
        
        #### Available Tools
        - GitHub Copilot
        - Claude Code CLI
        - Local AI models (Ollama via Homebrew)
        - AI-powered project analysis
        
        #### Commands
        ```bash
        # Check AI tools status
        ai-tools-health
        
        # Manage local AI models
        ai-models install
        ai-models status
        ai-models chat
        
        # Claude Code integration
        claude-dev setup
        claude-dev analyze
        claude-dev review <file>
        ```
        
        ### 4. Project Environment Auto-Setup
        
        #### Features
        - Automatic project type detection
        - Environment configuration generation
        - Direnv integration
        - Multi-language support
        
        #### Commands
        ```bash
        # Initialize new project
        project-init my-project nodejs
        
        # Auto-detect and setup
        project-init my-project auto
        
        # Check project environment
        project-env-health
        ```
        
        ## Health Checks
        
        ### Comprehensive Testing
        ```bash
        # Full integration test
        dev-integration-test
        
        # Individual component checks
        dev-health
        lsp-health
        ai-tools-health
        project-env-health
        ```
        
        ### Performance Optimization
        ```bash
        # Optimize all components
        dev-optimize
        
        # Specific optimizations
        dev-optimize memory
        dev-optimize performance
        dev-optimize update
        ```
        
        ## Configuration
        
        The development environment is configured through Nix with the following profiles:
        
        - **minimal**: Basic tools only
        - **standard**: Common development languages and tools
        - **full**: Complete feature set including advanced tools
        - **ai-powered**: Full + AI tools integration
        
        ### Current Configuration
        Profile: ${cfg.profile}
        
        Components:
        - Containers: ${if cfg.containers.enable then "✅ Enabled" else "❌ Disabled"}
        - LSP: ${if cfg.lsp.enable then "✅ Enabled" else "❌ Disabled"}
        - AI Tools: ${if cfg.ai-tools.enable then "✅ Enabled" else "❌ Disabled"}
        - Project Env: ${if cfg.project-env.enable then "✅ Enabled" else "❌ Disabled"}
        
        ## Troubleshooting
        
        ### Common Issues
        
        1. **LSP servers not starting**
           ```bash
           lsp-health --detailed
           lsp-restart
           ```
        
        2. **AI models not working**
           ```bash
           ai-tools-health
           ai-models install
           ```
        
        3. **Project environment not detected**
           ```bash
           project-env-health
           project-init project-name auto
           ```
        
        4. **Performance issues**
           ```bash
           dev-optimize memory
           lsp-tune optimize
           ```
        
        ### Support Commands
        
        ```bash
        # View logs
        lsp-logs
        
        # Performance monitoring
        lsp-perf
        
        # Clean up resources
        devcontainer-templates clean
        dev-optimize memory
        ```
        
        ## Integration with Editors
        
        ### VS Code
        - Automatic extension configuration
        - Dev Containers support
        - LSP integration
        - AI tools integration
        
        ### Neovim
        - LSP configuration
        - AI plugin integration
        - Performance optimizations
        
        ### Helix
        - LSP server configuration
        - Language-specific settings
        
        ## Best Practices
        
        1. **Regular Health Checks**: Run `dev-integration-test` weekly
        2. **Performance Monitoring**: Use `lsp-health` and `dev-optimize`
        3. **Project Setup**: Always use `project-init` for new projects
        4. **AI Integration**: Setup Claude Code with `claude-dev setup`
        5. **Container Usage**: Use DevContainers for complex projects
        
        ## Updates and Maintenance
        
        ```bash
        # Update Nix configuration
        nix run nix-darwin -- switch --flake .
        
        # Update AI models
        ai-models update
        
        # Optimize performance
        dev-optimize all
        
        # Test after updates
        dev-integration-test
        ```
        
        ---
        
        Generated by: Phase 4.4 Advanced Development Environment
        Date: $(date)
        Profile: ${cfg.profile}
        EOF
        
        echo "✅ Documentation generated: $OUTPUT_FILE"
        echo "📖 View with: cat $OUTPUT_FILE"
      '';
    };
  };
}