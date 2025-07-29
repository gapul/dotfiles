# Vue.js + TypeScript Development Environment
# Complete setup for modern Vue development with Vite, TypeScript, and testing tools

{ pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
    };
  }
, lib ? pkgs.lib
, stdenv ? pkgs.stdenv
}:

let
  # Development scripts
  setupScript = pkgs.writeShellScriptBin "setup-vue" ''
    set -e
    
    echo "🚀 Setting up Vue.js + TypeScript development environment..."
    
    # Install global tools
    npm install -g @vue/cli@latest
    npm install -g create-vue@latest
    npm install -g vite@latest
    npm install -g @vitejs/create-app@latest
    
    # Verify installations
    echo "🔍 Verifying installations..."
    node --version
    npm --version
    vue --version
    vite --version
    
    echo ""
    echo "🎯 Quick start:"
    echo "  npm create vue@latest myapp"
    echo "  cd myapp"
    echo "  npm install"
    echo "  npm run dev"
    echo ""
    echo "✅ Vue.js environment ready!"
  '';

  devScript = pkgs.writeShellScriptBin "vue-dev" ''
    case "$1" in
      create)
        echo "🆕 Creating new Vue.js project..."
        npm create vue@latest "$2"
        ;;
      dev)
        echo "🔥 Starting development server..."
        npm run dev
        ;;
      build)
        echo "🏗️ Building for production..."
        npm run build
        ;;
      preview)
        echo "👀 Previewing production build..."
        npm run preview
        ;;
      test)
        echo "🧪 Running tests..."
        npm run test:unit
        ;;
      test:e2e)
        echo "🎭 Running E2E tests..."
        npm run test:e2e
        ;;
      lint)
        echo "🔍 Running ESLint..."
        npm run lint
        ;;
      format)
        echo "💅 Formatting code..."
        npm run format
        ;;
      type-check)
        echo "🔧 Running TypeScript check..."
        npm run type-check
        ;;
      analyze)
        echo "📊 Analyzing bundle..."
        npx vite-bundle-analyzer
        ;;
      clean)
        echo "🧹 Cleaning project..."
        rm -rf dist
        rm -rf node_modules
        rm -rf .nuxt
        npm install
        ;;
      storybook)
        echo "📚 Starting Storybook..."
        npm run storybook
        ;;
      *)
        echo "💚 Vue.js Development Commands"
        echo ""
        echo "Usage: vue-dev <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create <name>  Create new Vue.js project"
        echo "  dev           Start development server"
        echo "  build         Build for production"
        echo "  preview       Preview production build"
        echo "  test          Run unit tests"
        echo "  test:e2e      Run E2E tests"
        echo "  lint          Run ESLint"
        echo "  format        Format code with Prettier"
        echo "  type-check    Run TypeScript check"
        echo "  analyze       Analyze bundle size"
        echo "  clean         Clean project"
        echo "  storybook     Start Storybook"
        ;;
    esac
  '';

in pkgs.mkShell {
  name = "vue-typescript-dev";
  
  buildInputs = with pkgs; [
    # Core development tools
    nodejs_20
    npm
    yarn
    pnpm
    git
    
    # Development utilities
    setupScript
    devScript
    
    # Browser testing tools
    chromium
    playwright
    cypress
    
    # Additional tools
    jq
    curl
    
    # Language servers and formatters
    nodePackages.typescript-language-server
    nodePackages.vscode-langservers-extracted
    nodePackages.prettier
    nodePackages.eslint
  ];

  shellHook = ''
    # Vue.js environment
    export NODE_ENV="development"
    export VITE_NODE_ENV="development"
    
    # Browser setup for testing
    export PLAYWRIGHT_BROWSERS_PATH="$HOME/.cache/playwright"
    export CYPRESS_CACHE_FOLDER="$HOME/.cache/cypress"
    
    # Performance optimizations
    export VITE_CJS_IGNORE_WARNING=true
    export NODE_OPTIONS="--max-old-space-size=4096"
    
    echo "💚 Vue.js + TypeScript Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Node.js: $(node --version)"
    echo "💚 Vue CLI: $(vue --version)"
    echo "⚡ Vite: $(vite --version)"
    echo "🎭 Playwright: Available"
    echo "🌲 Cypress: Available"
    echo ""
    echo "🛠️ Available commands:"
    echo "  setup-vue     # Initial environment setup"
    echo "  vue-dev       # Development commands"
    echo ""
    echo "📚 Quick start:"
    echo "  vue-dev create myapp"
    echo "  cd myapp && npm install"
    echo "  vue-dev dev"
    echo ""
    echo "🧪 Testing:"
    echo "  vue-dev test      # Unit tests with Vitest"
    echo "  vue-dev test:e2e  # E2E tests with Playwright/Cypress"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '';
}