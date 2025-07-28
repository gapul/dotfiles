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
      
    in texlivePackages ++ coreTexTools ++ lspTools ++ editorSupport ++ cfg.additionalPackages;
    
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
    
    # Create TeX directories on activation
    system.activationScripts.texSetup = lib.mkIf pkgs.stdenv.isDarwin ''
      echo "Setting up TeX environment..."
      
      # Create user TeX directories
      mkdir -p "$HOME/.texmf/tex/latex"
      mkdir -p "$HOME/.texlive/texmf-var"
      mkdir -p "$HOME/.texlive/texmf-config"
      
      # Set proper permissions
      chmod 755 "$HOME/.texmf" "$HOME/.texlive" || true
      
      echo "TeX environment setup complete"
    '';
  };
}