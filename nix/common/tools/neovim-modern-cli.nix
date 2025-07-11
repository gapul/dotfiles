{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modern-cli;
in
{
  config = mkIf cfg.enable {
    # Neovim configuration for modern CLI integration
    home-manager.users.yuki.programs.neovim = {
      enable = true;
      extraLuaConfig = ''
        -- Modern CLI Tools Integration (Phase 5)
        -- Conditional setup based on available tools
        
        local function command_exists(cmd)
          return vim.fn.executable(cmd) == 1
        end
        
        -- LazyGit integration
        if command_exists('lazygit') then
          vim.keymap.set('n', '<leader>gg', function()
            vim.cmd('terminal lazygit')
          end, { desc = 'Open LazyGit', silent = true })
          
          -- Better LazyGit with toggleterm if available
          local ok, _ = pcall(require, 'toggleterm')
          if ok then
            local Terminal = require('toggleterm.terminal').Terminal
            local lazygit = Terminal:new({
              cmd = 'lazygit',
              dir = 'git_dir',
              direction = 'float',
              float_opts = {
                border = 'curved',
                width = function() return math.floor(vim.o.columns * 0.9) end,
                height = function() return math.floor(vim.o.lines * 0.9) end,
              },
              on_open = function(term)
                vim.cmd('startinsert!')
                vim.api.nvim_buf_set_keymap(term.bufnr, 'n', 'q', '<cmd>close<CR>', { noremap = true, silent = true })
              end,
              on_close = function() vim.cmd('checktime') end,
            })
            
            vim.keymap.set('n', '<leader>gg', function() lazygit:toggle() end, { desc = 'Open LazyGit Float', silent = true })
          end
        end
        
        -- Yazi file manager integration
        if command_exists('yazi') then
          vim.keymap.set('n', '<leader>fm', function()
            vim.cmd('terminal yazi')
          end, { desc = 'Open Yazi file manager', silent = true })
        end
        
        -- Bottom system monitor integration
        if command_exists('btm') then
          vim.keymap.set('n', '<leader>tm', function()
            vim.cmd('terminal btm')
          end, { desc = 'Open system monitor', silent = true })
        end
        
        -- Enhanced search with ripgrep and fd (Telescope integration)
        if command_exists('rg') and command_exists('fd') then
          local telescope_ok, telescope = pcall(require, 'telescope')
          if telescope_ok then
            telescope.setup({
              defaults = {
                vimgrep_arguments = {
                  'rg', '--color=never', '--no-heading', '--with-filename',
                  '--line-number', '--column', '--smart-case', '--hidden', '--glob=!.git/*',
                },
                file_ignore_patterns = { "node_modules/.*", "%.git/.*", "dist/.*", "build/.*", "target/.*" },
              },
              pickers = {
                find_files = {
                  find_command = { 'fd', '--type', 'f', '--hidden', '--exclude', '.git' },
                },
              },
            })
            
            vim.keymap.set('n', '<leader>ff', require('telescope.builtin').find_files, { desc = 'Find files (fd)' })
            vim.keymap.set('n', '<leader>fg', require('telescope.builtin').live_grep, { desc = 'Live grep (rg)' })
          end
        end
        
        -- Eza integration for file listing
        if command_exists('eza') then
          vim.keymap.set('n', '<leader>ft', function()
            vim.cmd('terminal eza --tree --level=3 --icons --git --group-directories-first')
          end, { desc = 'File tree (eza)', silent = true })
        end
        
        -- Bat integration for file preview
        if command_exists('bat') then
          vim.keymap.set('n', '<leader>bp', function()
            local file = vim.fn.expand('<cfile>')
            if file and file ~= '' then
              local cmd = string.format('terminal bat --style=numbers,changes --color=always %s', vim.fn.shellescape(file))
              vim.cmd(cmd)
            else
              vim.notify('No file under cursor', vim.log.levels.WARN)
            end
          end, { desc = 'Preview with bat', silent = true })
        end
        
        -- Zoxide integration for smart directory jumping
        if command_exists('zoxide') then
          vim.keymap.set('n', '<leader>z', function()
            local input = vim.fn.input('Zoxide query: ')
            if input ~= '' then
              local result = vim.fn.systemlist('zoxide query ' .. vim.fn.shellescape(input))
              if #result > 0 and vim.v.shell_error == 0 then
                vim.cmd('cd ' .. result[1])
                vim.notify('Changed to: ' .. result[1])
              else
                vim.notify('No directory found for: ' .. input, vim.log.levels.WARN)
              end
            end
          end, { desc = 'Zoxide jump', silent = true })
        end
        
        -- Create Which-Key groups if available
        local wk_ok, wk = pcall(require, 'which-key')
        if wk_ok then
          wk.register({
            ['<leader>g'] = { name = 'Git' },
            ['<leader>f'] = { name = 'Find/Files' },
            ['<leader>t'] = { name = 'Terminal/Tools' },
            ['<leader>b'] = { name = 'Buffer/Bat' },
            ['<leader>z'] = { name = 'Zoxide' },
          })
        end
        
        vim.notify('Modern CLI tools integration loaded', vim.log.levels.INFO)
      '';
    };

    # Add toggleterm plugin for better terminal integration
    home-manager.users.yuki.programs.neovim.plugins = with pkgs.vimPlugins; [
      # Terminal management
      {
        plugin = toggleterm-nvim;
        type = "lua";
        config = ''
          require('toggleterm').setup({
            size = 20,
            open_mapping = [[<c-\>]],
            hide_numbers = true,
            shade_terminals = true,
            shading_factor = 2,
            start_in_insert = true,
            insert_mappings = true,
            terminal_mappings = true,
            persist_size = true,
            direction = 'float',
            close_on_exit = true,
            shell = vim.o.shell,
            float_opts = {
              border = 'curved',
              width = function() return math.floor(vim.o.columns * 0.8) end,
              height = function() return math.floor(vim.o.lines * 0.8) end,
              winblend = 0,
            }
          })
        '';
      }
      
      # Enhanced which-key for modern CLI keybindings
      {
        plugin = which-key-nvim;
        type = "lua";
        config = ''
          require('which-key').setup({
            plugins = {
              marks = true,
              registers = true,
              spelling = {
                enabled = true,
                suggestions = 20,
              },
            },
            window = {
              border = "rounded",
              position = "bottom",
              margin = { 1, 0, 1, 0 },
              padding = { 2, 2, 2, 2 },
            },
            layout = {
              height = { min = 4, max = 25 },
              width = { min = 20, max = 50 },
              spacing = 3,
              align = "left",
            },
          })
        '';
      }
    ];

    # Additional shell aliases for Neovim integration
    home-manager.users.yuki.programs.zsh.shellAliases = mkIf cfg.enable {
      # Neovim with modern CLI context
      nvim-git = "cd $(git rev-parse --show-toplevel 2>/dev/null || pwd) && nvim";
      nvim-find = "nvim $(fd --type f | fzf)";
      nvim-grep = "nvim $(rg --files-with-matches \"$1\" | fzf)";
    };
  };
}