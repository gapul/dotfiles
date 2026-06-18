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
      cleanup = "uninstall";  # 宣言外の brew は自動uninstall(zap は data 消すので avoid)
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

    # brew leaves
    # (starship / fzf / atuin / pipx は home-manager / uv 管理に移行のため除外)
    brews = [
      # ─── Git / VCS ───
      "git"
      "gh"
      "ghq"
      "lazygit"
      "lazyjj"

      # ─── Editor / Terminal multiplexer ───
      "neovim"
      "tmux"
      "zellij"

      # ─── Languages / Package managers ───
      "rust"
      "uv"
      "pnpm"
      "opam"
      "gauche"
      "guile"
      "cocoapods"
      "xcodegen"

      # ─── Build tools ───
      "cmake"
      "meson"
      "tree-sitter-cli"
      "sphinx-doc"

      # ─── Containers ───
      "docker"
      "docker-compose"
      "podman"

      # ─── Modern CLI replacements ───
      "fd"
      "bottom"
      "dust"
      "gdu"
      "ncdu"
      "tree"
      "yazi"
      "jq"
      "just"
      "curl"

      # ─── TUI utilities ───
      "aerc"          # mail
      "calcurse"      # calendar
      "sc-im"         # spreadsheet
      "visidata"      # data viewer
      "cmatrix"       # screensaver
      "lynx"          # text browser
      "w3m"           # text browser
      "glow"          # markdown viewer
      "chafa"         # image-to-terminal
      "wifitui"       # wifi
      "diskonaut"     # disk usage

      # ─── Network / Download / VPN ───
      "aria2"
      "gopeed"
      "rclone"
      "tailscale"
      "tor"
      "wireguard-tools"
      "wgcf"           # Cloudflare WARP
      "boringtun"      # WireGuard userspace
      "cloudflared"    # Cloudflare tunnel
      "nextdns"
      "scrcpy"         # Android mirror
      "tcpdump"

      # ─── AI / LLM ───
      "ollama"
      "opencode"
      "gemini-cli"

      # ─── Mail ───
      "isync"

      # ─── Security / Auth ───
      "bitwarden-cli"
      "rbw"
      "syft"           # SBOM
      "radare2"        # reverse engineering

      # ─── Documents / Fonts / Media ───
      "pandoc"
      "typst"
      "poppler"
      "imagemagick"
      "gstreamer"
      "libsixel"
      "fontforge"
      "fonttools"
      "mpv"
      "homebrew-zathura/zathura/zathura-pdf-mupdf"

      # ─── macOS specific CLI ───
      "mas"              # App Store
      "blueutil"         # Bluetooth
      "media-control"    # media keys
      "terminal-notifier"
      "duti"             # file associations

      # ─── Other shells ───
      "fish"
    ];

    # GUI applications (~100個)
    casks = [
      # ─── Browsers ───
      "brave-browser"
      "google-chrome"
      "tor-browser"
      "zen"
      "pear-desktop"

      # ─── Communication & Sync ───
      "beeper"
      "kdeconnect"
      "localsend"
      "simplex"
      "syncthing-app"

      # ─── Window / Keyboard / Input ───
      "aerospace"
      "alt-tab"
      "boring-notch"
      "karabiner-elements"
      "macskk"
      "shortcat"

      # ─── macOS utilities ───
      "hammerspoon"
      "espanso"
      "maccy"
      "monitorcontrol"
      "mos"
      "mechvibes"
      "qlmarkdown"
      "corelocationcli"

      # ─── Privacy / Security ───
      "blockblock"
      "knockknock"
      "lulu"
      "ente-auth"
      "keepassxc"
      "keyguard"

      # ─── Network / Remote ───
      "tailscale-app"
      "wireshark-app"
      "rustdesk"
      "cyberduck"

      # ─── Dev IDEs / Editors / SDK ───
      "claude-code"
      "ghostty"
      "zed"
      "android-studio"
      "flutter"
      "unity-hub"
      "figma-agent"
      "imhex"
      "trex"
      "deskflow"
      "deskreen"

      # ─── Creative — Design / 2D ───
      "affinity"
      "gimp"
      "krita"
      "inkscape"
      "scribus"
      "darktable"
      "rawtherapee"
      "upscayl"
      "fontforge-app"
      "fontgoggles"
      "pika"
      "adobe-creative-cloud"

      # ─── Creative — Audio / Music ───
      "audacity"
      "bitwig-studio"
      "cardinal"
      "cycling74-max"
      "mixxx"
      "musescore"
      "milkytracker"
      "native-access"
      "openutau"
      "pd"
      "reaper"
      "vcv-rack"
      "voicevox"

      # ─── Creative — Video / Animation / Stream ───
      "iina"
      "vlc"
      "obs"
      "gyroflow"
      "touchdesigner"

      # ─── 3D / CAD ───
      "blender"
      "freecad"
      "kicad"
      "librecad"
      "godot"
      "goxel"
      "material-maker"
      "openfoam"

      # ─── 3D Printing ───
      "bambu-studio"
      "orcaslicer"

      # ─── Games / Emulation ───
      "epic-games"
      "heroic"
      "mythic"
      "prismlauncher"
      "retroarch-metal"
      "steam"
      "playcover-community"

      # ─── Productivity / Notes / Reading ───
      "anki"
      "calibre"
      "obsidian"
      "libreoffice"
      "zotero"

      # ─── VM ───
      "utm"

      # ─── Fonts ───
      "font-hackgen-nerd"
      "font-jetbrains-mono-nerd-font"
      "font-sf-mono"

      # ─── Tracking / Misc ───
      "activitywatch"
      "gstreamer-runtime"
    ];

    masApps = {
      "Apple Configurator 2" = 1037126344;
      "DaVinci Resolve" = 571213070;
      "Plash" = 1494023538;
      "Xcode" = 497799835;
    };
  };
}
