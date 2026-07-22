{ pkgs, ... }: {
  # host 非依存のベース (nix cache / firewall / security / login hardening 等) は
  # darwin-common.nix に集約。ここは常用ワークステーション固有の設定のみ置く。
  imports = [ ./darwin-common.nix ];

  # macOS 設定 (GUI/周辺機器寄り。実機の defaults read で確認した値のみ宣言)
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
      # Homebrew 6.0 で既定 true 化した REQUIRE_TAP_TRUST を activation 時のみ無効化。
      # 非公式 tap の依存 formula (qmk/hid_bootloader_cli 等) が拒否され bundle が止まるのを防ぐ。
      # 全 tap は上で宣言・バージョン管理済みなので runtime の信頼チェックは冗長。
      extraEnv = {
        HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
      };
    };

    # tap の信頼は onActivation.extraEnv の HOMEBREW_NO_REQUIRE_TAP_TRUST=1 で一括対応。
    # (Homebrew 6.0 で REQUIRE_TAP_TRUST が既定 true 化。tap 行の trusted: true は依存 formula
    #  の読み込みには効かず、手動 brew trust は bundle が毎回上書きするため使えない。
    #  全 tap は下記で宣言・バージョン管理済みなので activation 時のチェックを切る。)
    taps = [
      "chojs23/tap" # Concord (Discord TUI)
      "deskflow/tap"
      "felixkratz/formulae"
      "finnvoor/tools"
      "gerlero/openfoam"
      "gapul/kdeconnect" # imshuhao/kdeconnect の fork。depends_on macos deprecated を修正済
      "macos-fuse-t/cask" # fuse-t (KEXT-less FUSE。rclone mount 用)
      "nikitabobko/tap"
      "osx-cross/arm" # QMK toolchain dependency tap
      "osx-cross/avr" # QMK / Keyball AVR toolchain tap
      "pear-devs/pear"
      "qmk/qmk" # QMK CLI
      "voicevox/voicevox" # VOICEVOX 公式 tap (homebrew/cask 未収録のため必須)

      # ─── 個人 fork (gapul) — fork した人は不要なら削除 ───
      "gapul/openutau"
      "gapul/zrythm"
      "gapul/azoo-key-skkserv"
      "gapul/keystats" # 自作の打鍵アナリティクス(cask)
    ];

    # brew leaves
    # (starship / fzf / atuin / pipx は home-manager / uv 管理に移行のため除外)
    brews = [
      # ─── Languages / Package managers ───
      # deno: nvim skkeleton(denops) の runtime + yt-dlp の JS チャレンジ解読に使用。
      # 現状は mpv/yt-dlp の依存だが、それらを消すと孤立して skkeleton が壊れるため明示宣言。
      "deno"
      "swi-prolog" # Prolog (関数・論理型プログラミング実験 第10-12回)

      # ─── Keyboard firmware ───
      "qmk/qmk/qmk" # QMK CLI (Keyball firmware build/flash)
      "osx-cross/avr/avr-gcc@12" # Keyball 用 AVR toolchain (keg-only)

      # ─── wine 補助 ───
      "winetricks" # wine prefix への DLL/コンポーネント導入ヘルパ

      # ─── TUI utilities ───
      "chojs23/tap/concord" # Discord TUI (画像・スレッド・音声対応)
      "herdr" # AI coding agent multiplexer
      "wifitui" # wifi (nixpkgs は Linux 専用のため brew 維持)

      # ─── Network / Download / VPN ───
      "tailscale"
      "tor"
      "wireguard-tools" # wg-quick + wireguard-go(依存で自動) が VPN エンジン
      "cloudflared" # Cloudflare tunnel
      "nextdns"
      "scrcpy" # Android mirror
      "tcpdump"
      "gnupg" # GPG (git コミット署名 / 暗号メール。sops は age だが GPG は別)

      # ─── Documents / Fonts / Media ───
      "gstreamer"
      "mpv"
      "sox" # 音声処理 (rec / play / sox / soxi)
      "exiftool" # 画像/PDF のメタデータ (GPS/端末情報) を共有前に除去

      # ─── macOS specific CLI ───
      "mas" # App Store
      "blueutil" # Bluetooth
      "media-control" # media keys
      "terminal-notifier"
      "duti" # file associations
      "displayplacer" # sketchybar マルチディスプレイ (homebrew/core 昇格済・同v1.4.0)

      # ─── Status bar / Window decoration (felixkratz tap) ───
      "felixkratz/formulae/sketchybar"
      "felixkratz/formulae/borders" # aerospace から exec-and-forget で起動

      # ─── Transcription / other 3rd-party tap brews ───
      "finnvoor/tools/yap" # 日本語 transcription
    ];

    # GUI applications (~100個)
    casks = [
      # ─── Browsers ───
      "google-chrome"
      "tor-browser"
      "zen"
      "pear-desktop"

      # ─── PDF viewers ───
      # sioyek は未署名の x86_64 cask (Rosetta 動作)。brew 既定の quarantine が付くと
      # Gatekeeper に「壊れている/マルウェア」判定され起動不能になるため no_quarantine 必須。
      {
        name = "sioyek";
        args = {
          no_quarantine = true;
        };
      } # vim キーバインドの軽量 PDF ビューア (zathura 代替・常用)
      "skim" # ネイティブ SyncTeX ビューア。TeX 執筆用の保険 (連携は後日)

      # ─── Image viewers ───
      # qView は ad-hoc 署名のみ (未 notarize)。quarantine 付きだと Gatekeeper に
      # rejected され起動不能になるため no_quarantine 必須 (sioyek と同様)。
      {
        name = "qview";
        args = {
          no_quarantine = true;
        };
      } # 軽量画像ビューア (yazi の image opener に使用)

      # ─── Communication & Sync ───
      "beeper"
      "kdeconnect"
      "localsend"
      "simplex"

      # ─── Window / Keyboard / Input ───
      "aerospace"
      "alt-tab"
      "karabiner-elements"
      "macskk"
      "gapul/azoo-key-skkserv/azoo-key-skkserv" # azooKey 変換エンジンの skkserv (gapul 自作 tap)
      "shortcat"

      # ─── macOS utilities ───
      "hammerspoon"
      "espanso"
      "maccy"
      "monitorcontrol"
      "mos"
      "qlmarkdown"
      "corelocationcli"
      "fuse-t" # KEXT-less FUSE (NFS バックエンド)。rclone mount ~/Cloud/GoogleDrive 用。KEXT/リカバリー不要

      # ─── Privacy / Security ───
      # Objective-See (Patrick Wardle) スイート — 全て無料・notarize 済み
      "blockblock" # 永続化 (persistence) 監視
      "knockknock" # 永続化スキャナ
      "lulu" # 送信ファイアウォール
      "oversight" # マイク/カメラの不正アクセス検知・通知
      "reikey" # キーロガー (キーボード event tap) 検知
      "netiquette" # ライブ通信モニタ (どのプロセスがどこへ)
      "taskexplorer" # プロセス検査 (署名 / VirusTotal 照合)
      "whatsyoursign" # Finder 右クリックでコード署名表示
      "kextviewr" # kernel extension ビューア
      "ransomwhere" # ランサムウェア (不審な暗号化挙動) 検知
      # VPN / 鍵
      "mullvad-vpn" # ノーログ匿名 VPN (self-host の WireGuard/Tailscale とは別レイヤ)
      "ente-auth"
      "keepassxc"
      "keyguard"
      "bitwarden" # Bitwarden 公式デスクトップアプリ

      # ─── Network / Remote ───
      "tailscale-app"
      "rustdesk"

      # ─── Dev IDEs / Editors / SDK ───
      "claude" # Claude デスクトップアプリ (Anthropic 公式)
      "claude-code"
      "ghostty"
      "zed"
      "android-studio"
      "flutter"
      "imhex"
      "trex"
      "deskflow"
      "deskreen"
      "codexbar" # AI コーディング各社の使用量/上限をメニューバー表示 (codexbar CLI 同梱・/opt/homebrew/bin に自動 link)

      # ─── Creative — Design / 2D ───
      "affinity"
      "gimp"
      "krita"
      "inkscape"
      "scribus"
      "darktable"
      "rawtherapee"
      "digikam" # 写真管理 (RAW現像・タグ管理)
      "upscayl"
      "fontforge-app"
      "fontgoggles"
      "pika"
      "adobe-creative-cloud"
      "sf-symbols" # Apple SF Symbols カタログ

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
      "supercollider"
      "surge-xt" # シンセ standalone/プラグイン (.pkg cask)
      "gapul/zrythm/zrythm" # DAW (gapul 自作 tap)
      "vcv-rack"
      "voicevox/voicevox/voicevox" # 公式 tap 専用 (homebrew/cask 未収録)。tap宣言必須
      # 自作の打鍵アナリティクス。Developer ID 署名 + 公証済みなので隔離付きでも
      # Gatekeeper を通過する(no_quarantine 不要)。
      "gapul/keystats/keystats"
      "blackhole-2ch" # OBS / DAW へシステム音声を回す仮想オーディオデバイス

      # ─── Creative — Video / Animation / Stream ───
      "obs"
      "kap" # オープンソース画面レコーダー (getkap.co)
      "gyroflow"
      "touchdesigner"
      "cavalry" # 2D モーショングラフィックス
      "opentoonz" # 2D アニメーション (.pkg cask)

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
