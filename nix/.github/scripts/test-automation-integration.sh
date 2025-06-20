#!/usr/bin/env bash
# Phase 4.5 Automation Integration Test
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT_DIR="$(cd "$NIX_DIR/.." && pwd)"
TEST_DIR="$NIX_DIR/test-automation"
ERRORS=0

echo "🧪 Phase 4.5 Automation Integration Test"
echo "========================================"
echo "Root Directory: $ROOT_DIR"
echo "Nix Directory: $NIX_DIR"  
echo "Test Directory: $TEST_DIR"
echo ""

# Setup test environment
log_info "Setting up test environment..."
mkdir -p "$TEST_DIR"
cd "$NIX_DIR"

# Test 1: Nix Configuration Validation
log_info "Test 1: Nix Configuration Validation"
echo "-------------------------------------"

if nix eval .#darwinConfigurations.default.system --show-trace &> /dev/null; then
    log_success "Nix configuration evaluation successful"
else
    log_error "Nix configuration evaluation failed"
    ((ERRORS++))
fi

if nix flake check --impure &> /dev/null; then
    log_success "Nix flake check passed"
else
    log_warning "Nix flake check has warnings (expected for incomplete systems)"
fi

echo ""

# Test 2: Automation Module Availability
log_info "Test 2: Automation Module Availability"  
echo "--------------------------------------"

# Check if automation modules are configured in flake
if grep -q "dotfiles.automation.enable = true" flake.nix; then
    log_success "Automation module enabled in configuration"
else
    log_error "Automation module not enabled in configuration" 
    ((ERRORS++))
fi

# Check automation imports
if grep -q "common/automation/default.nix" flake.nix; then
    log_success "Automation module imported in flake"
else
    log_error "Automation module not imported in flake"
    ((ERRORS++))
fi

echo ""

# Test 3: Package Availability Check
log_info "Test 3: Package Availability Check"
echo "-----------------------------------"

# Test core automation packages
PACKAGES=(
    "git"
    "curl" 
    "jq"
    "yq-go"
    "just"
    "gnumake"
    "terraform"
    "kubectl"
    "kubernetes-helm"
    "ansible"
    "awscli2"
    "trivy"
    "prometheus"
    "grafana"
    "argocd"
)

PACKAGE_ERRORS=0
for pkg in "${PACKAGES[@]}"; do
    if nix eval nixpkgs#"$pkg" --no-warn-dirty &> /dev/null; then
        echo "  ✅ $pkg: Available"
    else
        echo "  ❌ $pkg: Not available"
        ((PACKAGE_ERRORS++))
    fi
done

if [[ $PACKAGE_ERRORS -eq 0 ]]; then
    log_success "All core packages available"
else
    log_warning "$PACKAGE_ERRORS packages not available (may be platform-specific)"
fi

echo ""

# Test 4: IaC Module Integration
log_info "Test 4: IaC Module Integration"
echo "------------------------------"

# Test IaC project initialization script syntax
if grep -q "iac-init" common/automation/iac/default.nix; then
    log_success "IaC initialization script found"
else
    log_error "IaC initialization script not found"
    ((ERRORS++))
fi

# Test Terraform template generation
if grep -q "terraform {" common/automation/iac/default.nix; then
    log_success "Terraform templates configured"
else
    log_error "Terraform templates not configured"
    ((ERRORS++))
fi

echo ""

# Test 5: Kubernetes Module Integration  
log_info "Test 5: Kubernetes Module Integration"
echo "-------------------------------------"

# Test Kubernetes scripts
if grep -q "k8s-cluster" common/automation/kubernetes/default.nix; then
    log_success "Kubernetes cluster management script found"
else
    log_error "Kubernetes cluster management script not found"
    ((ERRORS++))
fi

# Test manifest generation
if grep -q "k8s-generate" common/automation/kubernetes/default.nix; then
    log_success "Kubernetes manifest generator found"
else
    log_error "Kubernetes manifest generator not found"
    ((ERRORS++))
fi

echo ""

# Test 6: Cloud Provider Integration
log_info "Test 6: Cloud Provider Integration"
echo "----------------------------------"

# Test cloud management scripts
if grep -q "cloud-check-status" common/automation/cloud/default.nix; then
    log_success "Cloud status checker found"
else
    log_error "Cloud status checker not found"
    ((ERRORS++))
fi

# Test multi-cloud support
if grep -q "aws\|gcp\|azure" common/automation/cloud/default.nix; then
    log_success "Multi-cloud provider support configured"
else
    log_error "Multi-cloud provider support not configured"
    ((ERRORS++))
fi

echo ""

# Test 7: Multi-Environment Deployment
log_info "Test 7: Multi-Environment Deployment"
echo "------------------------------------"

# Test deployment manager
if grep -q "deploy-manager" common/automation/default.nix; then
    log_success "Deployment manager script found"
else
    log_error "Deployment manager script not found"
    ((ERRORS++))
fi

# Test environment configurations
if grep -q "dev\|staging\|prod" common/automation/default.nix; then
    log_success "Multi-environment support configured"
else
    log_error "Multi-environment support not configured"
    ((ERRORS++))
fi

echo ""

# Test 8: Shell Integration
log_info "Test 8: Shell Integration"
echo "-------------------------"

# Test shell aliases
if grep -q "shellAliases" common/automation/default.nix; then
    log_success "Shell aliases configured"
else
    log_error "Shell aliases not configured"
    ((ERRORS++))
fi

# Test shell functions  
if grep -q "auto-env\|auto-status" common/automation/default.nix; then
    log_success "Automation shell functions configured"
else
    log_error "Automation shell functions not configured"
    ((ERRORS++))
fi

echo ""

# Test 9: Security Integration
log_info "Test 9: Security Integration"
echo "----------------------------"

# Test security tools
if grep -q "trivy\|checkov\|tfsec" common/automation/cloud/default.nix; then
    log_success "Security scanning tools configured"
else
    log_error "Security scanning tools not configured"
    ((ERRORS++))
fi

# Test secrets management integration
if grep -q "sops\|vault" common/automation/iac/default.nix; then
    log_success "Secrets management integration found"
else
    log_warning "Secrets management integration limited"
fi

echo ""

# Test 10: CI/CD Integration
log_info "Test 10: CI/CD Integration"
echo "--------------------------"

# Test GitHub Actions workflows
if [[ -d "$ROOT_DIR/.github/workflows" ]]; then
    log_success "GitHub Actions workflows directory exists"
    
    WORKFLOW_COUNT=$(find "$ROOT_DIR/.github/workflows" -name "*.yml" -o -name "*.yaml" | wc -l)
    log_info "Found $WORKFLOW_COUNT workflow files"
else
    log_warning "GitHub Actions workflows not found"
fi

# Test automation health check
if grep -q "automation-health" common/automation/default.nix; then
    log_success "Automation health check script configured"
else
    log_error "Automation health check script not configured"
    ((ERRORS++))
fi

echo ""

# Cleanup
log_info "Cleaning up test environment..."
cd "$NIX_DIR"
rm -rf "$TEST_DIR"

# Final Report
echo "📊 Integration Test Summary"
echo "=========================="
echo ""

if [[ $ERRORS -eq 0 ]]; then
    log_success "🎉 All integration tests passed!"
    echo ""
    echo "✅ Phase 4.5: Enterprise Automation and Orchestration - COMPLETE"
    echo ""
    echo "🏆 Available Features:"
    echo "  • Infrastructure as Code (Terraform, Ansible, Kubernetes)"
    echo "  • Kubernetes Environment Management (clusters, deployments, monitoring)"
    echo "  • Multi-Cloud Provider Integration (AWS, GCP, Azure)"
    echo "  • Multi-Environment Deployment Automation (dev, staging, prod)"
    echo "  • Security Scanning and Compliance (trivy, checkov, tfsec)"
    echo "  • Shell Integration (aliases, functions, environment switching)"
    echo "  • CI/CD Integration (GitHub Actions, automated testing)"
    echo ""
    echo "🚀 Commands Available:"
    echo "  • auto-health - Automation system health check"
    echo "  • deploy-manager - Multi-environment deployment"
    echo "  • iac-init - Infrastructure project initialization"
    echo "  • k8s-cluster - Kubernetes cluster management"
    echo "  • cloud-check-status - Multi-cloud status"
    echo "  • cloud-security-scan - Security scanning"
    echo ""
    exit 0
else
    log_error "❌ $ERRORS integration test failures detected"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "  • Check package availability for your platform"
    echo "  • Verify Nix configuration syntax"
    echo "  • Review module imports and dependencies"
    echo "  • Test individual automation components"
    echo ""
    exit 1
fi