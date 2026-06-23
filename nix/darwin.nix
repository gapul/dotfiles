{ pkgs, user, ... }: {
  nixpkgs.config.allowUnfree = true;

  # Determinate Nix が daemon/nix.conf を管理しているので nix-darwin は触らない
  nix.enable = false;

  system.stateVersion = 5;
  system.primaryUser = user.username;

  users.users.${user.username} = {
    name = user.username;
    home = "/Users/${user.username}";
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # macOS 設定 (実機の defaults read で確認した値のみ宣言)
  system.defaults = {
    dock = {
      autohide = true;
      show-recents = false;
      static-only = true;
      tilesize = 52;
      launchanim = false;
      minimize-to-application = true;
    };
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = false;
      FXPreferredViewStyle = "Nlsv";
      FXDefaultSearchScope = "SCcf";
      CreateDesktop = false;
    };
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      AppleShowScrollBars = "WhenScrolling";
      # Note: Caps→Esc は Karabiner で処理しているため宣言しない
      # Note: AppleInterfaceStyle (Dark mode) は明示設定されてないので除外
    };
    trackpad = {
      Clicking = false;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };
  };

  # cask に該当 Nerd Font が無いものだけ Nix で確保
  # (font-hackgen-nerd は HackGen で Hack とは別物)
  # (font-jetbrains-mono-nerd-font は cask 側で管理)
  fonts.packages = with pkgs; [
    nerd-fonts.hack
    nerd-fonts.fira-code
    # sketchybar アプリアイコンフォント。Ghostty/Zen 対応の v2.0.62 を vendor。
    # plugins/icon_map.sh と版を厳密一致させるため nixpkgs 版でなく同梱 ttf を使う。
    (stdenvNoCC.mkDerivation {
      pname = "sketchybar-app-font";
      version = "2.0.62";
      src = ../configs/fonts/sketchybar-app-font.ttf;
      dontUnpack = true;
      installPhase = ''
        install -Dm444 $src $out/share/fonts/truetype/sketchybar-app-font.ttf
      '';
    })
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

      # ─── 個人 fork (gapul) — fork した人は不要なら削除 ───
      "gapul/openutau"
      "gapul/zrythm"
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
      "swi-prolog"     # Prolog (関数・論理型プログラミング実験 第10-12回)
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
      "age"            # SOPS encryption backend
      "sops"           # secrets management
      "gitleaks"       # pre-commit hook で機密 leak 検査
      "pre-commit"     # hook framework

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
      "girara"           # zathura の UI ライブラリ。zathura が dlopen するので必須

      # ─── macOS specific CLI ───
      "mas"              # App Store
      "blueutil"         # Bluetooth
      "media-control"    # media keys
      "terminal-notifier"
      "duti"             # file associations
      "jakehilborn/jakehilborn/displayplacer"  # sketchybar マルチディスプレイ

      # ─── Status bar / Window decoration (felixkratz tap) ───
      "felixkratz/formulae/sketchybar"
      "felixkratz/formulae/borders"     # aerospace から exec-and-forget で起動

      # ─── Transcription / other 3rd-party tap brews ───
      "finnvoor/tools/yap"             # 日本語 transcription
      "infisical/get-cli/infisical"    # secret CLI
      "pomdtr/tap/sunbeam"             # launcher
      "supabase/tap/supabase"          # Supabase CLI

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
