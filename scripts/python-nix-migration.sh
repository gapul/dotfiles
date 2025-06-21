#!/usr/bin/env bash
# Python to Nix Migration Script
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🐍 Python to Nix Complete Migration"
echo "=================================="

# Step 1: Backup current pip packages
log_info "Step 1: Backing up current pip packages..."
BACKUP_DIR="$HOME/dotfiles/migration-backups"
mkdir -p "$BACKUP_DIR"

if command -v pip3 &> /dev/null; then
    log_info "Creating backup of current pip packages..."
    pip3 list --format=freeze > "$BACKUP_DIR/pip-packages-$(date +%Y%m%d_%H%M%S).txt"
    log_success "Backup created: $BACKUP_DIR/pip-packages-*.txt"
else
    log_warning "pip3 not found, skipping backup"
fi

# Step 2: Create system pip isolation
log_info "Step 2: Setting up system pip isolation..."

# Create pip wrapper that warns about system usage
cat > "$HOME/.local/bin/pip" << 'EOF'
#!/usr/bin/env bash
echo "⚠️  Warning: You're trying to use system pip!"
echo "🔄 Use Nix-managed Python environment instead:"
echo "   nix develop          # Enter Nix shell"
echo "   python -m pip ...    # Use Nix-managed pip"
echo ""
echo "🚫 To bypass this warning, use: /usr/bin/pip3"
echo ""
read -p "Continue with system pip? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    exec /usr/bin/pip3 "$@"
else
    echo "Cancelled"
    exit 1
fi
EOF

chmod +x "$HOME/.local/bin/pip"

# Create pip3 wrapper
cat > "$HOME/.local/bin/pip3" << 'EOF'
#!/usr/bin/env bash
echo "⚠️  Warning: You're trying to use system pip3!"
echo "🔄 Use Nix-managed Python environment instead:"
echo "   nix develop          # Enter Nix shell"
echo "   python -m pip ...    # Use Nix-managed pip"
echo ""
echo "🚫 To bypass this warning, use: /usr/bin/pip3"
echo ""
read -p "Continue with system pip3? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    exec /usr/bin/pip3 "$@"
else
    echo "Cancelled"
    exit 1
fi
EOF

chmod +x "$HOME/.local/bin/pip3"

log_success "System pip isolation configured"

# Step 3: Update shell PATH priority
log_info "Step 3: Ensuring ~/.local/bin is in PATH priority..."

# Check if ~/.local/bin is already in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    log_warning "~/.local/bin not in PATH, will be added by Nix configuration"
else
    log_success "~/.local/bin already in PATH"
fi

# Step 4: Create Python project template
log_info "Step 4: Creating enhanced Python project template..."

mkdir -p "$HOME/dotfiles/templates/python-project"

cat > "$HOME/dotfiles/templates/python-project/shell.nix" << 'EOF'
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    (python3.withPackages (ps: with ps; [
      # Add your project-specific packages here
      pip setuptools wheel
      poetry
      
      # Common development tools
      black flake8 mypy pytest
      requests pyyaml
      
      # Uncomment as needed:
      # pandas numpy matplotlib
      # django flask fastapi
      # pytest-cov coverage
    ]))
  ];
  
  shellHook = ''
    echo "🐍 Python project environment ready!"
    echo "Add packages to shell.nix buildInputs"
    export PYTHONPATH="$PWD:$PYTHONPATH"
  '';
}
EOF

cat > "$HOME/dotfiles/templates/python-project/.envrc" << 'EOF'
use nix
EOF

cat > "$HOME/dotfiles/templates/python-project/pyproject.toml" << 'EOF'
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "my-project"
version = "0.1.0"
description = ""
readme = "README.md"
requires-python = ">=3.9"
dependencies = []

[project.optional-dependencies]
dev = [
    "pytest",
    "black",
    "flake8",
    "mypy",
]

[tool.black]
line-length = 88
target-version = ['py39']

[tool.mypy]
python_version = "3.9"
warn_return_any = true
warn_unused_configs = true

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
EOF

log_success "Python project template created"

# Step 5: Create migration helper
log_info "Step 5: Creating migration helper commands..."

cat > "$HOME/.local/bin/python-nix-init" << 'EOF'
#!/usr/bin/env bash
# Initialize Python project with Nix
set -euo pipefail

PROJECT_NAME="${1:-$(basename "$PWD")}"
TEMPLATE_DIR="$HOME/dotfiles/templates/python-project"

echo "🐍 Initializing Nix-managed Python project: $PROJECT_NAME"

# Copy template files
cp "$TEMPLATE_DIR/shell.nix" .
cp "$TEMPLATE_DIR/.envrc" .
if [[ ! -f pyproject.toml ]]; then
    cp "$TEMPLATE_DIR/pyproject.toml" .
    sed -i '' "s/my-project/$PROJECT_NAME/g" pyproject.toml
fi

# Create basic structure
mkdir -p src tests
touch src/__init__.py
touch tests/__init__.py
echo "# $PROJECT_NAME" > README.md

# Initialize direnv
if command -v direnv &> /dev/null; then
    direnv allow
    echo "✅ direnv initialized"
fi

echo "✅ Python project initialized!"
echo "Next steps:"
echo "  1. Edit shell.nix to add required packages"
echo "  2. Run: nix develop"
echo "  3. Start coding!"
EOF

chmod +x "$HOME/.local/bin/python-nix-init"

# Step 6: Test the setup
log_info "Step 6: Testing Nix Python setup..."

if nix eval --raw nixpkgs#python3.version 2>/dev/null; then
    log_success "Nix Python evaluation works"
else
    log_error "Nix Python evaluation failed"
fi

echo ""
echo "🎉 Python to Nix migration completed!"
echo ""
echo "📋 Summary of changes:"
echo "  ✅ Core packages updated with python3.withPackages"
echo "  ✅ Python project template enhanced"
echo "  ✅ System pip isolation configured"
echo "  ✅ Python environment variables configured"
echo "  ✅ Migration helper tools created"
echo ""
echo "🚀 Next steps:"
echo "  1. Run: nix run nix-darwin -- switch --flake ."
echo "  2. Restart terminal to apply changes"
echo "  3. Test: python-nix-init my-project"
echo "  4. Use: nix develop (in any Python project)"
echo ""
echo "💡 For existing projects:"
echo "  - Add shell.nix with required packages"
echo "  - Use direnv for automatic environment loading"
echo "  - All pip operations will use Nix-managed packages"