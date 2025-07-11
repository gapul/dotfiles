# Web開発環境 - エディターAI機能拡張
# VS Code、NeoVimでのAI機能拡張（Cursor、Claude Dev、その他AI拡張）

{ lib, pkgs, config, ... }:

let
  cfg = config.web.ai.editor;
in
{
  options.web.ai.editor = {
    enable = lib.mkEnableOption "Editor AI integrations";
    
    vscode = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable VS Code AI extensions";
      };
      
      extensions = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [
          "cursor"
          "claude-dev" 
          "tabnine"
          "codeium"
          "continue"
          "aws-codewhisperer"
        ]);
        default = [ "cursor" "claude-dev" "continue" ];
        description = "AI extensions to configure";
      };
      
      chatIntegration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable chat interfaces";
      };
      
      codebaseIndex = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable codebase indexing for context";
      };
      
      multiFileEdit = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable multi-file editing capabilities";
      };
    };
    
    neovim = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable NeoVim AI plugins";
      };
      
      plugins = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [
          "neural"
          "chatgpt"
          "codeium"
          "tabnine"
          "cmp-ai"
        ]);
        default = [ "neural" "chatgpt" "codeium" ];
        description = "AI plugins to configure";
      };
      
      apiKeys = {
        anthropic = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Anthropic API key (use environment variable)";
        };
        
        openai = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "OpenAI API key (use environment variable)";
        };
      };
    };
    
    features = {
      codeCompletion = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable AI code completion";
      };
      
      codeGeneration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable AI code generation";
      };
      
      codeExplanation = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable code explanation features";
      };
      
      refactoring = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable AI-powered refactoring";
      };
      
      testGeneration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable test generation";
      };
      
      documentation = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable documentation generation";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # VS Code AI extensions configuration
    home-manager.users.yuki.home.file.".vscode/ai-extensions-settings.json" = lib.mkIf cfg.vscode.enable {
      text = builtins.toJSON (lib.mkMerge [
        # Base AI settings
        {
          # AI-powered features
          "editor.suggest.preview" = true;
          "editor.suggest.showStatusBar" = true;
          "editor.inlineSuggest.enabled" = cfg.features.codeCompletion;
          
          # Chat integration
          "workbench.panel.chatPanel.alwaysShowWelcome" = false;
          
          # Multi-file editing
          "diffEditor.experimental.showMoves" = cfg.vscode.multiFileEdit;
          "diffEditor.renderSideBySide" = true;
          
          # Codebase indexing
          "typescript.suggest.includePackageJsonAutoImports" = "auto";
          "typescript.suggest.includeCompletionsForModuleExports" = true;
          
          # Security
          "security.workspace.trust.untrustedFiles" = "prompt";
          "security.workspace.trust.banner" = "always";
        }
        
        # Cursor-specific settings
        (lib.mkIf (lib.elem "cursor" cfg.vscode.extensions) {
          "cursor.aiChat.enabled" = cfg.vscode.chatIntegration;
          "cursor.aiCompletion.enabled" = cfg.features.codeCompletion;
          "cursor.aiGeneration.enabled" = cfg.features.codeGeneration;
          "cursor.multiFileEdit.enabled" = cfg.vscode.multiFileEdit;
          "cursor.codebaseContext.enabled" = cfg.vscode.codebaseIndex;
          
          # Cursor preferences
          "cursor.general.enableCodebaseIndexing" = cfg.vscode.codebaseIndex;
          "cursor.general.enableReferenceProvider" = true;
          "cursor.general.enableAutoCompletion" = cfg.features.codeCompletion;
        })
        
        # Claude Dev settings
        (lib.mkIf (lib.elem "claude-dev" cfg.vscode.extensions) {
          "claude-dev.apiKey" = null; # Set via environment variable
          "claude-dev.model" = "claude-3-sonnet-20240229";
          "claude-dev.enableCodeGeneration" = cfg.features.codeGeneration;
          "claude-dev.enableRefactoring" = cfg.features.refactoring;
          "claude-dev.enableDocumentation" = cfg.features.documentation;
          "claude-dev.enableTestGeneration" = cfg.features.testGeneration;
        })
        
        # Continue settings
        (lib.mkIf (lib.elem "continue" cfg.vscode.extensions) {
          "continue.enableTabAutocomplete" = cfg.features.codeCompletion;
          "continue.enableCodeActions" = true;
          "continue.contextLength" = 8000;
          "continue.temperature" = 0.2;
        })
        
        # Codeium settings
        (lib.mkIf (lib.elem "codeium" cfg.vscode.extensions) {
          "codeium.enableCodeLens" = true;
          "codeium.enableSearch" = true;
          "codeium.enableConfig" = true;
        })
        
        # TabNine settings
        (lib.mkIf (lib.elem "tabnine" cfg.vscode.extensions) {
          "tabnine.experimentalAutoImports" = true;
          "tabnine.disable_line_regex" = [
            ".*password.*"
            ".*secret.*"
            ".*token.*"
            ".*key.*"
          ];
        })
      ]);
    };
    
    # NeoVim AI configuration
    home-manager.users.yuki.home.file.".config/nvim/lua/ai-config.lua" = lib.mkIf cfg.neovim.enable {
      text = ''
        -- AI integrations for NeoVim
        
        -- Global AI settings
        vim.g.ai_enabled = true
        vim.g.ai_code_completion = ${if cfg.features.codeCompletion then "true" else "false"}
        vim.g.ai_code_generation = ${if cfg.features.codeGeneration then "true" else "false"}
        
        ${lib.optionalString (lib.elem "neural" cfg.neovim.plugins) ''
        -- Neural plugin configuration
        require('neural').setup({
          source = {
            openai = {
              api_key = os.getenv('OPENAI_API_KEY'),
            },
            anthropic = {
              api_key = os.getenv('ANTHROPIC_API_KEY'),
            },
          },
          ui = {
            use_prompt = true,
            prompt_border = 'rounded',
          },
        })
        ''}
        
        ${lib.optionalString (lib.elem "chatgpt" cfg.neovim.plugins) ''
        -- ChatGPT plugin configuration
        require('chatgpt').setup({
          api_key_cmd = 'echo $OPENAI_API_KEY',
          yank_register = '+',
          edit_with_instructions = {
            diff = false,
            keymaps = {
              close = '<C-c>',
              accept = '<C-y>',
              toggle_diff = '<C-d>',
              toggle_settings = '<C-o>',
              cycle_windows = '<Tab>',
              use_output_as_input = '<C-i>',
            },
          },
          chat = {
            welcome_message = 'Welcome to ChatGPT!',
            loading_text = 'Loading, please wait ...',
            question_sign = '',
            answer_sign = 'ﮧ',
            max_line_length = 120,
            sessions_window = {
              border = {
                style = 'rounded',
                text = {
                  top = ' Sessions ',
                },
              },
              win_options = {
                winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
              },
            },
            keymaps = {
              close = { '<C-c>' },
              yank_last = '<C-y>',
              yank_last_code = '<C-k>',
              scroll_up = '<C-u>',
              scroll_down = '<C-d>',
              new_session = '<C-n>',
              cycle_windows = '<Tab>',
              cycle_modes = '<C-f>',
              select_session = '<Space>',
              rename_session = 'r',
              delete_session = 'd',
            },
          },
          popup_layout = {
            default = 'center',
            center = {
              width = '80%',
              height = '80%',
            },
            right = {
              width = '30%',
              width_settings_open = '50%',
            },
          },
          popup_window = {
            border = {
              highlight = 'FloatBorder',
              style = 'rounded',
              text = {
                top = ' ChatGPT ',
              },
            },
            win_options = {
              wrap = true,
              linebreak = true,
              foldcolumn = '1',
              winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
            },
            buf_options = {
              filetype = 'markdown',
            },
          },
          system_window = {
            border = {
              highlight = 'FloatBorder',
              style = 'rounded',
              text = {
                top = ' SYSTEM ',
              },
            },
            win_options = {
              wrap = true,
              linebreak = true,
              foldcolumn = '2',
              winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
            },
          },
          popup_input = {
            prompt = '  ',
            border = {
              highlight = 'FloatBorder',
              style = 'rounded',
              text = {
                top_align = 'center',
                top = ' Prompt ',
              },
            },
            win_options = {
              winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
            },
            submit = '<C-Enter>',
            submit_n = '<Enter>',
          },
          settings_window = {
            border = {
              style = 'rounded',
              text = {
                top = ' Settings ',
              },
            },
            win_options = {
              winhighlight = 'Normal:Normal,FloatBorder:FloatBorder',
            },
          },
          openai_params = {
            model = 'gpt-4',
            frequency_penalty = 0,
            presence_penalty = 0,
            max_tokens = 4000,
            temperature = 0.2,
            top_p = 0.1,
            n = 1,
          },
          openai_edit_params = {
            model = 'gpt-4',
            temperature = 0.2,
            top_p = 1,
            n = 1,
          },
          actions_paths = {
            '~/.config/nvim/chatgpt-actions.json',
          },
          show_quickfixes_cmd = 'Trouble quickfix',
          predefined_chat_gpt_prompts = 'https://raw.githubusercontent.com/f/awesome-chatgpt-prompts/main/prompts.csv',
        })
        ''}
        
        ${lib.optionalString (lib.elem "codeium" cfg.neovim.plugins) ''
        -- Codeium configuration
        vim.g.codeium_enabled = ${if cfg.features.codeCompletion then "true" else "false"}
        vim.g.codeium_disable_bindings = 0
        
        -- Key mappings for Codeium
        vim.keymap.set('i', '<C-g>', function() return vim.fn['codeium#Accept']() end, { expr = true })
        vim.keymap.set('i', '<c-;>', function() return vim.fn['codeium#CycleCompletions'](1) end, { expr = true })
        vim.keymap.set('i', '<c-,>', function() return vim.fn['codeium#CycleCompletions'](-1) end, { expr = true })
        vim.keymap.set('i', '<c-x>', function() return vim.fn['codeium#Clear']() end, { expr = true })
        ''}
        
        ${lib.optionalString (lib.elem "cmp-ai" cfg.neovim.plugins) ''
        -- AI completion source for nvim-cmp
        local cmp = require('cmp')
        local cmp_ai = require('cmp_ai.config')
        
        cmp_ai:setup({
          max_lines = 1000,
          provider = 'OpenAI',
          provider_options = {
            model = 'gpt-4',
          },
          notify = true,
          notify_callback = function(msg)
            vim.notify(msg)
          end,
          run_on_every_keystroke = ${if cfg.features.codeCompletion then "true" else "false"},
          ignored_file_types = {
            -- default is not to ignore
            -- uncomment to ignore files/buffers in certain file types
            -- markdown = true,
          },
        })
        ''}
        
        -- AI utility functions
        local ai_utils = {}
        
        ${lib.optionalString cfg.features.codeExplanation ''
        -- Code explanation function
        ai_utils.explain_code = function()
          local start_line = vim.fn.line("'<")
          local end_line = vim.fn.line("'>")
          local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
          local code = table.concat(lines, '\n')
          
          local prompt = "Explain the following code in detail:\n\n" .. code
          require('chatgpt').run_edit_with_instructions(prompt)
        end
        ''}
        
        ${lib.optionalString cfg.features.refactoring ''
        -- Refactoring function
        ai_utils.refactor_code = function()
          local start_line = vim.fn.line("'<")
          local end_line = vim.fn.line("'>")
          local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
          local code = table.concat(lines, '\n')
          
          local prompt = "Refactor the following code to improve readability, performance, and maintainability:\n\n" .. code
          require('chatgpt').run_edit_with_instructions(prompt)
        end
        ''}
        
        ${lib.optionalString cfg.features.testGeneration ''
        -- Test generation function
        ai_utils.generate_tests = function()
          local start_line = vim.fn.line("'<")
          local end_line = vim.fn.line("'>")
          local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
          local code = table.concat(lines, '\n')
          
          local prompt = "Generate comprehensive unit tests for the following code:\n\n" .. code
          require('chatgpt').run_edit_with_instructions(prompt)
        end
        ''}
        
        ${lib.optionalString cfg.features.documentation ''
        -- Documentation generation function
        ai_utils.generate_docs = function()
          local start_line = vim.fn.line("'<")
          local end_line = vim.fn.line("'>")
          local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
          local code = table.concat(lines, '\n')
          
          local prompt = "Generate comprehensive documentation for the following code including JSDoc comments:\n\n" .. code
          require('chatgpt').run_edit_with_instructions(prompt)
        end
        ''}
        
        -- Key mappings for AI functions
        vim.keymap.set('v', '<leader>ae', ai_utils.explain_code, { desc = 'AI: Explain code' })
        vim.keymap.set('v', '<leader>ar', ai_utils.refactor_code, { desc = 'AI: Refactor code' })
        vim.keymap.set('v', '<leader>at', ai_utils.generate_tests, { desc = 'AI: Generate tests' })
        vim.keymap.set('v', '<leader>ad', ai_utils.generate_docs, { desc = 'AI: Generate docs' })
        
        -- AI chat commands
        vim.api.nvim_create_user_command('AIChat', 'ChatGPT', {})
        vim.api.nvim_create_user_command('AIEdit', 'ChatGPTEditWithInstructions', {})
        vim.api.nvim_create_user_command('AIRun', 'ChatGPTRun', {})
        vim.api.nvim_create_user_command('AIActAs', 'ChatGPTActAs', {})
      '';
    };
    
    # Environment variables for AI services
    home-manager.users.yuki.home.sessionVariables = {
      # API keys (should be set separately for security)
      # OPENAI_API_KEY = ""; # Set in secrets
      # ANTHROPIC_API_KEY = ""; # Set in secrets
      # CODEIUM_API_KEY = ""; # Set in secrets
      
      # AI preferences
      AI_COMPLETION_ENABLED = if cfg.features.codeCompletion then "1" else "0";
      AI_GENERATION_ENABLED = if cfg.features.codeGeneration then "1" else "0";
    };
    
    # AI health check script
    home-manager.users.yuki.home.file."bin/ai-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🤖 AI Editor Integration Health Check"
        echo "===================================="
        
        # Check VS Code extensions
        ${lib.optionalString cfg.vscode.enable ''
        if command -v code &> /dev/null; then
          echo "✅ VS Code: available"
          
          extensions_check() {
            local ext="$1"
            local name="$2"
            if code --list-extensions | grep -q "$ext"; then
              echo "✅ $name: installed"
            else
              echo "❌ $name: not installed (code --install-extension $ext)"
            fi
          }
          
          ${lib.concatMapStringsSep "\n          " (ext: 
            if ext == "cursor" then ''extensions_check "cursor" "Cursor AI"''
            else if ext == "claude-dev" then ''extensions_check "saoudrizwan.claude-dev" "Claude Dev"''
            else if ext == "continue" then ''extensions_check "continue.continue" "Continue"''
            else if ext == "codeium" then ''extensions_check "codeium.codeium" "Codeium"''
            else if ext == "tabnine" then ''extensions_check "tabnine.tabnine-vscode" "TabNine"''
            else if ext == "aws-codewhisperer" then ''extensions_check "amazonwebservices.aws-toolkit-vscode" "AWS CodeWhisperer"''
            else ""
          ) cfg.vscode.extensions}
        else
          echo "⚪ VS Code: not found"
        fi
        ''}
        
        echo ""
        echo "🔧 NeoVim Plugins:"
        
        # Check NeoVim plugins
        ${lib.optionalString cfg.neovim.enable ''
        if command -v nvim &> /dev/null; then
          echo "✅ NeoVim: available"
          
          if [[ -f ~/.config/nvim/lua/ai-config.lua ]]; then
            echo "✅ AI configuration: present"
          else
            echo "❌ AI configuration: missing"
          fi
          
          # Check for plugin configuration
          ${lib.concatMapStringsSep "\n          " (plugin:
            ''echo "📦 ${plugin}: configured"''
          ) cfg.neovim.plugins}
        else
          echo "⚪ NeoVim: not found"
        fi
        ''}
        
        echo ""
        echo "🔑 Environment Variables:"
        
        # Check API keys (without revealing them)
        if [[ -n "''${OPENAI_API_KEY:-}" ]]; then
          echo "✅ OPENAI_API_KEY: set"
        else
          echo "⚪ OPENAI_API_KEY: not set"
        fi
        
        if [[ -n "''${ANTHROPIC_API_KEY:-}" ]]; then
          echo "✅ ANTHROPIC_API_KEY: set"
        else
          echo "⚪ ANTHROPIC_API_KEY: not set"
        fi
        
        if [[ -n "''${CODEIUM_API_KEY:-}" ]]; then
          echo "✅ CODEIUM_API_KEY: set"
        else
          echo "⚪ CODEIUM_API_KEY: not set"
        fi
        
        echo ""
        echo "📊 Features:"
        echo "Code completion: ${if cfg.features.codeCompletion then "enabled" else "disabled"}"
        echo "Code generation: ${if cfg.features.codeGeneration then "enabled" else "disabled"}"
        echo "Code explanation: ${if cfg.features.codeExplanation then "enabled" else "disabled"}"
        echo "Refactoring: ${if cfg.features.refactoring then "enabled" else "disabled"}"
        echo "Test generation: ${if cfg.features.testGeneration then "enabled" else "disabled"}"
        echo "Documentation: ${if cfg.features.documentation then "enabled" else "disabled"}"
        
        echo ""
        echo "✅ AI editor integration health check completed!"
      '';
    };
  };
}