{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs
    nodePackages.npm
    nodePackages.yarn
    nodePackages.pnpm
    nodePackages.typescript
    nodePackages.eslint
    nodePackages.prettier
  ];
  
  shellHook = ''
    echo "🚀 Node.js development environment ready!"
    echo "Node: $(node --version)"
    echo "NPM: $(npm --version)"
    
    # Create package.json if it doesn't exist
    if [ ! -f package.json ]; then
      echo "Creating package.json..."
      npm init -y
    fi
  '';
}