#!/usr/bin/env bash
# Local CI Test Runner - GitHub Actions simulation
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    log_info "Running: $test_name"
    
    if eval "$test_command"; then
        log_success "$test_name passed"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$test_name failed"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Change to dotfiles directory
cd "$(dirname "$0")/.."

log_info "🚀 Starting Local CI Tests"
log_info "=========================="

# 1. Lint and Syntax Check
log_info "📋 Phase 1: Lint and Syntax Check"

# Shellcheck for shell scripts
if command -v shellcheck &> /dev/null; then
    run_test "Shellcheck validation" "find . -name '*.sh' -not -path './backups/*' -not -path './.git/*' | xargs shellcheck"
else
    log_warning "Shellcheck not installed, installing via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install shellcheck
        run_test "Shellcheck validation" "find . -name '*.sh' -not -path './backups/*' -not -path './.git/*' | xargs shellcheck"
    else
        log_error "Homebrew not available, skipping shellcheck"
        ((TESTS_FAILED++))
    fi
fi

# Nix syntax check
if command -v nix &> /dev/null; then
    run_test "Nix flake check" "cd nix/platforms && nix flake check --impure"
else
    log_error "Nix not installed, cannot run Nix syntax check"
    ((TESTS_FAILED++))
fi

# JSON syntax check
run_test "JSON syntax validation" "find . -name '*.json' -not -path './backups/*' -not -path './.git/*' | xargs -I {} sh -c 'echo \"Checking {}\"; python3 -m json.tool {} > /dev/null'"

# YAML syntax check
if command -v yq &> /dev/null; then
    run_test "YAML syntax validation" "find . -name '*.yml' -o -name '*.yaml' | grep -v backups | xargs -I {} yq eval . {} > /dev/null"
else
    log_warning "yq not installed, skipping YAML validation"
fi

# 2. Security Scan
log_info "🔒 Phase 2: Security Scan"

# GitLeaks
if command -v gitleaks &> /dev/null; then
    run_test "GitLeaks secret detection" "gitleaks detect --source=. --verbose"
else
    log_warning "GitLeaks not installed, installing via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install gitleaks
        run_test "GitLeaks secret detection" "gitleaks detect --source=. --verbose"
    else
        log_error "Homebrew not available, skipping GitLeaks"
        ((TESTS_FAILED++))
    fi
fi

# Check for common security issues
run_test "Common security patterns check" "! grep -r --include='*.sh' --include='*.nix' --include='*.json' 'password\\|secret\\|token\\|key' . | grep -v '.example' | grep -v 'age-key' | grep -v 'ssh-key' | grep -v 'api-key-name'"

# 3. Installation Script Test
log_info "🔧 Phase 3: Installation Script Test"

# Dry run of installation script
if [[ -f "install.sh" ]]; then
    run_test "Installation script syntax" "bash -n install.sh"
else
    log_error "install.sh not found"
    ((TESTS_FAILED++))
fi

# 4. Platform Integration Test
log_info "🖥️  Phase 4: Platform Integration Test"

# Test platform detection
if [[ -f "nix/platforms/common/platform-detection.nix" ]]; then
    run_test "Platform detection validation" "cd nix/platforms && nix eval --impure --expr 'let platform = import ./common/platform-detection.nix; in platform.detectPlatform'"
else
    log_error "Platform detection file not found"
    ((TESTS_FAILED++))
fi

# 5. Development Environment Test
log_info "🛠️  Phase 5: Development Environment Test"

# Test LSP configuration
if [[ -f "nix/platforms/common/development/lsp/default.nix" ]]; then
    run_test "LSP configuration syntax" "cd nix/platforms && nix-instantiate --eval --expr 'import ./common/development/lsp/default.nix { config = {}; lib = import <nixpkgs/lib>; pkgs = import <nixpkgs> {}; }'"
else
    log_warning "LSP configuration not found (expected for new implementation)"
fi

# Test container configuration
if [[ -f "nix/platforms/common/development/containers/default.nix" ]]; then
    run_test "Container configuration syntax" "cd nix/platforms && nix-instantiate --eval --expr 'import ./common/development/containers/default.nix { config = {}; lib = import <nixpkgs/lib>; pkgs = import <nixpkgs> {}; }'"
else
    log_warning "Container configuration not found (expected for new implementation)"
fi

# Summary
log_info "📊 Test Summary"
log_info "==============="
log_success "Tests passed: $TESTS_PASSED"
if [[ $TESTS_FAILED -gt 0 ]]; then
    log_error "Tests failed: $TESTS_FAILED"
    exit 1
else
    log_success "All tests passed! 🎉"
    exit 0
fi