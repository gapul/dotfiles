{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs
    nodePackages.npm
    nodePackages.typescript
    nodePackages.eslint
    nodePackages.prettier
    nodePackages.ts-node
  ];
  
  shellHook = ''
    echo "📦 Node.js development environment ready!"
    echo "Node: $(node --version)"
    echo "NPM: $(npm --version)"
    echo ""
    echo "Available tools: typescript, eslint, prettier, ts-node"
    export PATH="$PWD/node_modules/.bin:$PATH"
  '';
}
