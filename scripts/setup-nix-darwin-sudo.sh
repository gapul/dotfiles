#!/usr/bin/env bash
# Setup sudoers configuration to eliminate nix-darwin warnings
set -euo pipefail

echo "🔧 Setting up sudoers for nix-darwin warning elimination"
echo "======================================================="

# Create sudoers configuration file
SUDOERS_FILE="/etc/sudoers.d/nix-darwin"

# Check if we have sudo access
if ! sudo -v; then
    echo "❌ This script requires sudo access"
    exit 1
fi

echo "📝 Creating sudoers configuration..."

# Create the sudoers configuration
sudo tee "$SUDOERS_FILE" > /dev/null << 'EOF'
# nix-darwin sudoers configuration
# Allows nix-darwin to run with proper environment preservation

# Preserve environment variables for nix-darwin
Defaults env_keep += "HOME USER"

# Allow admin users to run nix-darwin commands with preserved environment
%admin ALL=(ALL) SETENV: /nix/store/*/bin/nix
%admin ALL=(ALL) SETENV: /usr/bin/nix
%admin ALL=(ALL) SETENV: /opt/nix/bin/nix
%admin ALL=(ALL) SETENV: /nix/store/*/bin/darwin-rebuild

# Allow specific nix-darwin related commands
%admin ALL=(ALL) NOPASSWD: /nix/store/*/bin/darwin-rebuild
EOF

# Validate sudoers syntax
echo "🔍 Validating sudoers configuration..."
if sudo visudo -c -f "$SUDOERS_FILE"; then
    echo "✅ Sudoers configuration validated successfully"
else
    echo "❌ Invalid sudoers configuration, removing..."
    sudo rm -f "$SUDOERS_FILE"
    exit 1
fi

# Set proper permissions
sudo chmod 440 "$SUDOERS_FILE"

echo ""
echo "✅ nix-darwin sudoers setup complete!"
echo "📋 Configuration applied:"
echo "   - Environment variables preserved (HOME, USER)"
echo "   - nix-darwin commands allowed with SETENV"
echo "   - Proper file permissions set"
echo ""
echo "🔄 Now you can run nix-darwin switch without warnings:"
echo "   sudo nix run nix-darwin -- switch --flake . --impure"
echo ""
echo "⚠️  If you still see warnings, they should be minimal and non-functional"