{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Node.js runtime (pinned to LTS)
    nodejs_20
    
    # Package managers (avoid conflicts by using one primarily)
    nodePackages.npm
    # yarn and pnpm available but not auto-installed to avoid conflicts
    
    # Development tools (prefer local project versions)
    nodePackages.typescript-language-server
    
    # Optional global tools (comment out if using project-local versions)
    # nodePackages.typescript
    # nodePackages.eslint  
    # nodePackages.prettier
  ];
  
  shellHook = ''
    echo "🚀 Node.js development environment ready!"
    echo "Node: $(node --version)"
    echo "NPM: $(npm --version)"
    echo ""
    echo "📦 Available package managers:"
    echo "  • npm (primary)"
    echo "  • yarn (install with: npm install -g yarn)"
    echo "  • pnpm (install with: npm install -g pnpm)"
    echo ""
    echo "💡 Tips:"
    echo "  • Use 'npm install' for dependencies"
    echo "  • Install dev tools locally: npm install -D typescript eslint prettier"
    echo "  • TypeScript LSP available globally"
    
    # Create package.json if it doesn't exist
    if [ ! -f package.json ]; then
      echo ""
      echo "🔧 No package.json found. Create one with:"
      echo "  npm init -y"
    fi
    
    # Set NODE_ENV for development
    export NODE_ENV=development
    
    # Add local node_modules/.bin to PATH for project tools
    export PATH="$PWD/node_modules/.bin:$PATH"
  '';
}