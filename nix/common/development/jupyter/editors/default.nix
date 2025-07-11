{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.jupyter.editors;
in
{
  options.jupyter.editors = {
    enable = mkEnableOption "Jupyter editor integrations";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "Editor integration level";
    };
    
    vscode = mkEnableOption "VS Code Jupyter integration" // { default = true; };
    neovim = mkEnableOption "Neovim Jupyter integration" // { default = true; };
  };

  config = mkIf cfg.enable {
    # VS Code Jupyter integration
    programs.vscode = mkIf cfg.vscode {
      extensions = with pkgs.vscode-extensions; [
        ms-python.python
        ms-jupyter.jupyter
        ms-jupyter.notebook-renderers
        ms-python.vscode-pylance
      ];
      
      userSettings = {
        # Jupyter settings
        "jupyter.askForKernelRestart" = false;
        "jupyter.interactiveWindow.creationMode" = "perFile";
        "jupyter.notebookFileRoot" = "\${workspaceFolder}";
        
        # Python settings
        "python.defaultInterpreterPath" = "./venv/bin/python";
        "python.formatting.provider" = "black";
        "python.linting.enabled" = true;
        "python.linting.pylintEnabled" = true;
        "python.linting.flake8Enabled" = true;
        
        # Notebook settings
        "notebook.cellToolbarLocation" = {
          "default" = "right";
          "jupyter-notebook" = "left";
        };
        "notebook.output.textLineLimit" = 30;
        "notebook.outline.showCodeCells" = true;
        
        # File associations
        "files.associations" = {
          "*.ipynb" = "jupyter-notebook";
        };
      };
    };

    # Neovim Jupyter integration (via home-manager)
    home-manager.users.yuki.programs.neovim = mkIf cfg.neovim {
      plugins = with pkgs.vimPlugins; [
        # Core Jupyter support
        {
          plugin = pkgs.vimPlugins.jupytext-vim;
          config = ''
            " Enable jupytext for .py files with jupyter metadata
            let g:jupytext_fmt = 'py:percent'
            let g:jupytext_style = 'pycharm'
          '';
        }
        
        # Python development
        nvim-lspconfig
        null-ls-nvim
        
        # REPL integration
        iron-nvim
        
        # Enhanced display (optional)
        image-nvim
      ];
      
      extraLuaConfig = ''
        -- Jupyter/Python LSP setup
        local lspconfig = require('lspconfig')
        
        -- Python LSP
        lspconfig.pylsp.setup{
          settings = {
            pylsp = {
              plugins = {
                pycodestyle = {
                  ignore = {'W391', 'E501'},
                  maxLineLength = 88
                },
                flake8 = { enabled = true },
                black = { enabled = true },
                pylint = { enabled = true },
                mypy = { enabled = true }
              }
            }
          }
        }
        
        -- Iron REPL for Jupyter-like experience
        local iron = require("iron.core")
        iron.setup {
          config = {
            scratch_repl = true,
            repl_definition = {
              python = {
                command = {"python3"},
                format = require("iron.fts.common").bracketed_paste,
              }
            },
            repl_open_cmd = require('iron.view').bottom(40),
          },
          keymaps = {
            send_motion = "<space>sc",
            visual_send = "<space>sc",
            send_file = "<space>sf",
            send_line = "<space>sl",
            send_mark = "<space>sm",
            toggle_repl = "<space>st",
            interrupt = "<space>s<space>",
          },
        }
        
        -- Jupyter-style keymaps
        vim.keymap.set('n', '<leader>jr', ':IronRestart<CR>', { desc = 'Restart REPL' })
        vim.keymap.set('n', '<leader>jc', ':IronHide<CR>', { desc = 'Close REPL' })
        vim.keymap.set('v', '<leader>js', '<cmd>lua require("iron.core").send(nil, vim.api.nvim_get_visual_selection())<CR>', { desc = 'Send selection' })
      '';
    };
    
    # Global Jupyter editor configuration
    home-manager.users.yuki.home.file.".jupyter/jupyter_lab_config.py" = {
      text = ''
        # JupyterLab configuration for better editor integration
        
        c = get_config()
        
        # Interface settings
        c.LabApp.collaborative = True
        c.LabApp.news_url = None
        c.LabApp.check_for_updates_class = None
        
        # File browser settings
        c.ContentsManager.allow_hidden = False
        c.ContentsManager.pre_save_hook = None
        
        # Kernel settings
        c.MappingKernelManager.cull_idle_timeout = 3600  # 1 hour
        c.MappingKernelManager.cull_interval = 300       # 5 minutes
        c.MappingKernelManager.cull_connected = False
        
        # Security settings
        c.ServerApp.disable_check_xsrf = False
        c.ServerApp.allow_remote_access = False
        c.ServerApp.allow_root = False
        
        # Performance settings
        c.ResourceUseDisplay.mem_limit = 2 * 1024**3  # 2GB
        c.ResourceUseDisplay.track_cpu_percent = True
        c.ResourceUseDisplay.cpu_limit = 2  # 2 cores
      '';
    };
    
    # IPython configuration for better REPL experience
    home-manager.users.yuki.home.file.".ipython/profile_default/ipython_config.py" = {
      text = ''
        # IPython configuration for enhanced development experience
        
        c = get_config()
        
        # Terminal IPython settings
        c.TerminalIPythonApp.display_banner = True
        c.TerminalInteractiveShell.automagic = True
        c.TerminalInteractiveShell.autocall = 1
        c.TerminalInteractiveShell.colors = 'Linux'
        c.TerminalInteractiveShell.confirm_exit = False
        c.TerminalInteractiveShell.deep_reload = True
        
        # History settings
        c.HistoryManager.hist_file = ':memory:'
        c.HistoryAccessor.hist_file = ':memory:'
        
        # Completion settings
        c.IPCompleter.greedy = True
        c.IPCompleter.use_jedi = True
        
        # Display settings
        c.PlainTextFormatter.pprint = True
        c.InteractiveShell.ast_node_interactivity = 'all'
        
        # Auto-reload magic
        c.InteractiveShellApp.exec_lines = [
            '%load_ext autoreload',
            '%autoreload 2'
        ]
        
        # Common imports for data science
        c.InteractiveShellApp.exec_lines.extend([
            'import numpy as np',
            'import pandas as pd', 
            'import matplotlib.pyplot as plt',
            'import seaborn as sns',
            'print("📊 Data science environment ready")'
        ])
      '';
    };
  };
}