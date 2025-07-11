# Web開発環境 - 開発ツール統合
# ESLint、Prettier、その他の開発支援ツール

{ lib, pkgs, config, ... }:

let
  cfg = config.web.tooling;
in
{
  options.web.tooling = {
    enable = lib.mkEnableOption "Web development tooling";
    
    linting = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable linting tools";
      };
      
      eslint = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable ESLint";
      };
      
      prettier = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Prettier";
      };
    };
    
    formatting = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable code formatting";
      };
      
      onSave = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Format on save";
      };
    };
    
    bundling = {
      analyzer = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable bundle analyzer";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Development tooling packages
    home-manager.users.yuki.home.packages = with pkgs; [
      # Linting and formatting
      nodePackages.eslint
      nodePackages.prettier
      nodePackages.stylelint
      
      # Bundle analysis
      nodePackages.webpack-bundle-analyzer
      
      # Other tools
      nodePackages.npm-check-updates
      nodePackages.depcheck
    ];
    
    # Default ESLint configuration
    home-manager.users.yuki.home.file.".web-templates/.eslintrc.template.json" = lib.mkIf cfg.linting.eslint {
      text = builtins.toJSON {
        env = {
          browser = true;
          es2021 = true;
          node = true;
        };
        extends = [
          "eslint:recommended"
          "@typescript-eslint/recommended"
          "prettier"
        ];
        parser = "@typescript-eslint/parser";
        parserOptions = {
          ecmaVersion = "latest";
          sourceType = "module";
          ecmaFeatures = {
            jsx = true;
          };
        };
        plugins = [
          "@typescript-eslint"
          "react"
          "react-hooks"
        ];
        rules = {
          "prefer-const" = "error";
          "no-unused-vars" = "warn";
          "no-console" = "warn";
          "@typescript-eslint/no-unused-vars" = "warn";
          "@typescript-eslint/no-explicit-any" = "warn";
          "react/react-in-jsx-scope" = "off";
          "react-hooks/rules-of-hooks" = "error";
          "react-hooks/exhaustive-deps" = "warn";
        };
        settings = {
          react = {
            version = "detect";
          };
        };
      };
    };
    
    # Default Prettier configuration
    home-manager.users.yuki.home.file.".web-templates/.prettierrc.template.json" = lib.mkIf cfg.linting.prettier {
      text = builtins.toJSON {
        semi = true;
        trailingComma = "es5";
        singleQuote = true;
        printWidth = 80;
        tabWidth = 2;
        useTabs = false;
        bracketSpacing = true;
        bracketSameLine = false;
        arrowParens = "always";
        endOfLine = "lf";
        quoteProps = "as-needed";
        jsxSingleQuote = true;
        proseWrap = "preserve";
      };
    };
    
    # Prettier ignore file
    home-manager.users.yuki.home.file.".web-templates/.prettierignore.template" = lib.mkIf cfg.linting.prettier {
      text = ''
        # Dependencies
        node_modules/
        
        # Production builds
        build/
        dist/
        .next/
        .nuxt/
        .output/
        
        # Generated files
        *.min.js
        *.min.css
        
        # Package files
        package-lock.json
        yarn.lock
        pnpm-lock.yaml
        bun.lockb
        
        # Config files
        *.config.js
        *.config.ts
        
        # Documentation
        CHANGELOG.md
        
        # Cache
        .cache/
        .turbo/
        
        # Environment
        .env*
      '';
    };
    
    # Shell aliases for tooling
    home-manager.users.yuki.home.shellAliases = {
      # Linting shortcuts
      "lint-fix" = "npm run lint:fix";
      "format" = "prettier --write .";
      "format-check" = "prettier --check .";
      
      # Dependency management
      "deps-check" = "npm-check-updates";
      "deps-update" = "npm-check-updates -u";
      "deps-unused" = "depcheck";
      
      # Bundle analysis
      "analyze" = "npm run analyze";
      "bundle-size" = "du -sh dist/ build/ .next/";
    };
    
    # Tooling health check
    home-manager.users.yuki.home.file."bin/web-tooling-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🛠️  Web Development Tooling Health Check"
        echo "======================================"
        
        # Check linting tools
        echo "🔍 Linting Tools:"
        
        if command -v eslint &> /dev/null; then
          echo "✅ ESLint: $(eslint --version)"
        else
          echo "❌ ESLint: not found"
        fi
        
        if command -v prettier &> /dev/null; then
          echo "✅ Prettier: $(prettier --version)"
        else
          echo "❌ Prettier: not found"
        fi
        
        if command -v stylelint &> /dev/null; then
          echo "✅ Stylelint: available"
        else
          echo "❌ Stylelint: not found"
        fi
        
        # Check formatting configuration
        echo ""
        echo "📝 Formatting Configuration:"
        
        if [[ -f ".prettierrc" ]] || [[ -f ".prettierrc.json" ]] || [[ -f "prettier.config.js" ]]; then
          echo "✅ Prettier config: present"
        else
          echo "⚪ Prettier config: not found"
        fi
        
        if [[ -f ".eslintrc.json" ]] || [[ -f ".eslintrc.js" ]] || [[ -f "eslint.config.js" ]]; then
          echo "✅ ESLint config: present"
        else
          echo "⚪ ESLint config: not found"
        fi
        
        # Check current project
        echo ""
        echo "📁 Current Project:"
        
        if [[ -f "package.json" ]]; then
          if jq -e '.scripts.lint' package.json > /dev/null 2>&1; then
            echo "✅ Lint script: configured"
          else
            echo "⚪ Lint script: not configured"
          fi
          
          if jq -e '.scripts["lint:fix"]' package.json > /dev/null 2>&1; then
            echo "✅ Lint fix script: configured"
          else
            echo "⚪ Lint fix script: not configured"
          fi
          
          if jq -e '.devDependencies.prettier' package.json > /dev/null 2>&1; then
            echo "✅ Prettier dependency: installed"
          else
            echo "⚪ Prettier dependency: not installed"
          fi
          
          if jq -e '.devDependencies.eslint' package.json > /dev/null 2>&1; then
            echo "✅ ESLint dependency: installed"
          else
            echo "⚪ ESLint dependency: not installed"
          fi
        else
          echo "⚪ No package.json found"
        fi
        
        echo ""
        echo "📊 Configuration:"
        echo "Linting: ${if cfg.linting.enable then "enabled" else "disabled"}"
        echo "ESLint: ${if cfg.linting.eslint then "enabled" else "disabled"}"
        echo "Prettier: ${if cfg.linting.prettier then "enabled" else "disabled"}"
        echo "Format on save: ${if cfg.formatting.onSave then "enabled" else "disabled"}"
        echo "Bundle analyzer: ${if cfg.bundling.analyzer then "enabled" else "disabled"}"
        
        echo ""
        echo "✅ Tooling health check completed!"
      '';
    };
  };
}