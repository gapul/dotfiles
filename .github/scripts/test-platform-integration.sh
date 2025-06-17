#!/bin/bash
# Multi-Platform Integration Test Script
# Tests platform detection, configuration building, and runtime verification

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLATFORMS_DIR="$PROJECT_ROOT/nix/platforms"
TEST_OUTPUT_DIR="$PROJECT_ROOT/test-results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "Running test: $test_name"
    
    if $test_function; then
        log_success "✅ $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "❌ $test_name"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

# Platform detection test
test_platform_detection() {
    log_info "Testing platform detection logic..."
    
    cd "$PLATFORMS_DIR"
    
    # Test that platform detection evaluates without errors
    if ! nix eval .#platformInfo.platform --json >/dev/null 2>&1; then
        log_error "Platform detection evaluation failed"
        return 1
    fi
    
    # Test capabilities evaluation
    if ! nix eval .#platformInfo.capabilities --json >/dev/null 2>&1; then
        log_error "Platform capabilities evaluation failed"
        return 1
    fi
    
    # Test current platform is detected
    local current_platform
    current_platform=$(nix eval .#platformInfo.platform --raw 2>/dev/null)
    
    if [[ -z "$current_platform" ]]; then
        log_error "Current platform not detected"
        return 1
    fi
    
    log_info "Detected platform: $current_platform"
    return 0
}

# Flake syntax test
test_flake_syntax() {
    log_info "Testing flake syntax..."
    
    cd "$PLATFORMS_DIR"
    
    if ! nix flake check --show-trace; then
        log_error "Flake syntax check failed"
        return 1
    fi
    
    return 0
}

# Configuration building test
test_configuration_builds() {
    log_info "Testing configuration builds..."
    
    cd "$PLATFORMS_DIR"
    
    # Test configurations that should work on current system
    local configs_to_test=()
    
    # Determine which configs to test based on current system
    case "$(uname -s)" in
        Darwin)
            configs_to_test+=(
                "darwinConfigurations.default"
                "homeConfigurations.yuki@darwin"
            )
            ;;
        Linux)
            configs_to_test+=(
                "homeConfigurations.yuki@linux"
                "homeConfigurations.yuki@wsl"
            )
            ;;
    esac
    
    for config in "${configs_to_test[@]}"; do
        log_info "Testing build: $config"
        
        if ! nix build ".#$config" --no-link --print-build-logs; then
            log_error "Failed to build $config"
            return 1
        fi
        
        log_success "Built $config successfully"
    done
    
    return 0
}

# Package availability test
test_package_availability() {
    log_info "Testing package availability..."
    
    cd "$PLATFORMS_DIR"
    
    # Test that packages can be evaluated for each platform
    local platforms=("linux" "wsl")
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        platforms+=("darwin")
    fi
    
    for platform in "${platforms[@]}"; do
        local config=""
        case "$platform" in
            darwin)
                config="darwinConfigurations.default.config.environment.systemPackages"
                ;;
            linux)
                config="homeConfigurations.yuki@linux.config.home.packages"
                ;;
            wsl)
                config="homeConfigurations.yuki@wsl.config.home.packages"
                ;;
        esac
        
        log_info "Testing packages for $platform..."
        
        if ! nix eval ".#$config" --json >/dev/null 2>&1; then
            log_error "Failed to evaluate packages for $platform"
            return 1
        fi
        
        local package_count
        package_count=$(nix eval ".#$config" --json | jq length)
        log_info "$platform has $package_count packages"
    done
    
    return 0
}

# Shell configuration test
test_shell_configuration() {
    log_info "Testing shell configuration..."
    
    cd "$PLATFORMS_DIR"
    
    # Test shell configuration for available platforms
    local configs=()
    
    case "$(uname -s)" in
        Darwin)
            configs+=("homeConfigurations.yuki@darwin")
            ;;
        Linux)
            configs+=("homeConfigurations.yuki@linux" "homeConfigurations.yuki@wsl")
            ;;
    esac
    
    for config in "${configs[@]}"; do
        log_info "Testing shell config: $config"
        
        # Test zsh is enabled
        if ! nix eval ".#$config.config.programs.zsh.enable" >/dev/null 2>&1; then
            log_error "Failed to evaluate zsh config for $config"
            return 1
        fi
        
        # Test aliases are defined
        if ! nix eval ".#$config.config.programs.zsh.shellAliases" --json >/dev/null 2>&1; then
            log_error "Failed to evaluate shell aliases for $config"
            return 1
        fi
        
        local alias_count
        alias_count=$(nix eval ".#$config.config.programs.zsh.shellAliases" --json | jq length)
        log_info "$config has $alias_count shell aliases"
    done
    
    return 0
}

# Cross-platform compatibility test
test_cross_platform_compatibility() {
    log_info "Testing cross-platform compatibility..."
    
    cd "$PLATFORMS_DIR"
    
    # Test that all platform modules can be imported without errors
    local platforms=("common" "linux" "wsl")
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        platforms+=("darwin")
    fi
    
    for platform in "${platforms[@]}"; do
        if [[ -d "$platform" ]]; then
            log_info "Testing platform module: $platform"
            
            # Check that nix files in platform directory are syntactically correct
            find "$platform" -name "*.nix" -type f | while read -r nix_file; do
                if ! nix-instantiate --parse "$nix_file" >/dev/null 2>&1; then
                    log_error "Syntax error in $nix_file"
                    return 1
                fi
            done
        fi
    done
    
    return 0
}

# Performance test
test_build_performance() {
    log_info "Testing build performance..."
    
    cd "$PLATFORMS_DIR"
    
    # Time a simple configuration build
    local start_time end_time duration
    
    start_time=$(date +%s.%N)
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        nix build .#homeConfigurations.yuki@darwin --no-link --quiet
    else
        nix build .#homeConfigurations.yuki@linux --no-link --quiet
    fi
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    
    log_info "Build completed in ${duration}s"
    
    # Consider builds over 5 minutes as slow
    if (( $(echo "$duration > 300" | bc -l) )); then
        log_warning "Build took longer than 5 minutes"
    fi
    
    return 0
}

# Security test
test_security() {
    log_info "Testing security configuration..."
    
    # Check for hardcoded secrets
    if grep -r -E "(password|secret|key|token).*=" "$PLATFORMS_DIR" --include="*.nix" 2>/dev/null; then
        log_warning "Potential hardcoded secrets found"
        # Don't fail the test, just warn
    fi
    
    # Check file permissions
    find "$PLATFORMS_DIR" -type f -name "*.nix" -perm /077 | while read -r file; do
        log_warning "File has overly permissive permissions: $file"
    done
    
    return 0
}

# Generate test report
generate_report() {
    local report_file="$TEST_OUTPUT_DIR/integration-test-report.md"
    
    mkdir -p "$TEST_OUTPUT_DIR"
    
    cat > "$report_file" << EOF
# Multi-Platform Integration Test Report

Generated: $(date)
Platform: $(uname -s) $(uname -m)

## Test Summary

- Tests Passed: $TESTS_PASSED
- Tests Failed: $TESTS_FAILED
- Total Tests: $((TESTS_PASSED + TESTS_FAILED))

## Test Results

EOF

    if [[ ${#FAILED_TESTS[@]} -eq 0 ]]; then
        echo "✅ All tests passed!" >> "$report_file"
    else
        echo "❌ Failed tests:" >> "$report_file"
        for test in "${FAILED_TESTS[@]}"; do
            echo "- $test" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

## Platform Information

- Operating System: $(uname -s)
- Architecture: $(uname -m)
- Nix Version: $(nix --version)

## Configuration Details

EOF

    cd "$PLATFORMS_DIR"
    
    # Add platform detection results
    if nix eval .#platformInfo.platform --json >/dev/null 2>&1; then
        echo "- Detected Platform: $(nix eval .#platformInfo.platform --raw)" >> "$report_file"
    fi
    
    if nix eval .#platformInfo.capabilities --json >/dev/null 2>&1; then
        echo "- Platform Capabilities:" >> "$report_file"
        nix eval .#platformInfo.capabilities --json | jq -r 'to_entries[] | "  - \(.key): \(.value)"' >> "$report_file"
    fi
    
    log_success "Test report generated: $report_file"
}

# Main test execution
main() {
    log_info "Starting multi-platform integration tests..."
    log_info "Project root: $PROJECT_ROOT"
    log_info "Platforms directory: $PLATFORMS_DIR"
    
    # Ensure we're in the right directory
    if [[ ! -d "$PLATFORMS_DIR" ]]; then
        log_error "Platforms directory not found: $PLATFORMS_DIR"
        exit 1
    fi
    
    # Run all tests
    run_test "Platform Detection" test_platform_detection
    run_test "Flake Syntax" test_flake_syntax
    run_test "Configuration Builds" test_configuration_builds || true  # Don't fail on build errors
    run_test "Package Availability" test_package_availability
    run_test "Shell Configuration" test_shell_configuration
    run_test "Cross-Platform Compatibility" test_cross_platform_compatibility
    run_test "Build Performance" test_build_performance || true  # Don't fail on performance
    run_test "Security" test_security || true  # Don't fail on security warnings
    
    # Generate report
    generate_report
    
    # Final summary
    echo
    log_info "=== Test Summary ==="
    log_success "Passed: $TESTS_PASSED"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "Failed: $TESTS_FAILED"
        log_error "Failed tests: ${FAILED_TESTS[*]}"
        exit 1
    else
        log_success "All tests passed! 🎉"
    fi
}

# Script usage
show_usage() {
    cat << EOF
Usage: $0 [options]

Multi-Platform Integration Test Script

Options:
  -h, --help     Show this help message
  -v, --verbose  Enable verbose output
  
Examples:
  $0                    # Run all integration tests
  $0 --verbose          # Run with verbose output

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"