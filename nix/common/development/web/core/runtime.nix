# Web開発環境 - 次世代ランタイム統合
# Node.js 22, Bun 1.1+, Deno 2.0, Cloudflare Workers(workerd)の統合環境

{ lib, pkgs, config, ... }:

let
  cfg = config.web.runtime;
in
{
  options.web.runtime = {
    enable = lib.mkEnableOption "Web development runtime environment";
    
    node = lib.mkOption {
      type = lib.types.str;
      default = "22";
      description = "Node.js version";
    };
    
    bun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Bun runtime";
    };
    
    deno = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Deno runtime";
    };
    
    workerd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Cloudflare Workers runtime";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      # Node.js ecosystem
      nodejs_22
      corepack  # Built-in package manager manager
      
      # Bun - 高速JavaScript runtime & package manager
      bun
      
      # Deno - secure TypeScript runtime
      deno
      
      # Package managers
      nodePackages.npm
      nodePackages.pnpm
      nodePackages.yarn
      
      # Development utilities
      nodePackages.nodemon
      nodePackages.ts-node
      nodePackages.typescript
      
      # Web development CLI tools
      nodePackages.serve
      nodePackages.http-server
    ] ++ lib.optionals cfg.workerd [
      # Cloudflare Workers runtime (if available)
      # workerd package might need custom packaging
    ];
    
    # Environment variables
    home.sessionVariables = {
      # Node.js optimizations
      NODE_OPTIONS = "--max-old-space-size=4096";
      
      # Bun configuration
      BUN_RUNTIME_TRANSPILER_CACHE_PATH = "${config.xdg.cacheHome}/bun";
      
      # Deno configuration
      DENO_DIR = "${config.xdg.cacheHome}/deno";
    };
    
    # Shell aliases for quick development
    home.shellAliases = {
      # Runtime selection
      "dev-node" = "node";
      "dev-bun" = "bun";
      "dev-deno" = "deno";
      
      # Package management
      "ni" = "npm install";
      "nr" = "npm run";
      "pi" = "pnpm install";
      "pr" = "pnpm run";
      "bi" = "bun install";
      "br" = "bun run";
      
      # Development servers
      "serve" = "npx serve";
      "dev-server" = "python -m http.server 8000";
    };
    
    # Git ignore patterns for web development
    home.file.".gitignore_web" = {
      text = ''
        # Dependencies
        node_modules/
        .pnp
        .pnp.js
        .yarn/install-state.gz
        
        # Production builds
        build/
        dist/
        .next/
        .nuxt/
        .output/
        .vercel/
        .netlify/
        
        # Runtime caches
        .cache/
        .parcel-cache/
        .turbo/
        
        # Environment files
        .env
        .env.local
        .env.development.local
        .env.test.local
        .env.production.local
        
        # IDE files
        .vscode/
        .idea/
        *.swp
        *.swo
        *~
        
        # OS files
        .DS_Store
        Thumbs.db
        
        # Logs
        *.log
        logs/
        
        # Runtime files
        *.pid
        *.seed
        *.pid.lock
        
        # Coverage
        coverage/
        .nyc_output/
        
        # Dependency directories
        jspm_packages/
        
        # Optional npm cache directory
        .npm
        
        # Optional eslint cache
        .eslintcache
        
        # Optional stylelint cache
        .stylelintcache
        
        # Microbundle cache
        .rpt2_cache/
        .rts2_cache_cjs/
        .rts2_cache_es/
        .rts2_cache_umd/
        
        # Optional REPL history
        .node_repl_history
        
        # Output of 'npm pack'
        *.tgz
        
        # Yarn Integrity file
        .yarn-integrity
        
        # dotenv environment variables file
        .env.test
        
        # Stores VSCode versions used for testing VSCode extensions
        .vscode-test
        
        # yarn v2
        .yarn/cache
        .yarn/unplugged
        .yarn/build-state.yml
        .yarn/install-state.gz
        .pnp.*
      '';
    };
  };
}