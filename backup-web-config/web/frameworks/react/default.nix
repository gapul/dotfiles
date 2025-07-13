# Web開発環境 - React フレームワーク統合
# React、Next.js、Remix、Vite + Reactの統合

{ lib, pkgs, config, ... }:

with lib;

{
  imports = [
    ./nextjs.nix
  ];

  options.web.frameworks.react = {
    enable = mkEnableOption "React development environment";
    
    version = mkOption {
      type = types.str;
      default = "18";
      description = "React version";
    };
    
    frameworks = mkOption {
      type = types.listOf (types.enum [ "nextjs" "remix" "vite" "create-react-app" ]);
      default = [ "nextjs" "vite" ];
      description = "React frameworks to enable";
    };
    
    typescript = mkOption {
      type = types.bool;
      default = true;
      description = "Enable TypeScript support";
    };
    
    testing = {
      framework = mkOption {
        type = types.enum [ "vitest" "jest" ];
        default = "vitest";
        description = "Testing framework";
      };
      
      library = mkOption {
        type = types.enum [ "testing-library" "enzyme" ];
        default = "testing-library";
        description = "Testing library";
      };
    };
    
    styling = mkOption {
      type = types.enum [ "tailwind" "styled-components" "emotion" "css-modules" ];
      default = "tailwind";
      description = "Default styling solution";
    };
  };

  config = mkIf config.web.frameworks.react.enable {
    # Enable specific React frameworks
    web.frameworks.react.nextjs.enable = mkDefault (elem "nextjs" config.web.frameworks.react.frameworks);
    
    # React development packages
    home-manager.users.yuki.home.packages = with pkgs; [
      nodejs_22
      nodePackages.npm
      nodePackages.pnpm
      bun
      
      # React development tools
      nodePackages.typescript
      nodePackages.eslint
      nodePackages.prettier
      
      # Testing tools
      nodePackages.vitest
      nodePackages.jest
    ];
    
    # Default React + Vite template
    home-manager.users.yuki.home.file.".react-templates/vite-react.template.json" = {
      text = builtins.toJSON {
        name = "react-vite-app";
        version = "0.1.0";
        private = true;
        type = "module";
        scripts = {
          dev = "vite";
          build = "vite build";
          preview = "vite preview";
          lint = "eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0";
          "lint:fix" = "eslint . --ext ts,tsx --fix";
          test = "vitest";
          "test:watch" = "vitest --watch";
          "test:coverage" = "vitest --coverage";
        } // optionalAttrs config.web.frameworks.react.typescript {
          "type-check" = "tsc --noEmit";
        };
        dependencies = {
          react = "^${config.web.frameworks.react.version}";
          "react-dom" = "^${config.web.frameworks.react.version}";
        } // optionalAttrs (config.web.frameworks.react.styling == "tailwind") {
          tailwindcss = "^3.3.0";
          autoprefixer = "^10.4.14";
          postcss = "^8.4.24";
        } // optionalAttrs (config.web.frameworks.react.styling == "styled-components") {
          "styled-components" = "^6.0.0";
        } // optionalAttrs (config.web.frameworks.react.styling == "emotion") {
          "@emotion/react" = "^11.11.0";
          "@emotion/styled" = "^11.11.0";
        };
        devDependencies = {
          "@vitejs/plugin-react-swc" = "^3.3.2";
          vite = "^4.4.5";
          eslint = "^8.45.0";
          "eslint-plugin-react" = "^7.32.2";
          "eslint-plugin-react-hooks" = "^4.6.0";
          "eslint-plugin-react-refresh" = "^0.4.3";
          vitest = "^1.0.0";
          "@testing-library/react" = "^13.4.0";
          "@testing-library/jest-dom" = "^5.16.4";
          jsdom = "^22.1.0";
        } // optionalAttrs config.web.frameworks.react.typescript {
          typescript = "^5.0.2";
          "@types/react" = "^18.2.15";
          "@types/react-dom" = "^18.2.7";
          "@typescript-eslint/eslint-plugin" = "^6.0.0";
          "@typescript-eslint/parser" = "^6.0.0";
        } // optionalAttrs (config.web.frameworks.react.styling == "styled-components") {
          "@types/styled-components" = "^5.1.26";
        };
      };
    };
    
    # Vite configuration for React
    home-manager.users.yuki.home.file.".react-templates/vite.config.template.ts" = {
      text = ''
        import { defineConfig } from 'vite'
        import react from '@vitejs/plugin-react-swc'
        import path from 'path'
        
        export default defineConfig({
          plugins: [react()],
          
          resolve: {
            alias: {
              '@': path.resolve(__dirname, './src'),
              '@/components': path.resolve(__dirname, './src/components'),
              '@/lib': path.resolve(__dirname, './src/lib'),
              '@/styles': path.resolve(__dirname, './src/styles'),
            },
          },
          
          server: {
            host: '0.0.0.0',
            port: 3000,
            open: true,
            hmr: {
              overlay: true
            }
          },
          
          build: {
            target: 'esnext',
            minify: 'esbuild',
            sourcemap: false,
            rollupOptions: {
              output: {
                manualChunks: {
                  vendor: ['react', 'react-dom'],
                }
              }
            }
          },
          
          test: {
            globals: true,
            environment: 'jsdom',
            setupFiles: ['./src/test/setup.ts'],
            css: true,
          },
          
          optimizeDeps: {
            include: ['react', 'react-dom']
          }
        })
      '';
    };
    
    # Shell aliases for React development
    home-manager.users.yuki.home.shellAliases = {
      # React project creation
      "react-init" = "npm create vite@latest";
      "react-vite" = "npm create vite@latest";
      "create-react" = "npm create react-app";
      
      # Development shortcuts
      "react-dev" = "npm run dev";
      "react-build" = "npm run build";
      "react-test" = "npm test";
      "react-lint" = "npm run lint";
      
      # Framework-specific shortcuts
      "next-init" = "nextjs-init";
      "remix-init" = "npx create-remix@latest";
    };
    
    # React project initialization script
    home-manager.users.yuki.home.file."bin/react-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        show_usage() {
          cat << EOF
        Usage: react-init <project-name> [framework] [options]
        
        FRAMEWORKS:
          vite         React with Vite (default)
          nextjs       Next.js application
          remix        Remix application
          cra          Create React App
          
        OPTIONS:
          --typescript Enable TypeScript (default: ${if config.web.frameworks.react.typescript then "true" else "false"})
          --styling    Styling solution (tailwind, styled-components, emotion, css-modules)
          --dir DIR    Create in specific directory
          
        EXAMPLES:
          react-init my-app
          react-init my-app nextjs --typescript
          react-init my-app vite --styling tailwind
        EOF
        }
        
        PROJECT_NAME="$1"
        FRAMEWORK="''${2:-vite}"
        shift 2 2>/dev/null || shift 1
        
        if [[ -z "$PROJECT_NAME" ]]; then
          echo "❌ Project name required"
          show_usage
          exit 1
        fi
        
        # Parse options
        USE_TYPESCRIPT=${config.web.frameworks.react.typescript}
        STYLING="${config.web.frameworks.react.styling}"
        TARGET_DIR="."
        
        while [[ $# -gt 0 ]]; do
          case $1 in
            --typescript)
              USE_TYPESCRIPT=true
              shift
              ;;
            --styling)
              STYLING="$2"
              shift 2
              ;;
            --dir)
              TARGET_DIR="$2"
              shift 2
              ;;
            -h|--help)
              show_usage
              exit 0
              ;;
            *)
              echo "Unknown option: $1"
              show_usage
              exit 1
              ;;
          esac
        done
        
        echo "⚛️  Creating React project: $PROJECT_NAME"
        echo "Framework: $FRAMEWORK"
        echo "TypeScript: $USE_TYPESCRIPT"
        echo "Styling: $STYLING"
        echo "Directory: $TARGET_DIR"
        echo ""
        
        # Create project based on framework
        case "$FRAMEWORK" in
          vite)
            echo "⚡ Creating Vite + React project..."
            cd "$TARGET_DIR"
            
            if [[ "$USE_TYPESCRIPT" == "true" ]]; then
              npm create vite@latest "$PROJECT_NAME" -- --template react-ts
            else
              npm create vite@latest "$PROJECT_NAME" -- --template react
            fi
            
            cd "$PROJECT_NAME"
            npm install
            
            # Add styling dependencies
            case "$STYLING" in
              tailwind)
                npm install -D tailwindcss postcss autoprefixer @tailwindcss/forms @tailwindcss/typography
                npx tailwindcss init -p
                ;;
              styled-components)
                if [[ "$USE_TYPESCRIPT" == "true" ]]; then
                  npm install styled-components @types/styled-components
                else
                  npm install styled-components
                fi
                ;;
              emotion)
                npm install @emotion/react @emotion/styled
                ;;
            esac
            
            # Add testing dependencies
            npm install -D @testing-library/react @testing-library/jest-dom jsdom
            ;;
            
          nextjs)
            echo "🚀 Creating Next.js project..."
            nextjs-init "$PROJECT_NAME" --dir "$TARGET_DIR"
            return 0
            ;;
            
          remix)
            echo "💿 Creating Remix project..."
            cd "$TARGET_DIR"
            if [[ "$USE_TYPESCRIPT" == "true" ]]; then
              npx create-remix@latest "$PROJECT_NAME" --template typescript
            else
              npx create-remix@latest "$PROJECT_NAME"
            fi
            ;;
            
          cra)
            echo "📦 Creating Create React App project..."
            cd "$TARGET_DIR"
            if [[ "$USE_TYPESCRIPT" == "true" ]]; then
              npx create-react-app "$PROJECT_NAME" --template typescript
            else
              npx create-react-app "$PROJECT_NAME"
            fi
            ;;
            
          *)
            echo "❌ Unknown framework: $FRAMEWORK"
            show_usage
            exit 1
            ;;
        esac
        
        echo ""
        echo "✅ React project created successfully!"
        echo ""
        echo "📁 Project: $TARGET_DIR/$PROJECT_NAME"
        echo "🔧 Framework: $FRAMEWORK"
        echo ""
        echo "🚀 Next steps:"
        echo "  cd $TARGET_DIR/$PROJECT_NAME"
        echo "  npm run dev"
      '';
    };
    
    # React health check
    home-manager.users.yuki.home.file."bin/react-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "⚛️  React Development Environment Health Check"
        echo "==========================================="
        
        # Check React environment
        echo "🔧 React Environment:"
        
        if npx react --version &> /dev/null 2>&1; then
          echo "✅ React CLI: available"
        else
          echo "⚪ React CLI: not available (this is normal)"
        fi
        
        # Check framework tools
        echo ""
        echo "🏗️  Framework Tools:"
        
        frameworks=(
          ${concatMapStringsSep "\n          " (fw: ''"${fw}"'') config.web.frameworks.react.frameworks}
        )
        
        for framework in "''${frameworks[@]}"; do
          case "$framework" in
            nextjs)
              if command -v nextjs-health &> /dev/null; then
                echo "✅ Next.js: configured"
              else
                echo "❌ Next.js: not properly configured"
              fi
              ;;
            vite)
              if npx vite --version &> /dev/null; then
                echo "✅ Vite: $(npx vite --version)"
              else
                echo "❌ Vite: not available"
              fi
              ;;
            remix)
              if npx remix --version &> /dev/null; then
                echo "✅ Remix: available"
              else
                echo "❌ Remix: not available"
              fi
              ;;
          esac
        done
        
        # Check testing tools
        echo ""
        echo "🧪 Testing Environment:"
        
        if npx vitest --version &> /dev/null; then
          echo "✅ Vitest: $(npx vitest --version)"
        else
          echo "❌ Vitest: not available"
        fi
        
        # Current project check
        echo ""
        echo "📁 Current Project:"
        
        if [[ -f "package.json" ]]; then
          if jq -e '.dependencies.react' package.json > /dev/null 2>&1; then
            react_version=$(jq -r '.dependencies.react' package.json)
            project_name=$(jq -r '.name' package.json)
            echo "✅ React project: $project_name"
            echo "   React version: $react_version"
            
            # Detect framework
            if jq -e '.dependencies.next' package.json > /dev/null 2>&1; then
              echo "🚀 Framework: Next.js"
            elif jq -e '.dependencies."@remix-run/react"' package.json > /dev/null 2>&1; then
              echo "💿 Framework: Remix"
            elif jq -e '.devDependencies."@vitejs/plugin-react"' package.json > /dev/null 2>&1; then
              echo "⚡ Framework: Vite + React"
            elif jq -e '.dependencies."react-scripts"' package.json > /dev/null 2>&1; then
              echo "📦 Framework: Create React App"
            fi
            
            # Check TypeScript
            if [[ -f "tsconfig.json" ]]; then
              echo "✅ TypeScript: configured"
            else
              echo "⚪ TypeScript: not configured"
            fi
            
          else
            echo "⚪ Not a React project"
          fi
        else
          echo "⚪ No package.json found"
        fi
        
        echo ""
        echo "📊 Configuration:"
        echo "React version: ${config.web.frameworks.react.version}"
        echo "TypeScript: ${if config.web.frameworks.react.typescript then "enabled" else "disabled"}"
        echo "Testing: ${config.web.frameworks.react.testing.framework}"
        echo "Styling: ${config.web.frameworks.react.styling}"
        echo "Frameworks: ${toString config.web.frameworks.react.frameworks}"
        
        echo ""
        echo "✅ React health check completed!"
      '';
    };
  };
}