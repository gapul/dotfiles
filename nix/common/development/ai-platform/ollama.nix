# Ollama Local LLM Integration - Advanced Configuration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.ai-platform.ollama;
  
  # プラットフォーム検出
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  options.dotfiles.development.ai-platform.ollama = {
    enable = mkEnableOption "Advanced Ollama Local LLM Integration";
    
    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically start Ollama service";
    };
    
    models = mkOption {
      type = types.listOf types.str;
      default = [ "codellama:7b" "llama2:7b" "mistral:7b" "phi:2.7b" ];
      description = "List of models to install automatically";
    };
    
    cliIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable CLI integration tools (sgpt, mods)";
    };
    
    neovimIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Neovim integration for local LLM";
    };
    
    privacy = {
      localOnly = mkOption {
        type = types.bool;
        default = true;
        description = "Force local-only operations, no external API calls";
      };
      
      encryptedStorage = mkOption {
        type = types.bool;
        default = false;
        description = "Enable encrypted model storage";
      };
    };
    
    performance = {
      gpu = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GPU acceleration if available";
      };
      
      memoryLimit = mkOption {
        type = types.str;
        default = "8GB";
        description = "Memory limit for Ollama processes";
      };
    };
  };

  config = mkIf cfg.enable {
    # Ollama package installation (via Homebrew on macOS)
    home-manager.users.yuki.home.packages = with pkgs; [
      # CLI tools for LLM interaction
      curl  # For API calls
      jq    # JSON processing
    ] ++ optionals cfg.cliIntegration [
      # CLI AI assistants (will install via npm/pip in setup script)
    ];

    # Ollama service management
    home-manager.users.yuki.home.file."bin/ollama-manager" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Advanced Ollama Manager for Local LLM
        set -euo pipefail
        
        ACTION="''${1:-status}"
        MODEL="''${2:-codellama:7b}"
        
        # Configuration
        OLLAMA_HOST="127.0.0.1:11434"
        OLLAMA_DATA_DIR="$HOME/.ollama"
        MODELS=(${concatStringsSep " " (map (m: ''"${m}"'') cfg.models)})
        
        # Colors for output
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m' # No Color
        
        log_info() {
          echo -e "''${BLUE}ℹ️  $1''${NC}"
        }
        
        log_success() {
          echo -e "''${GREEN}✅ $1''${NC}"
        }
        
        log_warning() {
          echo -e "''${YELLOW}⚠️  $1''${NC}"
        }
        
        log_error() {
          echo -e "''${RED}❌ $1''${NC}"
        }
        
        check_ollama_installation() {
          if ! command -v ollama &> /dev/null; then
            log_error "Ollama not found. Installing via Homebrew..."
            if command -v brew &> /dev/null; then
              brew install ollama
              log_success "Ollama installed via Homebrew"
            else
              log_error "Please install Ollama manually: https://ollama.ai"
              exit 1
            fi
          fi
        }
        
        start_ollama_service() {
          log_info "Starting Ollama service..."
          
          # Check if already running
          if pgrep -f "ollama serve" &> /dev/null; then
            log_warning "Ollama service already running"
            return 0
          fi
          
          # Start service in background
          ${if cfg.autoStart then ''
            nohup ollama serve > "$HOME/.ollama/service.log" 2>&1 &
            sleep 5
            
            # Verify service is running
            if curl -s "http://$OLLAMA_HOST/api/tags" &> /dev/null; then
              log_success "Ollama service started successfully"
            else
              log_error "Failed to start Ollama service"
              exit 1
            fi
          '' else ''
            log_info "Auto-start disabled. Start manually: ollama serve"
          ''}
        }
        
        stop_ollama_service() {
          log_info "Stopping Ollama service..."
          
          if pgrep -f "ollama serve" &> /dev/null; then
            pkill -f "ollama serve"
            sleep 2
            log_success "Ollama service stopped"
          else
            log_warning "Ollama service not running"
          fi
        }
        
        pull_models() {
          log_info "Pulling recommended models..."
          
          start_ollama_service
          
          for model in "''${MODELS[@]}"; do
            log_info "Pulling $model..."
            if ollama pull "$model"; then
              log_success "$model installed successfully"
            else
              log_error "Failed to pull $model"
            fi
          done
        }
        
        list_models() {
          log_info "Available models:"
          if command -v ollama &> /dev/null && ollama list &> /dev/null; then
            ollama list
          else
            log_warning "Ollama service not available"
          fi
        }
        
        interactive_chat() {
          local model="$1"
          
          log_info "Starting interactive chat with $model"
          log_info "Type 'exit' to quit, 'switch <model>' to change model"
          
          start_ollama_service
          
          if ! ollama list | grep -q "$model"; then
            log_warning "Model $model not found. Pulling..."
            ollama pull "$model"
          fi
          
          # Enhanced interactive session
          while true; do
            echo -n -e "''${BLUE}You:''${NC} "
            read -r user_input
            
            case "$user_input" in
              "exit"|"quit")
                log_info "Goodbye!"
                break
                ;;
              switch\ *)
                new_model="''${user_input#switch }"
                if ollama list | grep -q "$new_model"; then
                  model="$new_model"
                  log_success "Switched to $model"
                else
                  log_error "Model $new_model not available"
                fi
                ;;
              *)
                echo -e "''${GREEN}$model:''${NC}"
                ollama run "$model" "$user_input"
                echo ""
                ;;
            esac
          done
        }
        
        code_generation() {
          local prompt="$1"
          local language="''${2:-auto}"
          
          start_ollama_service
          
          log_info "Generating code for: $prompt"
          
          # Enhanced prompt for code generation
          enhanced_prompt="You are an expert programmer. Generate clean, well-documented code for the following request. Include comments and follow best practices. Language preference: $language

Request: $prompt"
          
          ollama run codellama "$enhanced_prompt"
        }
        
        code_review() {
          local file_or_diff="''${1:-}"
          
          if [[ -z "$file_or_diff" ]]; then
            # Review git diff
            if git rev-parse --git-dir > /dev/null 2>&1; then
              local diff_content
              diff_content=$(git diff HEAD~1..HEAD)
              if [[ -z "$diff_content" ]]; then
                log_warning "No changes to review"
                return 0
              fi
            else
              log_error "Not in a git repository and no file specified"
              exit 1
            fi
          elif [[ -f "$file_or_diff" ]]; then
            # Review specific file
            diff_content=$(cat "$file_or_diff")
          else
            # Treat as git commit range
            diff_content=$(git diff "$file_or_diff")
          fi
          
          start_ollama_service
          
          log_info "Performing AI code review..."
          
          review_prompt="Perform a thorough code review of the following code. Analyze:
1. Code quality and best practices
2. Potential bugs or security issues
3. Performance optimizations
4. Maintainability improvements
5. Design patterns and architecture

Code to review:
$diff_content"
          
          ollama run codellama "$review_prompt" | tee "$HOME/.ollama/last_review.md"
          
          log_success "Review saved to $HOME/.ollama/last_review.md"
        }
        
        optimize_performance() {
          log_info "Optimizing Ollama performance..."
          
          # GPU optimization
          ${if cfg.performance.gpu then ''
            if command -v nvidia-smi &> /dev/null; then
              log_info "NVIDIA GPU detected, enabling CUDA"
              export CUDA_VISIBLE_DEVICES=0
            elif [[ "$(uname)" == "Darwin" ]] && system_profiler SPDisplaysDataType | grep -q "Metal"; then
              log_info "macOS Metal GPU acceleration enabled"
              export OLLAMA_GPU_LAYERS=35
            fi
          '' else ''
            log_info "GPU acceleration disabled"
            export OLLAMA_GPU_LAYERS=0
          ''}
          
          # Memory optimization
          export OLLAMA_MAX_MEMORY="${cfg.performance.memoryLimit}"
          
          log_success "Performance optimizations applied"
        }
        
        case "$ACTION" in
          "install"|"setup")
            check_ollama_installation
            start_ollama_service
            pull_models
            
            # Install CLI integrations
            ${if cfg.cliIntegration then ''
              log_info "Installing CLI AI tools..."
              if command -v npm &> /dev/null; then
                npm install -g @mendable/firecrawl-js shell-gpt
                log_success "CLI tools installed via npm"
              fi
              
              if command -v pip &> /dev/null; then
                pip install --user shell-gpt mods
                log_success "Python AI tools installed"
              fi
            '' else ''
              log_info "CLI integration disabled"
            ''}
            
            optimize_performance
            log_success "Ollama setup complete!"
            ;;
            
          "start")
            check_ollama_installation
            start_ollama_service
            optimize_performance
            ;;
            
          "stop")
            stop_ollama_service
            ;;
            
          "restart")
            stop_ollama_service
            sleep 2
            start_ollama_service
            optimize_performance
            ;;
            
          "status")
            log_info "Ollama System Status"
            echo "===================="
            
            if command -v ollama &> /dev/null; then
              log_success "Ollama binary: Available"
            else
              log_error "Ollama binary: Not found"
            fi
            
            if pgrep -f "ollama serve" &> /dev/null; then
              log_success "Service: Running"
            else
              log_warning "Service: Not running"
            fi
            
            if curl -s "http://$OLLAMA_HOST/api/tags" &> /dev/null; then
              log_success "API: Responsive"
              echo ""
              list_models
            else
              log_warning "API: Not accessible"
            fi
            
            echo ""
            log_info "Configuration:"
            echo "  Host: $OLLAMA_HOST"
            echo "  Data dir: $OLLAMA_DATA_DIR"
            echo "  Memory limit: ${cfg.performance.memoryLimit}"
            echo "  GPU enabled: ${if cfg.performance.gpu then "Yes" else "No"}"
            echo "  Privacy mode: ${if cfg.privacy.localOnly then "Local only" else "External APIs allowed"}"
            ;;
            
          "models")
            list_models
            ;;
            
          "pull")
            if [[ -n "''${2:-}" ]]; then
              ollama pull "$2"
            else
              pull_models
            fi
            ;;
            
          "chat")
            interactive_chat "$MODEL"
            ;;
            
          "code")
            if [[ -n "''${2:-}" ]]; then
              code_generation "$2" "''${3:-auto}"
            else
              log_error "Usage: ollama-manager code '<prompt>' [language]"
              exit 1
            fi
            ;;
            
          "review")
            code_review "''${2:-}"
            ;;
            
          "health")
            # Comprehensive health check
            log_info "Comprehensive Health Check"
            echo "=========================="
            
            # Check service health
            ollama-manager status
            
            # Check model performance
            if curl -s "http://$OLLAMA_HOST/api/tags" &> /dev/null; then
              echo ""
              log_info "Testing model performance..."
              
              # Quick performance test
              start_time=$(date +%s)
              ollama run phi:2.7b "Hello, test response" > /dev/null 2>&1
              end_time=$(date +%s)
              duration=$((end_time - start_time))
              
              if [[ $duration -lt 10 ]]; then
                log_success "Model response time: ''${duration}s (Good)"
              elif [[ $duration -lt 30 ]]; then
                log_warning "Model response time: ''${duration}s (Acceptable)"
              else
                log_error "Model response time: ''${duration}s (Slow)"
              fi
            fi
            ;;
            
          *)
            echo "Usage: ollama-manager <action> [options]"
            echo ""
            echo "Actions:"
            echo "  install/setup  - Install and configure Ollama"
            echo "  start         - Start Ollama service"
            echo "  stop          - Stop Ollama service"
            echo "  restart       - Restart Ollama service"
            echo "  status        - Show system status"
            echo "  models        - List available models"
            echo "  pull [model]  - Pull specific model or all recommended"
            echo "  chat [model]  - Interactive chat session"
            echo "  code <prompt> - Generate code"
            echo "  review [file] - AI code review"
            echo "  health        - Comprehensive health check"
            echo ""
            echo "Examples:"
            echo "  ollama-manager setup"
            echo "  ollama-manager chat codellama:7b"
            echo "  ollama-manager code 'Create a REST API in Python'"
            echo "  ollama-manager review src/main.rs"
            ;;
        esac
      '';
    };

    # Neovim integration for local LLM
    home-manager.users.yuki.home.file.".config/nvim/lua/plugins/ollama-local.lua" = mkIf cfg.neovimIntegration {
      text = ''
        -- Ollama Local LLM Integration for Neovim
        return {
          -- Local LLM completion
          {
            "David-Kunz/gen.nvim",
            opts = {
              model = "codellama:7b",
              host = "localhost",
              port = "11434",
              display_mode = "float",
              show_prompt = false,
              show_model = false,
              no_auto_close = true,
              init = function(options) pcall(io.popen, "ollama serve > /dev/null 2>&1 &") end,
              command = function(options)
                local body = {model = options.model, stream = true}
                return "curl --silent --no-buffer -X POST http://" .. options.host .. ":" .. options.port .. "/api/chat -H 'Content-Type: application/json' -d $body"
              end,
              list_models = function(options)
                local response = vim.fn.systemlist("curl --silent http://" .. options.host .. ":" .. options.port .. "/api/tags")
                local list = {}
                for _, line in ipairs(response) do
                  if line:match('"name"') then
                    local model_name = line:match('"name":%s*"([^"]+)"')
                    if model_name then
                      table.insert(list, model_name)
                    end
                  end
                end
                return list
              end,
            },
          },
          
          -- AI chat interface
          {
            "jackMort/ChatGPT.nvim",
            event = "VeryLazy",
            config = function()
              require("chatgpt").setup({
                api_host_cmd = "echo localhost:11434",
                api_key_cmd = "echo dummy_key", -- Ollama doesn't need API key
                openai_params = {
                  model = "codellama:7b",
                  temperature = 0.1,
                  max_tokens = 2048,
                },
                openai_edit_params = {
                  model = "codellama:7b",
                  temperature = 0.1,
                  top_p = 1,
                  n = 1,
                },
                chat = {
                  welcome_message = "Welcome to Local LLM (Ollama) Chat!",
                  loading_text = "Loading local model...",
                  question_sign = "",
                  answer_sign = "󰚩",
                  border_left_sign = "",
                  border_right_sign = "",
                  max_line_length = 120,
                  sessions_window = {
                    active_sign = "  ",
                    inactive_sign = "  ",
                    current_line_sign = "",
                    border = {
                      style = "rounded",
                      text = {
                        top = " Local AI Sessions ",
                      },
                    },
                  },
                },
                popup_layout = {
                  default = "center",
                  center = {
                    width = "80%",
                    height = "80%",
                  },
                  right = {
                    width = "30%",
                    width_settings_open = "50%",
                  },
                },
                popup_window = {
                  border = {
                    highlight = "FloatBorder",
                    style = "rounded",
                    text = {
                      top = " Local LLM Chat ",
                    },
                  },
                },
                settings_window = {
                  setting_sign = "  ",
                  border = {
                    style = "rounded",
                    text = {
                      top = " Settings ",
                    },
                  },
                },
                popup_input = {
                  prompt = "  ",
                  border = {
                    highlight = "FloatBorder",
                    style = "rounded",
                    text = {
                      top_align = "center",
                      top = " Prompt ",
                    },
                  },
                },
              })
            end,
            dependencies = {
              "MunifTanjim/nui.nvim",
              "nvim-lua/plenary.nvim",
              "folke/trouble.nvim",
              "nvim-telescope/telescope.nvim"
            }
          },
        }
      '';
    };

    # Shell aliases for Ollama
    home-manager.users.yuki.programs.zsh.shellAliases = {
      # Ollama management
      ollama-setup = "ollama-manager setup";
      ollama-status = "ollama-manager status";
      ollama-health = "ollama-manager health";
      
      # AI interactions
      ai-chat = lib.mkForce "ollama-manager chat";
      ai-code = "ollama-manager code";
      ai-local-review = "ollama-manager review";
      
      # Model management
      models = "ollama-manager models";
      pull-model = "ollama-manager pull";
      
      # Quick AI commands
      ask-ai = "ollama run codellama";
      code-help = "ollama run codellama 'Explain this code:'";
    };

    # Environment variables for Ollama
    home-manager.users.yuki.home.sessionVariables = {
      OLLAMA_HOST = "127.0.0.1:11434";
      OLLAMA_MODELS_DIR = "$HOME/.ollama/models";
      OLLAMA_LOGS_DIR = "$HOME/.ollama/logs";
      
      # Privacy settings
      OLLAMA_ORIGINS = mkIf cfg.privacy.localOnly "localhost,127.0.0.1";
      OLLAMA_DEBUG = "false";
      
      # Performance settings
      OLLAMA_MAX_MEMORY = cfg.performance.memoryLimit;
      OLLAMA_GPU_LAYERS = mkIf cfg.performance.gpu "35";
      OLLAMA_NUM_PARALLEL = "4";
      OLLAMA_MAX_QUEUE = "512";
    };

    # Automatic service management
    home-manager.users.yuki.programs.zsh.initContent = mkIf cfg.autoStart ''
      # Auto-start Ollama service if not running
      if command -v ollama &> /dev/null && ! pgrep -f "ollama serve" &> /dev/null; then
        echo "🤖 Starting Ollama service..."
        nohup ollama serve > "$HOME/.ollama/service.log" 2>&1 &
      fi
    '';

    # Create necessary directories
    home-manager.users.yuki.home.file.".ollama/.keep".text = "";
    home-manager.users.yuki.home.file.".ollama/logs/.keep".text = "";
  };
}