# macOS File Associations Management with duti
# ファイル関連付けを宣言的に管理

{ config, lib, pkgs, ... }:

{
  # Home Manager configuration for file associations
  home-manager.users.yuki = { ... }: {
    
    # File associations using duti
    home.file.".config/duti/config".text = ''
      # Development files - Visual Studio Code
      com.microsoft.VSCode .md all
      com.microsoft.VSCode .ts all
      com.microsoft.VSCode .js all
      com.microsoft.VSCode .json all
      com.microsoft.VSCode .lua all
      com.microsoft.VSCode .rs all
      com.microsoft.VSCode .go all
      com.microsoft.VSCode .py all
      com.microsoft.VSCode .sh all
      com.microsoft.VSCode .nix all
      com.microsoft.VSCode .txt all
      com.microsoft.VSCode .yml all
      com.microsoft.VSCode .yaml all
      com.microsoft.VSCode .toml all
      com.microsoft.VSCode .html all
      com.microsoft.VSCode .css all
      com.microsoft.VSCode .scss all
      com.microsoft.VSCode .jsx all
      com.microsoft.VSCode .tsx all
      com.microsoft.VSCode .vue all
      com.microsoft.VSCode .svelte all
      
      # Media files - VLC
      org.videolan.vlc .mp4 all
      org.videolan.vlc .mkv all
      org.videolan.vlc .mov all
      org.videolan.vlc .avi all
      org.videolan.vlc .webm all
      org.videolan.vlc .flv all
      org.videolan.vlc .m4v all
      org.videolan.vlc .mp3 all
      org.videolan.vlc .flac all
      org.videolan.vlc .wav all
      org.videolan.vlc .ogg all
      org.videolan.vlc .m4a all
      org.videolan.vlc .aac all
      
      # Image files - Preview
      com.apple.Preview .png all
      com.apple.Preview .jpg all
      com.apple.Preview .jpeg all
      com.apple.Preview .gif all
      com.apple.Preview .bmp all
      com.apple.Preview .tiff all
      com.apple.Preview .webp all
      com.apple.Preview .heic all
      
      # PDF files - Zen Browser
      app.zen-browser.zen .pdf all
      
      # Archive files - Keka or built-in Archive Utility
      com.apple.archiveutility .zip all
      com.apple.archiveutility .tar all
      com.apple.archiveutility .gz all
      com.apple.archiveutility .bz2 all
      com.apple.archiveutility .xz all
      
      # Web browsers - Zen Browser (default)
      app.zen-browser.zen http
      app.zen-browser.zen https
      app.zen-browser.zen .html
      
      # Alternative: Google Chrome Dev for development
      # com.google.Chrome.dev .html all
      
      # Office documents - LibreOffice
      org.libreoffice.script .doc all
      org.libreoffice.script .docx all
      org.libreoffice.script .xls all
      org.libreoffice.script .xlsx all
      org.libreoffice.script .ppt all
      org.libreoffice.script .pptx all
      org.libreoffice.script .odt all
      org.libreoffice.script .ods all
      org.libreoffice.script .odp all
    '';
    
    # Shell script to apply file associations
    home.file."bin/apply-file-associations" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "Applying file associations with duti..."
        if [ -f "$HOME/.config/duti/config" ] && command -v duti >/dev/null 2>&1; then
          duti "$HOME/.config/duti/config"
          echo "File associations applied successfully"
        else
          echo "duti not found or config file missing, skipping file associations"
        fi
      '';
    };
  };
}