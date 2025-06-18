{ pkgs }:

# Media processing and creative tools
with pkgs; [
  # Image processing
  imagemagick
  graphicsmagick
  
  # Video/Audio processing
  ffmpeg-full
  
  # Image viewers and basic editors
  # feh          # X11-based, may not work on macOS
  # sxiv         # X11-based, may not work on macOS
  
  # Audio tools
  # audacity     # GUI app, better managed via Homebrew cask
  sox            # CLI audio processing
  
  # Video tools
  # vlc          # GUI app, better managed via Homebrew cask
  # mpv          # Lightweight video player (CLI-based)
  
  # Graphics tools (CLI)
  # gimp         # GUI app, better managed via Homebrew cask
  # inkscape     # GUI app, better managed via Homebrew cask
  
  # Photo management
  # darktable    # GUI app, better managed via Homebrew cask
  exiftool       # EXIF data manipulation
  
  # 3D graphics (CLI tools)
  # blender      # GUI app, better managed via Homebrew cask
  
  # Document processing
  pandoc
  # texlive      # Large package, consider keeping in Homebrew
  
  # Font tools
  fontconfig
  # fontforge    # GUI app, better managed via Homebrew cask
  
  # Color management
  # colord       # May not be relevant for macOS
  
  # Screen capture (CLI)
  # scrot        # X11-based, use macOS built-in screencapture
  
  # Audio format conversion
  # lame         # MP3 encoder
  # flac         # FLAC tools
  
  # Video format conversion
  # x264         # H.264 encoder (included in ffmpeg)
  # x265         # H.265 encoder (included in ffmpeg)
  
  # Streaming tools
  # obs-studio   # GUI app, better managed via Homebrew cask
  
  # PDF tools
  poppler        # PDF utilities
  # pdftk        # PDF toolkit
  
  # E-book tools
  # calibre      # GUI app, better managed via Homebrew cask
  
  # Music tools
  # spotify-tui  # Terminal Spotify client
  # ncmpcpp      # Music player client
  
  # YouTube tools
  yt-dlp         # YouTube downloader
  
  # Image optimization
  oxipng         # PNG optimizer
  jpegoptim      # JPEG optimizer
  
  # Subtitle tools
  # subliminal   # Subtitle downloader
  
  # Media information
  mediainfo      # Media file information
  
  # File format conversion
  # pandoc       # Already included above
  
  # Archive extraction for media
  # unrar        # Proprietary, may need alternative
  
  # Thumbnail generation
  # tumbler      # Linux-specific
]

# Note: Many GUI applications are better managed through Homebrew casks
# during the transition period. Consider moving them to nix later if
# they work well and are actively maintained in nixpkgs.