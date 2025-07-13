# Web開発環境 - パッケージマネージャー統合
# npm, pnpm, yarn, bunの統合管理

{ lib, pkgs, config, ... }:

let
  cfg = config.web.packageManagers;
in
{
  options.web.packageManagers = {
    enable = lib.mkEnableOption "Web package managers integration";
    
    primary = lib.mkOption {
      type = lib.types.enum [ "npm" "pnpm" "yarn" "bun" ];
      default = "bun";
      description = "Primary package manager";
    };
    
    fallback = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "npm" "pnpm" "yarn" "bun" ]);
      default = [ "pnpm" "npm" ];
      description = "Fallback package managers";
    };
    
    autoDetect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-detect package manager from lock files";
    };
    
    globalPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "typescript"
        "ts-node"
        "nodemon"
        "serve"
        "http-server"
        "prettier"
        "eslint"
      ];
      description = "Global packages to install";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.yuki.home.packages = with pkgs; [
      # Core package managers
      nodejs_22.pkgs.npm
      nodejs_22.pkgs.pnpm
      nodejs_22.pkgs.yarn
      bun
      
      # Package management utilities
      ncu # npm-check-updates
      npm-check-updates
    ];
    
    # Environment variables for package managers
    home-manager.users.yuki.home.sessionVariables = {
      # npm configuration
      NPM_CONFIG_FUND = "false";
      NPM_CONFIG_AUDIT = "false";
      NPM_CONFIG_UPDATE_NOTIFIER = "false";
      
      # pnpm configuration
      PNPM_HOME = "${config.xdg.dataHome}/pnpm";
      
      # yarn configuration
      YARN_CACHE_FOLDER = "${config.xdg.cacheHome}/yarn";
      
      # bun configuration
      BUN_INSTALL = "${config.xdg.dataHome}/bun";
    };
    
    # Ensure pnpm and bun paths are added
    home-manager.users.yuki.home.sessionPath = [
      "${config.xdg.dataHome}/pnpm"
      "${config.xdg.dataHome}/bun/bin"
    ];
    
    # Shell aliases for package management
    home-manager.users.yuki.home.shellAliases = {
      # Smart package manager aliases
      "install" = lib.mkIf cfg.autoDetect ''
        if [[ -f "bun.lockb" ]]; then
          bun install
        elif [[ -f "pnpm-lock.yaml" ]]; then
          pnpm install
        elif [[ -f "yarn.lock" ]]; then
          yarn install
        else
          ${cfg.primary} install
        fi
      '';
      
      "add" = lib.mkIf cfg.autoDetect ''
        if [[ -f "bun.lockb" ]]; then
          bun add
        elif [[ -f "pnpm-lock.yaml" ]]; then
          pnpm add
        elif [[ -f "yarn.lock" ]]; then
          yarn add
        else
          ${cfg.primary} install
        fi
      '';
      
      "run" = lib.mkIf cfg.autoDetect ''
        if [[ -f "bun.lockb" ]]; then
          bun run
        elif [[ -f "pnpm-lock.yaml" ]]; then
          pnpm run
        elif [[ -f "yarn.lock" ]]; then
          yarn run
        else
          ${cfg.primary} run
        fi
      '';
      
      # Direct package manager aliases
      "ni" = "npm install";
      "nr" = "npm run";
      "ns" = "npm start";
      "nt" = "npm test";
      "nb" = "npm run build";
      
      "pi" = "pnpm install";
      "pr" = "pnpm run";
      "ps" = "pnpm start";
      "pt" = "pnpm test";
      "pb" = "pnpm run build";
      
      "yi" = "yarn install";
      "yr" = "yarn run";
      "ys" = "yarn start";
      "yt" = "yarn test";
      "yb" = "yarn build";
      
      "bi" = "bun install";
      "br" = "bun run";
      "bs" = "bun start";
      "bt" = "bun test";
      "bb" = "bun run build";
      
      # Package management utilities
      "outdated" = "ncu";
      "update-deps" = "ncu -u";
      "audit-fix" = "npm audit fix";
    };
    
    # Package manager configuration files
    home-manager.users.yuki.home.file.".npmrc" = {
      text = ''
        fund=false
        audit=false
        update-notifier=false
        save-exact=true
        package-lock=true
        progress=true
        
        # Performance optimizations
        cache=${config.xdg.cacheHome}/npm
        tmp=${config.xdg.cacheHome}/npm-tmp
        
        # Security
        audit-level=moderate
      '';
    };
    
    home-manager.users.yuki.home.file.".pnpmrc" = {
      text = ''
        store-dir=${config.xdg.dataHome}/pnpm/store
        cache-dir=${config.xdg.cacheHome}/pnpm
        state-dir=${config.xdg.dataHome}/pnpm/state
        
        # Performance
        package-import-method=clone-or-copy
        symlink=true
        
        # Behavior
        auto-install-peers=true
        strict-peer-dependencies=false
        save-exact=true
        
        # Logging
        progress=true
        reporter=default
      '';
    };
    
    home-manager.users.yuki.home.file.".yarnrc.yml" = {
      text = ''
        compressionLevel: mixed
        enableGlobalCache: true
        enableInlineBuilds: true
        enableMessageNames: false
        
        globalFolder: ${config.xdg.dataHome}/yarn/global
        cacheFolder: ${config.xdg.cacheHome}/yarn
        
        logFilters:
          - code: YN0002
            level: discard
          - code: YN0060
            level: discard
            
        nodeLinker: node-modules
        
        packageExtensions:
          "@babel/core@*":
            peerDependencies:
              "@babel/types": "*"
      '';
    };
    
    # Bun configuration
    home-manager.users.yuki.home.file.".bunfig.toml" = {
      text = ''
        [install]
        cache = "${config.xdg.cacheHome}/bun/install"
        globalDir = "${config.xdg.dataHome}/bun/install/global"
        globalBinDir = "${config.xdg.dataHome}/bun/bin"
        
        # Package manager behavior
        production = false
        save = true
        saveExact = true
        
        # Performance
        concurrent = true
        
        [run]
        shell = "zsh"
        
        [test]
        coverage = true
        
        [build]
        outdir = "dist"
        target = "browser"
        
        [macros]
        react = true
      '';
    };
    
    # Package manager detection script
    home-manager.users.yuki.home.file."bin/detect-pm" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        # Detect package manager from lock files
        if [[ -f "bun.lockb" ]]; then
          echo "bun"
        elif [[ -f "pnpm-lock.yaml" ]]; then
          echo "pnpm"
        elif [[ -f "yarn.lock" ]]; then
          echo "yarn"
        elif [[ -f "package-lock.json" ]]; then
          echo "npm"
        else
          echo "${cfg.primary}"
        fi
      '';
    };
    
    # Package manager wrapper script
    home-manager.users.yuki.home.file."bin/pm" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        PM=$(detect-pm)
        CMD="$1"
        shift
        
        case "$CMD" in
          install|i)
            $PM install "$@"
            ;;
          add|a)
            $PM add "$@"
            ;;
          remove|rm)
            if [[ "$PM" == "npm" ]]; then
              npm uninstall "$@"
            elif [[ "$PM" == "yarn" ]]; then
              yarn remove "$@"
            else
              $PM remove "$@"
            fi
            ;;
          run|r)
            $PM run "$@"
            ;;
          build|b)
            $PM run build "$@"
            ;;
          start|s)
            $PM run start "$@"
            ;;
          test|t)
            $PM run test "$@"
            ;;
          dev|d)
            $PM run dev "$@"
            ;;
          update|up)
            if [[ "$PM" == "bun" ]]; then
              bun update "$@"
            elif [[ "$PM" == "pnpm" ]]; then
              pnpm update "$@"
            elif [[ "$PM" == "yarn" ]]; then
              yarn upgrade "$@"
            else
              npm update "$@"
            fi
            ;;
          outdated)
            if [[ "$PM" == "bun" ]]; then
              bun outdated
            else
              $PM outdated
            fi
            ;;
          *)
            echo "Usage: pm <command> [args...]"
            echo "Commands: install(i), add(a), remove(rm), run(r), build(b), start(s), test(t), dev(d), update(up), outdated"
            echo "Detected package manager: $PM"
            exit 1
            ;;
        esac
      '';
    };
  };
}