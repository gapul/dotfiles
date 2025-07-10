# Web開発環境 - Next.js 15+ App Router統合
# Next.js、Turbopack、App Router、Server Componentsの統合

{ lib, pkgs, config, ... }:

let
  cfg = config.web.frameworks.react.nextjs;
in
{
  options.web.frameworks.react.nextjs = {
    enable = lib.mkEnableOption "Next.js development environment";
    
    version = lib.mkOption {
      type = lib.types.str;
      default = "15";
      description = "Next.js version";
    };
    
    router = lib.mkOption {
      type = lib.types.enum [ "app" "pages" "both" ];
      default = "app";
      description = "Next.js router type";
    };
    
    turbopack = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Turbopack bundler";
      };
      
      development = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use Turbopack in development";
      };
      
      build = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use Turbopack for production builds (experimental)";
      };
    };
    
    features = {
      serverComponents = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable React Server Components";
      };
      
      appRouter = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable App Router";
      };
      
      typescript = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TypeScript support";
      };
      
      tailwindcss = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Tailwind CSS";
      };
      
      eslint = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable ESLint configuration";
      };
      
      pwa = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable PWA support";
      };
      
      analytics = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Next.js Analytics";
      };
    };
    
    deployment = {
      vercel = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Optimize for Vercel deployment";
      };
      
      static = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable static export";
      };
      
      edge = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Edge Runtime support";
      };
    };
    
    optimization = {
      images = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Next.js Image optimization";
      };
      
      fonts = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Next.js Font optimization";
      };
      
      bundle = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable bundle optimization";
      };
      
      compression = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable compression";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Next.js project dependencies
    home.packages = with pkgs; [
      nodejs_22
      nodePackages.npm
      nodePackages.pnpm
      bun
      
      # Development tools
      nodePackages.typescript
      nodePackages.eslint
      nodePackages.prettier
      
      # Build tools
      nodePackages.postcss-cli
      nodePackages.autoprefixer
      
      # Testing tools
      nodePackages.jest
      nodePackages.vitest
    ];
    
    # Default Next.js configuration template
    home.file.".nextjs-templates/next.config.template.js" = {
      text = ''
        /** @type {import('next').NextConfig} */
        const nextConfig = {
          // App Router configuration
          ${lib.optionalString cfg.features.appRouter ''
          experimental: {
            appDir: true,
            ${lib.optionalString cfg.features.serverComponents "serverComponents: true,"}
            ${lib.optionalString cfg.turbopack.build "turbo: { rules: { '*.svg': { loaders: ['@svgr/webpack'], as: '*.js' } } },"}
            ${lib.optionalString cfg.deployment.edge "runtime: 'edge',"}
          },
          ''}
          
          // TypeScript configuration
          ${lib.optionalString cfg.features.typescript ''
          typescript: {
            ignoreBuildErrors: false,
          },
          ''}
          
          // ESLint configuration
          ${lib.optionalString cfg.features.eslint ''
          eslint: {
            ignoreDuringBuilds: false,
            dirs: ['pages', 'components', 'lib', 'src', 'app'],
          },
          ''}
          
          // Image optimization
          ${lib.optionalString cfg.optimization.images ''
          images: {
            domains: [],
            formats: ['image/webp', 'image/avif'],
            minimumCacheTTL: 60,
            dangerouslyAllowSVG: true,
            contentSecurityPolicy: "default-src 'self'; script-src 'none'; sandbox;",
          },
          ''}
          
          // Compression
          ${lib.optionalString cfg.optimization.compression ''
          compress: true,
          ''}
          
          // Bundle optimization
          ${lib.optionalString cfg.optimization.bundle ''
          webpack: (config, { buildId, dev, isServer, defaultLoaders, webpack }) => {
            // Bundle analyzer in development
            if (dev && !isServer) {
              config.plugins.push(
                new (require('webpack-bundle-analyzer').BundleAnalyzerPlugin)({
                  analyzerMode: 'disabled',
                  generateStatsFile: true,
                  statsOptions: { source: false }
                })
              );
            }
            
            // Optimize chunks
            config.optimization = {
              ...config.optimization,
              splitChunks: {
                chunks: 'all',
                cacheGroups: {
                  default: false,
                  vendors: false,
                  vendor: {
                    name: 'vendor',
                    chunks: 'all',
                    test: /node_modules/,
                    priority: 20
                  },
                  common: {
                    name: 'common',
                    minChunks: 2,
                    chunks: 'all',
                    priority: 10,
                    reuseExistingChunk: true,
                    enforce: true
                  }
                }
              }
            };
            
            return config;
          },
          ''}
          
          // Static export configuration
          ${lib.optionalString cfg.deployment.static ''
          output: 'export',
          trailingSlash: true,
          ''}
          
          // Vercel optimization
          ${lib.optionalString cfg.deployment.vercel ''
          env: {
            VERCEL_URL: process.env.VERCEL_URL,
          },
          ''}
          
          // PWA configuration
          ${lib.optionalString cfg.features.pwa ''
          pwa: {
            dest: 'public',
            disable: process.env.NODE_ENV === 'development',
            register: true,
            skipWaiting: true,
          },
          ''}
          
          // Performance optimizations
          poweredByHeader: false,
          reactStrictMode: true,
          swcMinify: true,
          
          // Development configuration
          ${lib.optionalString cfg.turbopack.development ''
          ...(process.env.NODE_ENV === 'development' && {
            experimental: {
              ...nextConfig.experimental,
              turbo: {
                loaders: {
                  '.svg': ['@svgr/webpack'],
                },
              },
            },
          }),
          ''}
        };
        
        ${lib.optionalString cfg.features.pwa ''
        const withPWA = require('next-pwa')({
          dest: 'public',
          disable: process.env.NODE_ENV === 'development',
        });
        
        module.exports = withPWA(nextConfig);
        ''}
        
        ${lib.optionalString (!cfg.features.pwa) ''
        module.exports = nextConfig;
        ''}
      '';
    };
    
    # TypeScript configuration for Next.js
    home.file.".nextjs-templates/tsconfig.template.json" = lib.mkIf cfg.features.typescript {
      text = builtins.toJSON {
        compilerOptions = {
          target = "es5";
          lib = [ "dom" "dom.iterable" "es6" ];
          allowJs = true;
          skipLibCheck = true;
          strict = true;
          noEmit = true;
          esModuleInterop = true;
          module = "esnext";
          moduleResolution = "bundler";
          resolveJsonModule = true;
          isolatedModules = true;
          jsx = "preserve";
          incremental = true;
          plugins = [
            {
              name = "next";
            }
          ];
          baseUrl = ".";
          paths = {
            "@/*" = [ "./src/*" ];
            "@/components/*" = [ "./src/components/*" ];
            "@/lib/*" = [ "./src/lib/*" ];
            "@/styles/*" = [ "./src/styles/*" ];
          };
        };
        include = [ "next-env.d.ts" "**/*.ts" "**/*.tsx" ".next/types/**/*.ts" ];
        exclude = [ "node_modules" ];
      };
    };
    
    # Tailwind CSS configuration
    home.file.".nextjs-templates/tailwind.config.template.js" = lib.mkIf cfg.features.tailwindcss {
      text = ''
        /** @type {import('tailwindcss').Config} */
        module.exports = {
          content: [
            './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
            './src/components/**/*.{js,ts,jsx,tsx,mdx}',
            './src/app/**/*.{js,ts,jsx,tsx,mdx}',
          ],
          theme: {
            extend: {
              colors: {
                background: 'hsl(var(--background))',
                foreground: 'hsl(var(--foreground))',
                primary: {
                  DEFAULT: 'hsl(var(--primary))',
                  foreground: 'hsl(var(--primary-foreground))',
                },
                secondary: {
                  DEFAULT: 'hsl(var(--secondary))',
                  foreground: 'hsl(var(--secondary-foreground))',
                },
                muted: {
                  DEFAULT: 'hsl(var(--muted))',
                  foreground: 'hsl(var(--muted-foreground))',
                },
                accent: {
                  DEFAULT: 'hsl(var(--accent))',
                  foreground: 'hsl(var(--accent-foreground))',
                },
                destructive: {
                  DEFAULT: 'hsl(var(--destructive))',
                  foreground: 'hsl(var(--destructive-foreground))',
                },
                border: 'hsl(var(--border))',
                input: 'hsl(var(--input))',
                ring: 'hsl(var(--ring))',
              },
              borderRadius: {
                lg: 'var(--radius)',
                md: 'calc(var(--radius) - 2px)',
                sm: 'calc(var(--radius) - 4px)',
              },
              fontFamily: {
                sans: ['var(--font-inter)', 'system-ui', 'sans-serif'],
                mono: ['var(--font-geist-mono)', 'monospace'],
              },
            },
          },
          plugins: [
            require('@tailwindcss/forms'),
            require('@tailwindcss/typography'),
            require('@tailwindcss/aspect-ratio'),
          ],
        };
      '';
    };
    
    # ESLint configuration for Next.js
    home.file.".nextjs-templates/.eslintrc.template.json" = lib.mkIf cfg.features.eslint {
      text = builtins.toJSON {
        extends = [
          "next/core-web-vitals"
        ] ++ lib.optionals cfg.features.typescript [
          "@typescript-eslint/recommended"
        ];
        parser = if cfg.features.typescript then "@typescript-eslint/parser" else null;
        plugins = lib.optionals cfg.features.typescript [ "@typescript-eslint" ];
        rules = {
          "react/no-unescaped-entities" = "off";
          "@next/next/no-page-custom-font" = "off";
          "prefer-const" = "error";
          "no-unused-vars" = "warn";
          "no-console" = "warn";
        } // lib.optionalAttrs cfg.features.typescript {
          "@typescript-eslint/no-unused-vars" = "warn";
          "@typescript-eslint/no-explicit-any" = "warn";
        };
      };
    };
    
    # Package.json template for Next.js projects
    home.file.".nextjs-templates/package.template.json" = {
      text = builtins.toJSON {
        name = "nextjs-app";
        version = "0.1.0";
        private = true;
        scripts = {
          dev = if cfg.turbopack.development then "next dev --turbo" else "next dev";
          build = if cfg.turbopack.build then "next build --turbo" else "next build";
          start = "next start";
          lint = "next lint";
          "lint:fix" = "next lint --fix";
          "type-check" = lib.mkIf cfg.features.typescript "tsc --noEmit";
          test = "vitest";
          "test:watch" = "vitest --watch";
          "test:coverage" = "vitest --coverage";
          analyze = "cross-env ANALYZE=true next build";
          "build-stats" = "cross-env ANALYZE=true npm run build";
        };
        dependencies = {
          next = "^${cfg.version}";
          react = "^18";
          "react-dom" = "^18";
        } // lib.optionalAttrs cfg.features.typescript {
          "@types/node" = "^20";
          "@types/react" = "^18";
          "@types/react-dom" = "^18";
          typescript = "^5";
        } // lib.optionalAttrs cfg.features.tailwindcss {
          tailwindcss = "^3.3.0";
          autoprefixer = "^10.4.14";
          postcss = "^8.4.24";
          "@tailwindcss/forms" = "^0.5.3";
          "@tailwindcss/typography" = "^0.5.9";
          "@tailwindcss/aspect-ratio" = "^0.4.2";
        } // lib.optionalAttrs cfg.features.pwa {
          "next-pwa" = "^5.6.0";
        } // lib.optionalAttrs cfg.optimization.fonts {
          "@next/font" = "^${cfg.version}";
        };
        devDependencies = {
          eslint = "^8";
          "eslint-config-next" = "^${cfg.version}";
          "cross-env" = "^7.0.3";
          "@next/bundle-analyzer" = "^${cfg.version}";
          vitest = "^1.0.0";
          "@vitejs/plugin-react" = "^4.0.0";
        } // lib.optionalAttrs cfg.features.typescript {
          "@typescript-eslint/eslint-plugin" = "^6.0.0";
          "@typescript-eslint/parser" = "^6.0.0";
        } // lib.optionalAttrs cfg.features.tailwindcss {
          "tailwindcss" = "^3.3.0";
        };
      };
    };
    
    # Shell aliases for Next.js development
    home.shellAliases = {
      # Next.js project management
      "next-init" = "npx create-next-app@latest";
      "next-dev" = if cfg.turbopack.development then "npm run dev -- --turbo" else "npm run dev";
      "next-build" = "npm run build";
      "next-start" = "npm run start";
      "next-lint" = "npm run lint";
      "next-test" = "npm test";
      
      # Development shortcuts
      "ndev" = "next-dev";
      "nbuild" = "next-build";
      "nlint" = "next-lint";
      "ntest" = "next-test";
      
      # Analysis
      "next-analyze" = "npm run analyze";
      "bundle-size" = "npm run build-stats";
    };
    
    # Next.js project initialization script
    home.file."bin/nextjs-init" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        show_usage() {
          cat << EOF
        Usage: nextjs-init <project-name> [options]
        
        OPTIONS:
          --typescript     Enable TypeScript (default: ${if cfg.features.typescript then "true" else "false"})
          --tailwind       Enable Tailwind CSS (default: ${if cfg.features.tailwindcss then "true" else "false"})
          --app-router     Use App Router (default: ${if cfg.features.appRouter then "true" else "false"})
          --turbo          Enable Turbopack (default: ${if cfg.turbopack.enable then "true" else "false"})
          --pwa            Enable PWA support (default: ${if cfg.features.pwa then "true" else "false"})
          --dir DIR        Create in specific directory
          
        EXAMPLES:
          nextjs-init my-app
          nextjs-init my-app --typescript --tailwind
          nextjs-init my-app --app-router --turbo --dir ./projects
        EOF
        }
        
        PROJECT_NAME="$1"
        shift
        
        if [[ -z "$PROJECT_NAME" ]]; then
          echo "❌ Project name required"
          show_usage
          exit 1
        fi
        
        # Parse options
        USE_TYPESCRIPT=${cfg.features.typescript}
        USE_TAILWIND=${cfg.features.tailwindcss}
        USE_APP_ROUTER=${cfg.features.appRouter}
        USE_TURBO=${cfg.turbopack.enable}
        USE_PWA=${cfg.features.pwa}
        TARGET_DIR="."
        
        while [[ $# -gt 0 ]]; do
          case $1 in
            --typescript)
              USE_TYPESCRIPT=true
              shift
              ;;
            --tailwind)
              USE_TAILWIND=true
              shift
              ;;
            --app-router)
              USE_APP_ROUTER=true
              shift
              ;;
            --turbo)
              USE_TURBO=true
              shift
              ;;
            --pwa)
              USE_PWA=true
              shift
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
        
        echo "🚀 Creating Next.js project: $PROJECT_NAME"
        echo "Directory: $TARGET_DIR"
        echo "TypeScript: $USE_TYPESCRIPT"
        echo "Tailwind CSS: $USE_TAILWIND"
        echo "App Router: $USE_APP_ROUTER"
        echo "Turbopack: $USE_TURBO"
        echo "PWA: $USE_PWA"
        echo ""
        
        # Create project directory
        mkdir -p "$TARGET_DIR"
        cd "$TARGET_DIR"
        
        # Initialize Next.js project
        create_next_args=()
        create_next_args+=("$PROJECT_NAME")
        
        if [[ "$USE_TYPESCRIPT" == "true" ]]; then
          create_next_args+=("--typescript")
        else
          create_next_args+=("--javascript")
        fi
        
        if [[ "$USE_TAILWIND" == "true" ]]; then
          create_next_args+=("--tailwind")
        fi
        
        if [[ "$USE_APP_ROUTER" == "true" ]]; then
          create_next_args+=("--app")
        else
          create_next_args+=("--src-dir")
        fi
        
        create_next_args+=("--eslint")
        create_next_args+=("--import-alias" "@/*")
        
        echo "📦 Running: npx create-next-app@latest ''${create_next_args[*]}"
        npx create-next-app@latest "''${create_next_args[@]}"
        
        cd "$PROJECT_NAME"
        
        # Copy configuration templates
        echo "⚙️  Setting up configuration files..."
        
        # Next.js config
        if [[ -f ~/.nextjs-templates/next.config.template.js ]]; then
          cp ~/.nextjs-templates/next.config.template.js next.config.js
        fi
        
        # TypeScript config
        if [[ "$USE_TYPESCRIPT" == "true" && -f ~/.nextjs-templates/tsconfig.template.json ]]; then
          cp ~/.nextjs-templates/tsconfig.template.json tsconfig.json
        fi
        
        # Tailwind config
        if [[ "$USE_TAILWIND" == "true" && -f ~/.nextjs-templates/tailwind.config.template.js ]]; then
          cp ~/.nextjs-templates/tailwind.config.template.js tailwind.config.js
        fi
        
        # ESLint config
        if [[ -f ~/.nextjs-templates/.eslintrc.template.json ]]; then
          cp ~/.nextjs-templates/.eslintrc.template.json .eslintrc.json
        fi
        
        # Install additional dependencies
        echo "📦 Installing additional dependencies..."
        
        additional_deps=()
        additional_dev_deps=()
        
        if [[ "$USE_PWA" == "true" ]]; then
          additional_deps+=("next-pwa")
        fi
        
        additional_dev_deps+=("@next/bundle-analyzer" "cross-env" "vitest" "@vitejs/plugin-react")
        
        if [[ "$USE_TYPESCRIPT" == "true" ]]; then
          additional_dev_deps+=("@typescript-eslint/eslint-plugin" "@typescript-eslint/parser")
        fi
        
        if [[ ''${#additional_deps[@]} -gt 0 ]]; then
          npm install "''${additional_deps[@]}"
        fi
        
        if [[ ''${#additional_dev_deps[@]} -gt 0 ]]; then
          npm install --save-dev "''${additional_dev_deps[@]}"
        fi
        
        # Update package.json scripts
        if command -v jq &> /dev/null; then
          echo "📝 Updating package.json scripts..."
          
          jq_script='
            .scripts.dev = (if $turbo then "next dev --turbo" else "next dev" end) |
            .scripts.build = (if $turbo then "next build --turbo" else "next build" end) |
            .scripts["lint:fix"] = "next lint --fix" |
            .scripts.test = "vitest" |
            .scripts["test:watch"] = "vitest --watch" |
            .scripts["test:coverage"] = "vitest --coverage" |
            .scripts.analyze = "cross-env ANALYZE=true next build"
          '
          
          if [[ "$USE_TYPESCRIPT" == "true" ]]; then
            jq_script="$jq_script"' | .scripts["type-check"] = "tsc --noEmit"'
          fi
          
          jq --arg turbo "$USE_TURBO" "$jq_script" package.json > package.json.tmp && mv package.json.tmp package.json
        fi
        
        # Create basic Vitest config
        cat > vitest.config.ts << EOF
        import { defineConfig } from 'vitest/config'
        import react from '@vitejs/plugin-react'
        import path from 'path'
        
        export default defineConfig({
          plugins: [react()],
          test: {
            environment: 'jsdom',
            setupFiles: ['./src/test/setup.ts'],
          },
          resolve: {
            alias: {
              '@': path.resolve(__dirname, './src'),
            },
          },
        })
        EOF
        
        # Create test setup file
        mkdir -p src/test
        cat > src/test/setup.ts << EOF
        import '@testing-library/jest-dom'
        EOF
        
        # Create basic README
        cat > README.md << EOF
        # $PROJECT_NAME
        
        A Next.js ${cfg.version} application built with modern tooling.
        
        ## Features
        
        - ✅ Next.js ${cfg.version} with App Router
        - ✅ React 18 with Server Components
        ${if cfg.features.typescript then "- ✅ TypeScript" else ""}
        ${if cfg.features.tailwindcss then "- ✅ Tailwind CSS" else ""}
        ${if cfg.turbopack.enable then "- ✅ Turbopack (development)" else ""}
        ${if cfg.features.eslint then "- ✅ ESLint with Next.js config" else ""}
        - ✅ Vitest for testing
        - ✅ Bundle analyzer
        ${if cfg.features.pwa then "- ✅ PWA support" else ""}
        
        ## Development
        
        \`\`\`bash
        # Start development server
        npm run dev
        
        # Build for production
        npm run build
        
        # Start production server
        npm start
        
        # Run tests
        npm test
        
        # Lint code
        npm run lint
        
        # Type check (TypeScript)
        ${if cfg.features.typescript then "npm run type-check" else "# TypeScript not enabled"}
        
        # Analyze bundle
        npm run analyze
        \`\`\`
        
        ## Project Structure
        
        \`\`\`
        ${if cfg.features.appRouter then ''
        src/
        ├── app/                 # App Router pages
        │   ├── globals.css     # Global styles
        │   ├── layout.tsx      # Root layout
        │   └── page.tsx        # Home page
        ├── components/         # Reusable components
        ├── lib/               # Utility functions
        └── test/              # Test setup
        '' else ''
        src/
        ├── pages/             # Pages Router
        ├── components/        # Reusable components
        ├── lib/              # Utility functions
        ├── styles/           # Stylesheets
        └── test/             # Test setup
        ''}
        \`\`\`
        
        ## Configuration
        
        - **Next.js**: \`next.config.js\`
        ${if cfg.features.typescript then "- **TypeScript**: \`tsconfig.json\`" else ""}
        ${if cfg.features.tailwindcss then "- **Tailwind**: \`tailwind.config.js\`" else ""}
        ${if cfg.features.eslint then "- **ESLint**: \`.eslintrc.json\`" else ""}
        - **Vitest**: \`vitest.config.ts\`
        EOF
        
        echo ""
        echo "✅ Next.js project created successfully!"
        echo ""
        echo "📁 Project: $TARGET_DIR/$PROJECT_NAME"
        echo "🔧 Features: TypeScript($USE_TYPESCRIPT), Tailwind($USE_TAILWIND), Turbo($USE_TURBO), PWA($USE_PWA)"
        echo ""
        echo "🚀 Next steps:"
        echo "  cd $TARGET_DIR/$PROJECT_NAME"
        echo "  npm run dev"
        echo ""
        echo "🔗 Useful commands:"
        echo "  npm run lint          # Check code quality"
        echo "  npm run test          # Run tests"
        echo "  npm run analyze       # Analyze bundle size"
        ${if cfg.features.typescript then ''echo "  npm run type-check    # TypeScript check"'' else ""}
      '';
    };
    
    # Next.js health check
    home.file."bin/nextjs-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "⚛️  Next.js Development Environment Health Check"
        echo "=============================================="
        
        # Check Node.js and package managers
        echo "🔧 Runtime Environment:"
        
        if command -v node &> /dev/null; then
          node_version=$(node --version)
          echo "✅ Node.js: $node_version"
          
          # Check if Node.js version is compatible
          major_version=$(echo "$node_version" | sed 's/v\([0-9]*\).*/\1/')
          if [[ $major_version -ge 18 ]]; then
            echo "   ✅ Version compatible with Next.js ${cfg.version}"
          else
            echo "   ⚠️  Version may not be fully compatible"
          fi
        else
          echo "❌ Node.js: not found"
        fi
        
        package_managers=("npm" "pnpm" "bun")
        for pm in "''${package_managers[@]}"; do
          if command -v "$pm" &> /dev/null; then
            echo "✅ $pm: $(''${pm} --version)"
          else
            echo "❌ $pm: not found"
          fi
        done
        
        echo ""
        echo "📦 Next.js Environment:"
        
        # Check Next.js CLI
        if npx next --version &> /dev/null; then
          echo "✅ Next.js CLI: $(npx next --version)"
        else
          echo "❌ Next.js CLI: not available"
        fi
        
        # Check TypeScript
        ${lib.optionalString cfg.features.typescript ''
        if command -v tsc &> /dev/null; then
          echo "✅ TypeScript: $(tsc --version)"
        else
          echo "❌ TypeScript: not found"
        fi
        ''}
        
        # Check Turbopack
        ${lib.optionalString cfg.turbopack.enable ''
        echo "⚡ Turbopack: enabled in configuration"
        ''}
        
        echo ""
        echo "🧰 Development Tools:"
        
        tools=(
          "eslint:ESLint"
          "prettier:Prettier"
        )
        
        for tool_desc in "''${tools[@]}"; do
          tool="''${tool_desc%%:*}"
          desc="''${tool_desc##*:}"
          
          if npx "$tool" --version &> /dev/null 2>&1; then
            echo "✅ $desc: available"
          else
            echo "❌ $desc: not available"
          fi
        done
        
        # Current project check
        echo ""
        echo "📁 Current Project:"
        
        if [[ -f "package.json" ]]; then
          if jq -e '.dependencies.next' package.json > /dev/null 2>&1; then
            next_version=$(jq -r '.dependencies.next' package.json)
            project_name=$(jq -r '.name' package.json)
            echo "✅ Next.js project: $project_name"
            echo "   Version: $next_version"
            
            # Check project features
            if [[ -f "next.config.js" ]] || [[ -f "next.config.mjs" ]]; then
              echo "✅ Next.js config: present"
            else
              echo "❌ Next.js config: missing"
            fi
            
            if [[ -f "tsconfig.json" ]]; then
              echo "✅ TypeScript: configured"
            else
              echo "⚪ TypeScript: not configured"
            fi
            
            if [[ -f "tailwind.config.js" ]] || [[ -f "tailwind.config.ts" ]]; then
              echo "✅ Tailwind CSS: configured"
            else
              echo "⚪ Tailwind CSS: not configured"
            fi
            
            # Check if using App Router
            if [[ -d "src/app" ]] || [[ -d "app" ]]; then
              echo "✅ App Router: detected"
            elif [[ -d "src/pages" ]] || [[ -d "pages" ]]; then
              echo "✅ Pages Router: detected"
            fi
            
          else
            echo "⚪ Not a Next.js project"
          fi
        else
          echo "⚪ No package.json found"
        fi
        
        echo ""
        echo "📊 Configuration:"
        echo "Next.js version: ${cfg.version}"
        echo "Router: ${cfg.router}"
        echo "TypeScript: ${if cfg.features.typescript then "enabled" else "disabled"}"
        echo "Tailwind CSS: ${if cfg.features.tailwindcss then "enabled" else "disabled"}"
        echo "Turbopack: ${if cfg.turbopack.enable then "enabled" else "disabled"}"
        echo "PWA: ${if cfg.features.pwa then "enabled" else "disabled"}"
        
        echo ""
        echo "✅ Next.js health check completed!"
      '';
    };
  };
}