{ pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;

  # Determinate Nix が daemon/nix.conf を管理しているので nix-darwin は触らない
  nix.enable = false;

  system.stateVersion = 5;
  system.primaryUser = "yuki";

  users.users.yuki = {
    name = "yuki";
    home = "/Users/yuki";
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # cask に該当 Nerd Font が無いものだけ Nix で確保
  # (font-hackgen-nerd は HackGen で Hack とは別物)
  # (font-jetbrains-mono-nerd-font は cask 側で管理)
  fonts.packages = with pkgs; [
    nerd-fonts.hack
    nerd-fonts.fira-code
  ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
      upgrade = false;
    };

    taps = [
      "deskflow/tap"
      "felixkratz/formulae"
      "finnvoor/tools"
      "gapul/openutau"
      "gapul/zrythm"
      "gerlero/openfoam"
      "homebrew-zathura/zathura"
      "imshuhao/kdeconnect"
      "infisical/get-cli"
      "jakehilborn/jakehilborn"
      "jpmhouston/bananameterlabs"
      "nikitabobko/tap"
      "pear-devs/pear"
      "pomdtr/tap"
      "riscv-software-src/riscv"
      "supabase/tap"
      "theboredteam/boring-notch"
    ];

    # brew leaves から (starship/fzf/atuin は home-manager 管理に移行のため除外)
    brews = [
      "aerc" "aria2" "bitwarden-cli" "blueutil" "boringtun" "bottom"
      "calcurse" "chafa" "cmake" "cmatrix" "cocoapods" "curl" "diskonaut"
      "docker" "docker-compose" "dust" "duti" "fd" "fish" "fontforge"
      "fonttools" "gauche" "gdu" "gemini-cli" "gh" "ghq" "git" "glow"
      "gopeed" "gstreamer" "guile" "homebrew-zathura/zathura/zathura-pdf-mupdf"
      "imagemagick" "isync" "jq" "just" "lazygit" "lazyjj" "libsixel" "lynx"
      "mas" "media-control" "meson" "mpv" "ncdu" "neovim" "nextdns" "ollama"
      "opam" "opencode" "pandoc" "pipx" "pnpm" "podman" "poppler" "radare2"
      "rbw" "rclone" "rust" "sc-im" "scrcpy" "sphinx-doc" "syft"
      "tailscale" "tcpdump" "terminal-notifier" "tmux" "tor" "tree"
      "tree-sitter-cli" "typst" "uv" "visidata" "w3m" "wgcf" "wifitui"
      "wireguard-tools" "xcodegen" "yazi" "zellij"
    ];

    # GUI applications (100 個)
    casks = [
      "activitywatch" "adobe-creative-cloud" "aerospace" "affinity" "alt-tab"
      "android-studio" "anki" "audacity" "bambu-studio" "beeper" "bitwig-studio"
      "blender" "blockblock" "boring-notch" "brave-browser" "calibre" "cardinal"
      "claude-code" "corelocationcli" "cyberduck" "cycling74-max" "darktable"
      "deskflow" "deskreen" "ente-auth" "epic-games" "espanso" "figma-agent"
      "flutter" "font-hackgen-nerd" "font-jetbrains-mono-nerd-font" "font-sf-mono"
      "fontforge-app" "fontgoggles" "freecad" "ghostty" "gimp" "godot"
      "google-chrome" "goxel" "gstreamer-runtime" "gyroflow" "hammerspoon"
      "heroic" "iina" "imhex" "inkscape" "karabiner-elements" "kdeconnect"
      "keepassxc" "keyguard" "kicad" "knockknock" "krita" "librecad"
      "libreoffice" "localsend" "lulu" "maccy" "macskk" "material-maker"
      "mechvibes" "milkytracker" "mixxx" "monitorcontrol" "mos" "musescore"
      "mythic" "native-access" "obs" "obsidian" "openfoam" "openutau"
      "orcaslicer" "pd" "pear-desktop" "pika" "playcover-community"
      "prismlauncher" "qlmarkdown" "rawtherapee" "reaper" "retroarch-metal"
      "rustdesk" "scribus" "shortcat" "simplex" "steam" "syncthing-app"
      "tailscale-app" "tor-browser" "touchdesigner" "trex" "unity-hub"
      "upscayl" "utm" "vcv-rack" "vlc" "voicevox" "wireshark-app" "zed"
      "zen" "zotero"
    ];

    masApps = {
      "Apple Configurator 2" = 1037126344;
      "DaVinci Resolve" = 571213070;
      "Plash" = 1494023538;
      "Xcode" = 497799835;
    };
  };
}
