{ pkgs, user, ... }: {
  nixpkgs.config.allowUnfree = true;

  # Determinate Nix が daemon/nix.conf を管理しているので nix-darwin は触らない
  nix.enable = false;

  # Determinate の nix.conf は `!include nix.custom.conf` するので、そこへ
  # use-xdg-base-directories を冪等に書き込む。これで nix-env / nix-instantiate
  # (home-manager / nix-darwin が profile 操作で内部使用) が ~/.nix-defexpr /
  # ~/.nix-channels を $HOME に再生成せず、~/.local/state/nix/ 配下へ寄せる。
  # nix-darwin は任意名の system.activationScripts.<name> を実行しない。root で activation
  # 末尾に走る postActivation に集約する。
  system.activationScripts.postActivation.text = ''
    # use-xdg-base-directories を nix.custom.conf へ冪等追記 (nix-env が ~/.nix-defexpr /
    # ~/.nix-channels を $HOME に再生成せず ~/.local/state/nix/ 配下へ寄せる)。
    conf=/etc/nix/nix.custom.conf
    if [ -f "$conf" ] && ! /usr/bin/grep -q '^use-xdg-base-directories' "$conf"; then
      printf '\n# XDG Base Directory 準拠 (~/.nix-defexpr 等を ~/.local/state/nix へ)\nuse-xdg-base-directories = true\n' >> "$conf"
    fi
    # Application Firewall: 有効化 + ステルスモード (ping/ポートスキャンに無応答)。
    # alf defaults は最新 macOS で効きづらいので公式 socketfilterfw を冪等に叩く。
    fw=/usr/libexec/ApplicationFirewall/socketfilterfw
    "$fw" --setglobalstate on >/dev/null 2>&1 || true
    "$fw" --setstealthmode on >/dev/null 2>&1 || true
    # 自動セキュリティ更新 (system レベル defaults。nix-darwin に型付きオプションが無いので
    # root の postActivation で直接書く)。放置でも XProtect/MRT・セキュリティ応答が最新。
    su=/Library/Preferences/com.apple.SoftwareUpdate
    /usr/bin/defaults write "$su" AutomaticCheckEnabled -bool true   >/dev/null 2>&1 || true
    /usr/bin/defaults write "$su" AutomaticDownload     -bool true   >/dev/null 2>&1 || true
    /usr/bin/defaults write "$su" CriticalUpdateInstall -bool true   >/dev/null 2>&1 || true  # セキュリティ応答/XProtect
    /usr/bin/defaults write "$su" ConfigDataInstall     -bool true   >/dev/null 2>&1 || true  # XProtect/MRT 定義
    /usr/bin/defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true >/dev/null 2>&1 || true
  '';

  system.stateVersion = 5;
  system.primaryUser = user.username;

  # sudo を Touch ID で認証 (sudo_local は macOS 更新でも残る公式の仕組み)
  security.pam.services.sudo_local.touchIdAuth = true;

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
      NSDocumentSaveNewDocumentsToCloud = false; # 新規書類を既定で iCloud に上げない
      # Note: Caps→Esc は Karabiner で処理しているため宣言しない
      # Note: AppleInterfaceStyle (Dark mode) は明示設定されてないので除外
    };
    trackpad = {
      Clicking = false;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };
    # スリープ/スクリーンセーバ後すぐにパスワード要求 (離席時の覗き見対策。従来300秒)
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };
    # (自動セキュリティ更新は system レベルのため postActivation で defaults write)
    # ログイン画面ハードニング
    loginwindow = {
      GuestEnabled = false; # ゲストアカウント無効
      SHOWFULLNAME = true; # ユーザー一覧を出さず 名前+PW 入力 (アカウント列挙対策)
      DisableConsoleAccess = true; # ">console" コンソールログイン禁止
    };
    # ブラウザのテレメトリ無効化 (enterprise policy を defaults 経由で宣言)
    CustomUserPreferences = {
      # Apple の個人化広告 (ターゲティング) を無効化
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
      # ネットワーク共有 / USB に .DS_Store を書かない (ローカルは Finder 仕様で抑止不可)
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.google.Chrome" = {
        MetricsReportingEnabled = false;
      };
      "com.brave.Browser" = {
        MetricsReportingEnabled = false;
        BraveStatsPingEnabled = false;
        BraveP3AEnabled = false;
      };
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
      src = ../../configs/fonts/sketchybar-app-font.ttf;
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
      cleanup = "uninstall"; # 宣言外の brew は自動uninstall(zap は data 消すので avoid)
      upgrade = false;
    };

    taps = [
      "deskflow/tap"
      "felixkratz/formulae"
      "finnvoor/tools"
      "gerlero/openfoam"
      "homebrew-zathura/zathura"
      "gapul/kdeconnect" # imshuhao/kdeconnect の fork。depends_on macos deprecated を修正済
      "jakehilborn/jakehilborn"
      "jpmhouston/bananameterlabs"
      "nikitabobko/tap"
      "pear-devs/pear"
      "riscv-software-src/riscv"
      "theboredteam/boring-notch"

      # ─── 個人 fork (gapul) — fork した人は不要なら削除 ───
      "gapul/openutau"
      "gapul/zrythm"
    ];

    # brew leaves
    # (starship / fzf / atuin / pipx は home-manager / uv 管理に移行のため除外)
    brews = [
      # ─── Languages / Package managers ───
      # deno: nvim skkeleton(denops) の runtime + yt-dlp の JS チャレンジ解読に使用。
      # 現状は mpv/yt-dlp の依存だが、それらを消すと孤立して skkeleton が壊れるため明示宣言。
      "deno"
      "swi-prolog" # Prolog (関数・論理型プログラミング実験 第10-12回)

      # ─── wine 補助 ───
      "winetricks" # wine prefix への DLL/コンポーネント導入ヘルパ

      # ─── TUI utilities ───
      "aerc" # mail (要・残置判断)
      "wifitui" # wifi (nixpkgs は Linux 専用のため brew 維持)

      # ─── Network / Download / VPN ───
      "tailscale"
      "tor"
      "wireguard-tools" # wg-quick + wireguard-go(依存で自動) が VPN エンジン
      "cloudflared" # Cloudflare tunnel
      "nextdns"
      "scrcpy" # Android mirror
      "tcpdump"

      # ─── Mail ───
      "isync"

      # ─── Documents / Fonts / Media ───
      "gstreamer"
      "mpv"
      "homebrew-zathura/zathura/zathura-pdf-mupdf"
      # zathura-pdf-mupdf の tap内依存。新 brew は HOMEBREW_REQUIRE_TAP_TRUST 既定ONで
      # brew bundle が trust.json を Brewfile 基準に再生成するため、明示しないと依存が
      # untrusted で "Refusing to load" になる → Brewfile に書いて auto-trust させる。
      "homebrew-zathura/zathura/zathura"
      "homebrew-zathura/zathura/synctex"
      "girara" # zathura の UI ライブラリ。zathura が dlopen するので必須
      # zathura が runtime で dlopen する GTK 統合。Homebrew 側が依存宣言してないため
      # 明示しないと cleanup="uninstall" で孤立判定→削除され zathura が dyld エラーになる。
      "gtk-mac-integration"
      "adwaita-icon-theme" # GTK アイコンテーマ (zathura/girara UI)

      # ─── macOS specific CLI ───
      "mas" # App Store
      "blueutil" # Bluetooth
      "media-control" # media keys
      "terminal-notifier"
      "duti" # file associations
      "jakehilborn/jakehilborn/displayplacer" # sketchybar マルチディスプレイ

      # ─── Status bar / Window decoration (felixkratz tap) ───
      "felixkratz/formulae/sketchybar"
      "felixkratz/formulae/borders" # aerospace から exec-and-forget で起動

      # ─── Transcription / other 3rd-party tap brews ───
      "finnvoor/tools/yap" # 日本語 transcription
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
      "wine-stable" # WineHQ 安定版。Windows アプリ実行 (winetricks と併用)
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
