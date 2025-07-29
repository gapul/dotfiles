# TeX environment configuration
{ lib, pkgs, config, ... }:

let
  cfg = config.dotfiles.development.tex;
in {
  options.dotfiles.development.tex = {
    enable = lib.mkEnableOption "TeX development environment";
    
    profile = lib.mkOption {
      type = lib.types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "TeX installation profile";
    };
    
    texlive = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TeXLive distribution";
      };
      
      scheme = lib.mkOption {
        type = lib.types.enum [ "basic" "medium" "full" ];
        default = "medium";
        description = "TeXLive scheme to install";
      };
    };
    
    lsp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TeX language server support";
      };
    };
    
    modernWorkflow = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable modern academic writing workflow (VS Code, Pandoc, Neovim)";
      };
      
      vscode = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Configure VS Code with LaTeX Workshop";
        };
      };
      
      neovim = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Configure Neovim with Vimtex";
        };
      };
      
      pandoc = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Pandoc integration for Markdown to LaTeX conversion";
        };
      };
      
      pdfViewer = lib.mkOption {
        type = lib.types.enum [ "zathura" "skim" "preview" ];
        default = "zathura";
        description = "PDF viewer with SyncTeX support";
      };
    };
    
    fonts = {
      japanese = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Japanese font configuration for LuaLaTeX";
        };
        
        serif = lib.mkOption {
          type = lib.types.str;
          default = "Noto Serif CJK JP";
          description = "Japanese serif font for LuaLaTeX";
        };
        
        sans = lib.mkOption {
          type = lib.types.str;
          default = "Noto Sans CJK JP";
          description = "Japanese sans-serif font for LuaLaTeX";
        };
      };
    };
    
    additionalPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional TeX-related packages";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; let
      # TeXLive distribution based on profile
      texlivePackages = if cfg.profile == "minimal" then [
        texlive.combined.scheme-basic
      ] else if cfg.profile == "standard" then [
        texlive.combined.scheme-medium
      ] else [
        texlive.combined.scheme-full
      ];
      
      # Core TeX tools
      coreTexTools = [
        # PDF utilities
        qpdf              # PDF manipulation
        pdftk             # PDF toolkit
        ghostscript       # PostScript/PDF processing
        poppler_utils     # PDF utilities (pdfinfo, pdftotext, etc.)
        
        # LaTeX utilities
        latexrun          # LaTeX build tool
        rubber            # LaTeX build system
        
        # Bibtex utilities
        biber             # Modern bibliography processor
        
        # Graphics tools for LaTeX
        imagemagick       # Image manipulation
        graphviz          # Graph visualization
        
        # Fonts
        # cm-super          # Computer Modern fonts (included in TeX Live)
        # lmodern           # Latin Modern fonts (included in TeX Live)
      ];
      
      # Language server and development tools
      lspTools = lib.optionals cfg.lsp.enable [
        texlab            # TeX language server
        ltex-ls           # Grammar/spell checker for LaTeX
      ];
      
      # Additional editor support
      editorSupport = [
        # Spell checking
        hunspell
        hunspellDicts.en_US
        # hunspellDicts.ja_JP  # Japanese dictionary not available
        
        # Preview tools
        zathura           # Minimal PDF viewer
        evince            # GNOME PDF viewer (Linux)
      ] ++ lib.optionals pkgs.stdenv.isDarwin [
        # macOS specific tools
        # Note: Skim and other GUI apps are typically installed via Homebrew on macOS
      ];
      
      # Modern workflow tools
      modernWorkflowTools = lib.optionals cfg.modernWorkflow.enable [
        # Document conversion
        pandoc            # Universal document converter
        # pandoc-crossref   # Cross-references for Pandoc (may not be available)
        
        # Modern editors
        vscode            # VS Code editor
        
        # Japanese fonts for LuaLaTeX
        noto-fonts-cjk-sans    # Noto CJK fonts
        
        # Additional bibliography tools
        # jabref            # Bibliography management (may not be available in nixpkgs)
      ] ++ lib.optionals cfg.modernWorkflow.pandoc.enable [
        # Pandoc filters
        # Note: Many filters are available as separate packages
      ];
      
    in texlivePackages ++ coreTexTools ++ lspTools ++ editorSupport ++ modernWorkflowTools ++ cfg.additionalPackages;
    
    # Environment variables for TeX
    environment.variables = {
      TEXMFHOME = "$HOME/.texmf";
      TEXMFVAR = "$HOME/.texlive/texmf-var";
      TEXMFCONFIG = "$HOME/.texlive/texmf-config";
    };
    
    # Shell aliases for TeX workflows
    environment.shellAliases = {
      # LaTeX compilation shortcuts
      latex-build = "latexmk -pdf -pvc";
      latex-clean = "latexmk -c";
      latex-cleanall = "latexmk -C";
      
      # PDF manipulation shortcuts
      pdf-info = "pdfinfo";
      pdf-merge = "pdftk *.pdf cat output merged.pdf";
      pdf-compress = "gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH -sOutputFile=compressed.pdf";
      
      # Bibliography tools
      bib-clean = "biber --tool --output-align --output-indent=2 --output-fieldcase=lower";
    };
    
    
    # Modern workflow editor configurations
    home-manager.users.yuki = lib.mkIf cfg.modernWorkflow.enable {
      # VS Code configuration for LaTeX Workshop
      programs.vscode = lib.mkIf cfg.modernWorkflow.vscode.enable {
        enable = true;
        profiles.default = {
          extensions = with pkgs.vscode-extensions; [
            james-yu.latex-workshop
            ms-vscode.cpptools  # For better syntax highlighting
          ];
          userSettings = {
          # LaTeX Workshop settings
          "latex-workshop.latex.tools" = [
            {
              name = "lualatex";
              command = "lualatex";
              args = [
                "-synctex=1"
                "-interaction=nonstopmode"
                "-file-line-error"
                "%DOCFILE%"
              ];
            }
            {
              name = "biber";
              command = "biber";
              args = [ "%DOCFILE%" ];
            }
          ];
          
          "latex-workshop.latex.recipes" = [
            {
              name = "LuaLaTeX + Biber";
              tools = [ "lualatex" "biber" "lualatex" "lualatex" ];
            }
            {
              name = "LuaLaTeX";
              tools = [ "lualatex" ];
            }
          ];
          
          "latex-workshop.latex.clean.fileTypes" = [
            "*.aux" "*.bbl" "*.blg" "*.idx" "*.ind" "*.lof" "*.lot"
            "*.out" "*.toc" "*.acn" "*.acr" "*.alg" "*.glg" "*.glo"
            "*.gls" "*.ist" "*.fls" "*.log" "*.fdb_latexmk" "*.run.xml"
            "*.bcf" "*.nav" "*.snm" "*.vrb"
          ];
          
          "latex-workshop.latex.autoClean.run" = "onBuilt";
          "latex-workshop.latex.autoBuild.run" = "onFileChange";
          
          "latex-workshop.view.pdf.viewer" = lib.mkDefault (
            if cfg.modernWorkflow.pdfViewer == "zathura" then "external"
            else "tab"
          );
          
          "latex-workshop.view.pdf.external.viewer.command" = lib.mkIf (cfg.modernWorkflow.pdfViewer == "zathura") "zathura";
          "latex-workshop.view.pdf.external.viewer.args" = lib.mkIf (cfg.modernWorkflow.pdfViewer == "zathura") [
            "--synctex-editor-command"
            "code --goto %f:%l"
            "%PDF%"
          ];
          
            # LaTeX syntax highlighting
            "latex-workshop.latex.outDir" = "%DIR%";
            "latex-workshop.latex.recipe.default" = "LuaLaTeX + Biber";
            
            # Auto-completion settings
            "latex-workshop.intellisense.citation.backend" = "bibtex";
            "latex-workshop.intellisense.citation.label" = "bibtex key";
          };
        };
      };
      
      # Neovim configuration for LaTeX with Vimtex
      programs.neovim = lib.mkIf cfg.modernWorkflow.neovim.enable {
        enable = true;
        plugins = with pkgs.vimPlugins; [
          # LaTeX plugins
          vimtex
          nvim-lspconfig
          
          # Completion
          nvim-cmp
          cmp-nvim-lsp
          cmp-path
          cmp-buffer
          luasnip
          cmp_luasnip
          
          # UI enhancements
          lualine-nvim
          nvim-web-devicons
          telescope-nvim
          
          # Theme
          tokyonight-nvim
        ];
        
        extraLuaConfig = ''
        -- Modern TeX environment for Neovim
        vim.opt.number = true
        vim.opt.relativenumber = true
        vim.opt.expandtab = true
        vim.opt.shiftwidth = 2
        vim.opt.tabstop = 2
        vim.opt.wrap = true
        vim.opt.linebreak = true
        vim.opt.conceallevel = 2
        
        -- Theme
        require("tokyonight").setup()
        vim.cmd.colorscheme("tokyonight")
        
        -- Vimtex configuration
        vim.g.vimtex_view_method = '${cfg.modernWorkflow.pdfViewer}'
        vim.g.vimtex_compiler_method = 'latexmk'
        vim.g.vimtex_compiler_latexmk = {
          build_dir = 'build',
          callback = 1,
          continuous = 1,
          executable = 'latexmk',
          hooks = {},
          options = {
            '-verbose',
            '-file-line-error',
            '-synctex=1',
            '-interaction=nonstopmode',
            '-lualatex',  -- Use LuaLaTeX by default
          },
        }
        
        -- Vimtex quickfix settings
        vim.g.vimtex_quickfix_mode = 0
        vim.g.vimtex_quickfix_open_on_warning = 0
        
        -- SyncTeX configuration
        ${lib.optionalString (cfg.modernWorkflow.pdfViewer == "zathura") ''
        vim.g.vimtex_view_zathura_options = '--synctex-editor-command="nvim --server $NVIM_LISTEN_ADDRESS --remote-send \\\"<C-\\\\><C-n>:VimtexInverseSearch %{line} %{input}<CR>\\\""'
        ''}
        
        -- LSP Configuration
        local lspconfig = require("lspconfig")
        
        -- Setup texlab
        lspconfig.texlab.setup({
          settings = {
            texlab = {
              build = {
                executable = 'lualatex',
                args = {
                  '-pdf',
                  '-interaction=nonstopmode',
                  '-synctex=1',
                  '%f'
                },
                onSave = true,
              },
              forwardSearch = {
                executable = '${cfg.modernWorkflow.pdfViewer}',
                args = ${if cfg.modernWorkflow.pdfViewer == "zathura" then ''
                {
                  '--synctex-forward',
                  '%l:1:%f',
                  '%p'
                }
                '' else ''
                { '%p' }
                ''},
              },
              chktex = {
                onOpenAndSave = true,
                onEdit = true,
              },
            },
          },
        })
        
        -- Completion setup
        local cmp = require("cmp")
        local luasnip = require("luasnip")
        
        cmp.setup({
          snippet = {
            expand = function(args)
              luasnip.lsp_expand(args.body)
            end,
          },
          mapping = cmp.mapping.preset.insert({
            ["<C-b>"] = cmp.mapping.scroll_docs(-4),
            ["<C-f>"] = cmp.mapping.scroll_docs(4),
            ["<C-Space>"] = cmp.mapping.complete(),
            ["<C-e>"] = cmp.mapping.abort(),
            ["<CR>"] = cmp.mapping.confirm({ select = true }),
            ["<Tab>"] = cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_next_item()
              elseif luasnip.expand_or_jumpable() then
                luasnip.expand_or_jump()
              else
                fallback()
              end
            end, { "i", "s" }),
            ["<S-Tab>"] = cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_prev_item()
              elseif luasnip.jumpable(-1) then
                luasnip.jump(-1)
              else
                fallback()
              end
            end, { "i", "s" }),
          }),
          sources = cmp.config.sources({
            { name = "nvim_lsp" },
            { name = "luasnip" },
            { name = "path" },
          }, {
            { name = "buffer" },
          })
        })
        
        -- Lualine statusline
        require("lualine").setup {
          options = {
            theme = "tokyonight",
            component_separators = { left = "", right = "" },
            section_separators = { left = "", right = "" },
          },
          sections = {
            lualine_c = {
              {
                "filename",
                path = 1,  -- Show relative path
              }
            },
            lualine_x = {
              {
                function()
                  if vim.bo.filetype == "tex" then
                    return "LuaLaTeX"
                  end
                  return ""
                end,
                color = { fg = "#7aa2f7" },
              },
              "encoding",
              "fileformat",
              "filetype"
            },
          },
        }
        
        -- Key mappings for LaTeX
        vim.api.nvim_create_autocmd("FileType", {
          pattern = "tex",
          callback = function()
            local opts = { buffer = true, silent = true }
            
            -- Compilation
            vim.keymap.set("n", "<leader>ll", "<cmd>VimtexCompile<CR>", opts)
            vim.keymap.set("n", "<leader>lv", "<cmd>VimtexView<CR>", opts)
            vim.keymap.set("n", "<leader>lc", "<cmd>VimtexClean<CR>", opts)
            vim.keymap.set("n", "<leader>le", "<cmd>VimtexErrors<CR>", opts)
            
            -- Navigation
            vim.keymap.set("n", "<leader>lt", "<cmd>VimtexTocToggle<CR>", opts)
            vim.keymap.set("n", "<leader>lm", "<cmd>VimtexImaps<CR>", opts)
            
            -- Text objects (already provided by vimtex)
            -- vim.keymap.set({'x', 'o'}, 'ie', '<Plug>(vimtex-ie)', opts)
            -- vim.keymap.set({'x', 'o'}, 'ae', '<Plug>(vimtex-ae)', opts)
          end,
        })
        
        -- Telescope setup for finding files
        require("telescope").setup({
          defaults = {
            file_ignore_patterns = {
              "%.aux", "%.bbl", "%.blg", "%.fls", "%.fdb_latexmk",
              "%.log", "%.out", "%.toc", "%.synctex.gz", "%.bcf",
              "%.run.xml", "%.nav", "%.snm", "%.vrb"
            }
          }
        })
        
          -- Global key mappings
          vim.g.mapleader = " "
          vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>")
          vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<CR>")
          vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<CR>")
          vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<CR>")
        '';
      };
      
      # Pandoc workflow helper scripts and templates
      home.file = lib.mkMerge [
        (lib.mkIf cfg.modernWorkflow.pandoc.enable {
          "bin/md2tex" = {
            executable = true;
            text = ''
          #!/usr/bin/env bash
          # Modern Academic Writing: Markdown to LaTeX converter
          set -euo pipefail
          
          # Colors for output
          RED='\033[0;31m'
          GREEN='\033[0;32m'
          YELLOW='\033[1;33m'
          BLUE='\033[0;34m'
          NC='\033[0m'
          
          log_info() { echo -e "''${BLUE}[INFO]''${NC} $1"; }
          log_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
          log_warning() { echo -e "''${YELLOW}[WARNING]''${NC} $1"; }
          log_error() { echo -e "''${RED}[ERROR]''${NC} $1"; }
          
          show_help() {
            cat << EOF
          Usage: md2tex [OPTIONS] INPUT.md [OUTPUT.tex]
          
          Convert Markdown to LaTeX using Pandoc with academic writing optimizations.
          
          OPTIONS:
            -b, --bibliography FILE   Specify bibliography file (.bib)
            -t, --template TEMPLATE   Use specific LaTeX template
            -j, --japanese           Enable Japanese language support
            --lualatex              Optimize for LuaLaTeX engine
            --biblatex              Use BibLaTeX instead of natbib
            -h, --help              Show this help message
          
          EXAMPLES:
            md2tex paper.md                    # Basic conversion
            md2tex -b refs.bib -j paper.md     # With bibliography and Japanese
            md2tex --lualatex paper.md paper.tex  # LuaLaTeX optimization
          
          WORKFLOW:
            1. Write in Obsidian using Markdown
            2. Use [@key] for citations (Pandoc format)
            3. Run md2tex to convert to LaTeX
            4. Open in VS Code for final editing
            5. Compile with LuaLaTeX + Biber
          EOF
          }
          
          # Parse arguments
          BIBLIOGRAPHY=""
          TEMPLATE=""
          JAPANESE=false
          LUALATEX=false
          BIBLATEX=true
          INPUT=""
          OUTPUT=""
          
          while [[ $# -gt 0 ]]; do
            case $1 in
              -b|--bibliography)
                BIBLIOGRAPHY="$2"
                shift 2
                ;;
              -t|--template)
                TEMPLATE="$2"
                shift 2
                ;;
              -j|--japanese)
                JAPANESE=true
                shift
                ;;
              --lualatex)
                LUALATEX=true
                shift
                ;;
              --biblatex)
                BIBLATEX=true
                shift
                ;;
              -h|--help)
                show_help
                exit 0
                ;;
              -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
              *)
                if [[ -z "$INPUT" ]]; then
                  INPUT="$1"
                elif [[ -z "$OUTPUT" ]]; then
                  OUTPUT="$1"
                else
                  log_error "Too many arguments"
                  show_help
                  exit 1
                fi
                shift
                ;;
            esac
          done
          
          # Validate input
          if [[ -z "$INPUT" ]]; then
            log_error "Input file required"
            show_help
            exit 1
          fi
          
          if [[ ! -f "$INPUT" ]]; then
            log_error "Input file not found: $INPUT"
            exit 1
          fi
          
          # Set default output
          if [[ -z "$OUTPUT" ]]; then
            OUTPUT="''${INPUT%.md}.tex"
          fi
          
          log_info "Converting $INPUT to $OUTPUT"
          
          # Build pandoc command
          PANDOC_ARGS=(
            "--from=markdown"
            "--to=latex"
            "--standalone"
            "--biblatex"
            "--citeproc"
          )
          
          # Add bibliography if specified
          if [[ -n "$BIBLIOGRAPHY" ]]; then
            if [[ ! -f "$BIBLIOGRAPHY" ]]; then
              log_error "Bibliography file not found: $BIBLIOGRAPHY"
              exit 1
            fi
            PANDOC_ARGS+=("--bibliography=$BIBLIOGRAPHY")
            log_info "Using bibliography: $BIBLIOGRAPHY"
          fi
          
          # Add template if specified
          if [[ -n "$TEMPLATE" ]]; then
            PANDOC_ARGS+=("--template=$TEMPLATE")
            log_info "Using template: $TEMPLATE"
          fi
          
          # Japanese support
          if [[ "$JAPANESE" == true ]]; then
            PANDOC_ARGS+=("--variable=lang:ja")
            log_info "Enabling Japanese language support"
          fi
          
          # Run conversion
          if pandoc "''${PANDOC_ARGS[@]}" "$INPUT" -o "$OUTPUT"; then
            log_success "Conversion completed: $OUTPUT"
            
            # LuaLaTeX optimizations
            if [[ "$LUALATEX" == true && "$JAPANESE" == true ]]; then
              log_info "Applying LuaLaTeX Japanese font optimizations..."
              
              # Add Japanese font configuration
              sed -i '1i\\usepackage{luatexja-fontspec}' "$OUTPUT"
              sed -i '2i\\setmainfont{${cfg.fonts.japanese.serif}}' "$OUTPUT"
              sed -i '3i\\setsansfont{${cfg.fonts.japanese.sans}}' "$OUTPUT"
              
              log_success "Japanese font configuration added"
            fi
            
            echo ""
            log_info "Next steps:"
            echo "  1. Open $OUTPUT in VS Code"
            echo "  2. Edit documentclass and packages as needed"
            echo "  3. Use Ctrl+Alt+B to build with LaTeX Workshop"
            echo ""
          else
            log_error "Conversion failed"
            exit 1
          fi
        '';
      };
      
      "bin/tex-health" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          # TeX Environment Health Check
          set -euo pipefail
          
          echo "📝 Modern TeX Environment Health Check"
          echo "======================================"
          echo ""
          
          # Core TeX tools
          echo "🔧 Core TeX Tools:"
          tools=(
            "lualatex:LuaLaTeX engine"
            "biber:Modern bibliography processor"
            "texlab:TeX language server"
            "pandoc:Document converter"
          )
          
          for tool_desc in "''${tools[@]}"; do
            tool="''${tool_desc%%:*}"
            desc="''${tool_desc##*:}"
            
            if command -v "$tool" &> /dev/null; then
              echo "✅ $tool: $desc"
            else
              echo "❌ $tool: $desc (not found)"
            fi
          done
          
          echo ""
          echo "🖥️  Editors:"
          
          # VS Code
          if command -v code &> /dev/null; then
            echo "✅ VS Code: Available"
            if code --list-extensions | grep -q "james-yu.latex-workshop"; then
              echo "  ✅ LaTeX Workshop extension installed"
            else
              echo "  ❌ LaTeX Workshop extension missing"
            fi
          else
            echo "❌ VS Code: Not available"
          fi
          
          # Neovim
          if command -v nvim &> /dev/null; then
            echo "✅ Neovim: $(nvim --version | head -n1)"
          else
            echo "❌ Neovim: Not available"
          fi
          
          echo ""
          echo "📄 PDF Viewers:"
          
          viewers=("zathura" "skim" "evince")
          for viewer in "''${viewers[@]}"; do
            if command -v "$viewer" &> /dev/null; then
              echo "✅ $viewer: Available"
            else
              echo "⚪ $viewer: Not available"
            fi
          done
          
          echo ""
          echo "🌏 Japanese Support:"
          
          # Font check (basic)
          if fc-list | grep -i "noto.*cjk" > /dev/null 2>&1; then
            echo "✅ Noto CJK fonts: Available"
          else
            echo "❌ Noto CJK fonts: Missing"
          fi
          
          echo ""
          echo "📚 Modern Workflow:"
          
          # Check for helper scripts
          if [[ -x "$HOME/bin/md2tex" ]]; then
            echo "✅ md2tex converter: Available"
          else
            echo "❌ md2tex converter: Missing"
          fi
          
          # Check Zotero integration (basic)
          if [[ -d "$HOME/.zotero" ]] || [[ -d "$HOME/Zotero" ]]; then
            echo "✅ Zotero: Detected"
          else
            echo "⚪ Zotero: Not detected"
          fi
          
          # Check Obsidian integration (basic)
          if [[ -d "$HOME/.obsidian" ]] || ls "$HOME"/*.obsidian > /dev/null 2>&1; then
            echo "✅ Obsidian: Detected"
          else
            echo "⚪ Obsidian: Not detected"
          fi
          
          echo ""
          echo "🎯 Recommendations:"
          echo "  • Use LuaLaTeX for modern Unicode support"
          echo "  • Manage bibliography with Zotero + Better BibTeX"
          echo "  • Write drafts in Obsidian with Markdown"
          echo "  • Convert with md2tex and edit in VS Code"
          echo "  • Use SyncTeX for PDF⇔source navigation"
          echo ""
        '';
          };
        })
        (lib.mkIf cfg.modernWorkflow.enable {
          ".tex-templates/modern-academic.tex" = {
            text = ''
              \documentclass[${if cfg.fonts.japanese.enable then "lualatex, ja=standard, " else ""}a4paper, 12pt]{article}
              
              ${lib.optionalString cfg.fonts.japanese.enable ''
              % Japanese font configuration for LuaLaTeX
              \usepackage{luatexja-fontspec}
              \setmainfont{${cfg.fonts.japanese.serif}}
              \setsansfont{${cfg.fonts.japanese.sans}}
              ''}
              
              % Modern bibliography with BibLaTeX
              \usepackage[backend=biber, style=authoryear-comp, sorting=nyt]{biblatex}
              \addbibresource{references.bib}
              
              % Essential packages
              \usepackage[utf8]{inputenc}
              \usepackage[T1]{fontenc}
              \usepackage{amsmath, amsfonts, amssymb}
              \usepackage{graphicx}
              \usepackage{hyperref}
              \usepackage{geometry}
              \usepackage{booktabs}
              \usepackage{microtype}
              
              % Geometry
              \geometry{margin=2.5cm}
              
              % Hyperref setup
              \hypersetup{
                  colorlinks=true,
                  linkcolor=blue,
                  citecolor=red,
                  urlcolor=blue,
                  pdfauthor={Your Name},
                  pdftitle={Document Title}
              }
              
              \title{Your Document Title}
              \author{Your Name}
              \date{\today}
              
              \begin{document}
              
              \maketitle
              
              \begin{abstract}
              Your abstract here.
              \end{abstract}
              
              \section{Introduction}
              
              This is a modern LaTeX template optimized for academic writing.
              
              You can cite works like this: \cite{key1}.
              
              \section{Methodology}
              
              Mathematical expressions: $E = mc^2$
              
              \begin{equation}
              \int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
              \end{equation}
              
              \section{Results}
              
              \section{Discussion}
              
              \section{Conclusion}
              
              \printbibliography
              
              \end{document}
            '';
          };
        })
      ];
    };
    
    # Create TeX directories on activation
    system.activationScripts.texSetup = lib.mkIf pkgs.stdenv.isDarwin ''
      echo "Setting up modern TeX environment..."
      
      # Create user TeX directories
      mkdir -p "$HOME/.texmf/tex/latex"
      mkdir -p "$HOME/.texlive/texmf-var"
      mkdir -p "$HOME/.texlive/texmf-config"
      
      # Set proper permissions
      chmod 755 "$HOME/.texmf" "$HOME/.texlive" || true
      
      echo "Modern TeX environment setup complete"
    '';
  };
}