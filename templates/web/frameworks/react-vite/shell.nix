# React + Vite 開発環境
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Node.js environment
    nodejs_22
    nodePackages.npm
    nodePackages.pnpm
    
    # TypeScript and tools
    nodePackages.typescript
    nodePackages.typescript-language-server
    
    # React development
    nodePackages.eslint
    nodePackages.prettier
    
    # Build tools
    vite
  ];

  shellHook = ''
    echo "🚀 React + Vite development environment"
    echo "📦 Node.js: $(node --version)"
    echo "📦 npm: $(npm --version)"
    echo "📦 TypeScript: $(tsc --version)"
    echo ""
    echo "Available commands:"
    echo "  npm run dev     - Start development server"
    echo "  npm run build   - Build for production"
    echo "  npm run preview - Preview production build"
    echo "  npm run lint    - Lint code"
    echo ""
  '';
}