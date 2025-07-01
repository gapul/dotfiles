{
  description = "Slidev presentation development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { 
          inherit system; 
          config.allowUnfree = true; 
        };
        
        # Slidev presentation toolkit
        slidev-env = pkgs.buildEnv {
          name = "slidev-environment";
          paths = with pkgs; [
            nodejs_22
            nodePackages.npm
            nodePackages.pnpm
            nodePackages.yarn
            git
            gh
            
            # Image processing tools
            imagemagick
            ffmpeg
            
            # PDF tools
            poppler_utils
            
            # Browser automation (macOS用)
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            chromium
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # macOSではchromeやsafariを使用
            
            # Editor support
            neovim
            vscode
          ];
        };
        
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [ slidev-env ];
          
          shellHook = ''
            echo "🎨 Slidev Development Environment"
            echo "================================"
            echo ""
            echo "Available commands:"
            echo "  npm create slidev@latest <name>  - Create new presentation"
            echo "  npm run dev                      - Start development server"
            echo "  npm run build                    - Build for production"
            echo "  npm run export                   - Export to PDF/PNG"
            echo ""
            echo "Tools available:"
            echo "  Node.js: $(node --version)"
            echo "  npm: $(npm --version)"
            echo "  pnpm: $(pnpm --version)"
            echo ""
            
            # Create .envrc for automatic activation
            if [[ ! -f .envrc ]]; then
              echo "use flake" > .envrc
              echo "📝 Created .envrc for automatic environment activation"
              echo "   Run 'direnv allow' to enable auto-activation"
            fi
            
            # Create package.json if it doesn't exist
            if [[ ! -f package.json ]]; then
              echo "📦 Initializing npm project..."
              npm init -y > /dev/null 2>&1
              
              # Add Slidev as dependency
              echo "🔧 Installing Slidev..."
              npm install @slidev/cli @slidev/theme-default
              
              # Add useful scripts
              npx json -I -f package.json -e '
                this.scripts = {
                  "dev": "slidev",
                  "build": "slidev build",
                  "export": "slidev export",
                  "format": "slidev format",
                  "new": "npm create slidev@latest"
                };
                this.type = "module";
              ' > /dev/null 2>&1 || true
              
              echo "✅ Slidev environment ready!"
            fi
          '';
          
          # Environment variables
          BROWSER = if pkgs.stdenv.isDarwin then "open" else "chromium";
          SLIDEV_EXPORT_FORMAT = "pdf";
          NODE_ENV = "development";
        };
        
        # Convenience apps
        apps = {
          # Quick presentation creator
          new = {
            type = "app";
            program = toString (pkgs.writeShellScript "slidev-new" ''
              if [[ $# -eq 0 ]]; then
                echo "Usage: nix run .#new -- <presentation-name>"
                echo "Example: nix run .#new -- my-presentation"
                exit 1
              fi
              
              PRESENTATION_NAME="$1"
              echo "🎨 Creating new Slidev presentation: $PRESENTATION_NAME"
              
              mkdir -p "$PRESENTATION_NAME"
              cd "$PRESENTATION_NAME"
              
              # Initialize with flake environment
              echo "use flake .." > .envrc
              
              # Create basic slides.md
              cat > slides.md << EOF
---
theme: default
background: https://cover.sli.dev
title: $PRESENTATION_NAME
info: |
  ## $PRESENTATION_NAME
  
  Presentation created with Slidev
  
  Learn more at [Sli.dev](https://sli.dev)
class: text-center
highlighter: shiki
lineNumbers: false
drawings:
  enabled: true
  persist: false
transition: slide-left
css: unocss
---

# $PRESENTATION_NAME

Welcome to your new presentation

---

# Overview

- 📝 **Text-based** - focus on the content with Markdown
- 🎨 **Themable** - theme can be shared and used with npm packages
- 🧑‍💻 **Developer Friendly** - code highlighting, live coding with autocompletion
- 🤹 **Interactive** - embedding Vue components to enhance your expressions
- 🎥 **Recording** - built-in recording and camera view
- 📤 **Portable** - export into PDF, PNGs, or even a hostable SPA
- 🛠 **Hackable** - anything possible on a webpage

<br>
<br>

Read more about [Why Slidev?](https://sli.dev/guide/why)

---

# Navigation

Hover on the bottom-left corner to see the navigation's controls panel

### Keyboard Shortcuts

|     |     |
| --- | --- |
| <kbd>right</kbd> / <kbd>space</kbd> | next animation or slide |
| <kbd>left</kbd>  / <kbd>shift</kbd><kbd>space</kbd> | previous animation or slide |
| <kbd>up</kbd> | previous slide |
| <kbd>down</kbd> | next slide |

---

# Thank You!

Questions?
EOF
              
              echo "✅ Created presentation: $PRESENTATION_NAME"
              echo "📁 Location: $(pwd)"
              echo ""
              echo "Next steps:"
              echo "  cd $PRESENTATION_NAME"
              echo "  direnv allow"
              echo "  npm run dev"
            '');
          };
          
          # Development server launcher
          dev = {
            type = "app";
            program = toString (pkgs.writeShellScript "slidev-dev" ''
              if [[ ! -f slides.md ]]; then
                echo "❌ No slides.md found in current directory"
                echo "💡 Run 'nix run .#new -- <name>' to create a new presentation"
                exit 1
              fi
              
              echo "🚀 Starting Slidev development server..."
              ${pkgs.nodejs_22}/bin/npx slidev
            '');
          };
        };
        
        # Package outputs
        packages.default = slidev-env;
      }
    );
}