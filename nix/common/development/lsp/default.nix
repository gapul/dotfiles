{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.lsp;
  
  # LSP server configurations
  lspServers = {
    # Web Development
    typescript = {
      package = pkgs.nodePackages.typescript-language-server;
      command = "typescript-language-server";
      filetypes = [ "typescript" "javascript" "typescriptreact" "javascriptreact" ];
    };
    
    html = {
      package = pkgs.nodePackages.vscode-html-languageserver-bin;
      command = "html-languageserver";
      filetypes = [ "html" ];
    };
    
    css = {
      package = pkgs.nodePackages.vscode-css-languageserver-bin;
      command = "css-languageserver";
      filetypes = [ "css" "scss" "sass" "less" ];
    };
    
    json = {
      package = pkgs.nodePackages.vscode-json-languageserver;
      command = "json-languageserver";
      filetypes = [ "json" "jsonc" ];
    };
    
    # Systems Programming
    rust = {
      package = pkgs.rust-analyzer;
      command = "rust-analyzer";
      filetypes = [ "rust" ];
    };
    
    go = {
      package = pkgs.gopls;
      command = "gopls";
      filetypes = [ "go" "gomod" "gowork" ];
    };
    
    c_cpp = {
      package = pkgs.clang-tools;
      command = "clangd";
      filetypes = [ "c" "cpp" "objc" "objcpp" ];
    };
    
    # Scripting Languages
    python = {
      package = pkgs.python3Packages.python-lsp-server;
      command = "pylsp";
      filetypes = [ "python" ];
    };
    
    lua = {
      package = pkgs.sumneko-lua-language-server;
      command = "lua-language-server";
      filetypes = [ "lua" ];
    };
    
    bash = {
      package = pkgs.nodePackages.bash-language-server;
      command = "bash-language-server";
      filetypes = [ "sh" "bash" ];
    };
    
    # Configuration Languages
    nix = {
      package = pkgs.nil;
      command = "nil";
      filetypes = [ "nix" ];
    };
    
    yaml = {
      package = pkgs.nodePackages.yaml-language-server;
      command = "yaml-language-server";
      filetypes = [ "yaml" "yml" ];
    };
    
    # Markup Languages
    markdown = {
      package = pkgs.marksman;
      command = "marksman";
      filetypes = [ "markdown" ];
    };
    
    # Database
    sql = {
      package = pkgs.sqls;
      command = "sqls";
      filetypes = [ "sql" ];
    };
  };
  
  enabledServers = filterAttrs (name: server: 
    elem name cfg.enabledLanguages
  ) lspServers;
  
in
{
  options.dotfiles.development.lsp = {
    enable = mkEnableOption "Language Server Protocol support";
    
    enabledLanguages = mkOption {
      type = types.listOf (types.enum (attrNames lspServers));
      default = [ "typescript" "html" "css" "json" "rust" "go" "python" "nix" "yaml" "markdown" "bash" ];
      description = "List of LSP servers to enable";
    };
    
    globalConfig = mkOption {
      type = types.attrs;
      default = {
        diagnostic = {
          enable = true;
          signs = true;
          virtual_text = true;
          update_in_insert = false;
        };
        completion = {
          enable = true;
          snippets = true;
          documentation = true;
        };
        formatting = {
          enable = true;
          format_on_save = false;
        };
        hover = {
          enable = true;
          documentation = true;
        };
      };
      description = "Global LSP configuration";
    };
    
    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages for LSP support";
    };
    
    nvimIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Neovim LSP integration";
    };
    
    vscodeIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable VS Code LSP integration";
    };
    
    emacsIntegration = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Emacs LSP integration";
    };
  };

  config = mkIf cfg.enable {
    # Install LSP servers
    home-manager.users.yuki.home.packages = mkIf (config ? home-manager) 
      (map (server: server.package) (attrValues enabledServers)) ++
      cfg.extraPackages ++
      (with pkgs; [
        # Formatters and linters
        nodePackages.prettier
        black
        rustfmt
        gofmt
        shfmt
        nixpkgs-fmt
        
        # Additional development tools
        tree-sitter
        ripgrep
        fd
        fzf
      ]);

    # Neovim LSP configuration
    home-manager.users.yuki.programs.neovim = mkIf (config ? home-manager && cfg.nvimIntegration) {
      enable = true;
      plugins = with pkgs.vimPlugins; [
        nvim-lspconfig
        nvim-cmp
        cmp-nvim-lsp
        cmp-buffer
        cmp-path
        cmp-cmdline
        luasnip
        cmp_luasnip
        telescope-nvim
        null-ls-nvim
      ];
      
      extraLuaConfig = ''
        -- LSP Configuration
        local lspconfig = require('lspconfig')
        local cmp = require('cmp')
        local luasnip = require('luasnip')
        
        -- Completion setup
        cmp.setup({
          snippet = {
            expand = function(args)
              luasnip.lsp_expand(args.body)
            end,
          },
          mapping = cmp.mapping.preset.insert({
            ['<C-b>'] = cmp.mapping.scroll_docs(-4),
            ['<C-f>'] = cmp.mapping.scroll_docs(4),
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<C-e>'] = cmp.mapping.abort(),
            ['<CR>'] = cmp.mapping.confirm({ select = true }),
          }),
          sources = cmp.config.sources({
            { name = 'nvim_lsp' },
            { name = 'luasnip' },
          }, {
            { name = 'buffer' },
          })
        })
        
        -- LSP servers configuration
        ${concatStringsSep "\n" (mapAttrsToList (name: server: ''
          lspconfig.${server.command}:setup({
            capabilities = require('cmp_nvim_lsp').default_capabilities(),
            on_attach = function(client, bufnr)
              -- Key mappings
              local bufopts = { noremap=true, silent=true, buffer=bufnr }
              vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
              vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
              vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
              vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
              vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, bufopts)
              vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, bufopts)
              vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, bufopts)
              vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
              vim.keymap.set('n', '<leader>f', function()
                vim.lsp.buf.format { async = true }
              end, bufopts)
            end,
          })
        '') enabledServers)}
        
        -- Diagnostic configuration
        vim.diagnostic.config({
          virtual_text = ${if cfg.globalConfig.diagnostic.virtual_text then "true" else "false"},
          signs = ${if cfg.globalConfig.diagnostic.signs then "true" else "false"},
          update_in_insert = ${if cfg.globalConfig.diagnostic.update_in_insert then "true" else "false"},
        })
      '';
    };

    # VS Code LSP configuration
    home-manager.users.yuki.home.file.".vscode/settings.json" = mkIf (config ? home-manager && cfg.vscodeIntegration) {
      text = builtins.toJSON (
        # LSP server paths
        (listToAttrs (mapAttrsToList (name: server: {
          name = "${name}.path";
          value = "${server.package}/bin/${server.command}";
        }) enabledServers)) //
        {
          # Global LSP settings
          "editor.formatOnSave" = cfg.globalConfig.formatting.format_on_save;
          "editor.hover.enabled" = cfg.globalConfig.hover.enable;
          "editor.quickSuggestions" = cfg.globalConfig.completion.enable;
        
          # Language-specific settings
          "[typescript]" = {
            "editor.defaultFormatter" = "esbenp.prettier-vscode";
          };
          "[javascript]" = {
            "editor.defaultFormatter" = "esbenp.prettier-vscode";
          };
          "[python]" = {
            "editor.defaultFormatter" = "ms-python.black-formatter";
          };
          "[rust]" = {
            "editor.defaultFormatter" = "rust-lang.rust-analyzer";
          };
          "[go]" = {
            "editor.defaultFormatter" = "golang.go";
          };
          "[nix]" = {
            "editor.defaultFormatter" = "jnoortheen.nix-ide";
          };
        }
      );
    };

    # Shell aliases for LSP management
    home-manager.users.yuki.programs.zsh.shellAliases = mkIf (config ? home-manager) {
      lsp-status = "ps aux | grep -E '(language-server|lsp|rust-analyzer|gopls|nil)'";
      lsp-restart = "pkill -f 'language-server|lsp|rust-analyzer|gopls|nil'";
    };

    # LSP health check script
    home-manager.users.yuki.home.file."bin/lsp-health" = mkIf (config ? home-manager) {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🔍 LSP Health Check"
        echo "=================="
        
        # Check enabled LSP servers
        ${concatStringsSep "\n" (mapAttrsToList (name: server: ''
          if command -v ${server.command} &> /dev/null; then
            echo "✅ ${name}: ${server.command} available"
          else
            echo "❌ ${name}: ${server.command} not found"
          fi
        '') enabledServers)}
        
        # Check running LSP processes
        echo ""
        echo "🔄 Running LSP processes:"
        ps aux | grep -E '(language-server|lsp|rust-analyzer|gopls|nil)' | grep -v grep || echo "No LSP processes running"
        
        # Check LSP logs (if available)
        if [[ -d ~/.local/share/nvim/lsp.log ]]; then
          echo ""
          echo "📝 Recent LSP errors:"
          tail -20 ~/.local/share/nvim/lsp.log | grep -i error || echo "No recent errors"
        fi
      '';
    };
  };
}