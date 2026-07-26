{ pkgs, user, ... }:
{
  # ワークステーション (darwin.nix) と ヘッドレス LLM ワーカー (macmini.nix) が
  # 共有する host 非依存のベース設定。ここを直すと両ホストに効く。
  # GUI/周辺機器寄りの設定 (dock/finder/trackpad/fonts/homebrew) は各ホスト側に置く。

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
    # nix-community キャッシュを system 全体で信頼。
    # セキュリティ最小権限: yuki を trusted-user(実質 root 相当)にはせず、特定 substituter +
    # その公開鍵だけを root 権限の nix.custom.conf に追記する。これで flake nixConfig の
    # 'ignoring untrusted substituter' 警告が消え、ユーザーに広い権限を与えない。
    if [ -f "$conf" ] && ! /usr/bin/grep -q 'nix-community.cachix.org' "$conf"; then
      printf '\n# nix-community バイナリキャッシュ (trusted-user 付与でなく substituter 限定の最小権限)\nextra-substituters = https://nix-community.cachix.org\nextra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=\n' >> "$conf"
    fi
    # nix-on-droid: proot-termux 等のプリビルドは公式 cachix からしか取得できない
    if [ -f "$conf" ] && ! /usr/bin/grep -q 'nix-on-droid.cachix.org' "$conf"; then
      printf '\n# nix-on-droid バイナリキャッシュ (droid 構成の eval/build 用)\nextra-substituters = https://nix-on-droid.cachix.org\nextra-trusted-public-keys = nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU=\n' >> "$conf"
    fi
    # Determinate Nix already trusts FlakeHub as a substituter, but using it as an
    # active substituter without the matching credentials produces 401 warnings.
    if [ -f "$conf" ] && /usr/bin/grep -q 'cache.flakehub.com' "$conf"; then
      /usr/bin/sed -i.bak '/cache\.flakehub\.com/d' "$conf"
      /bin/rm -f "$conf.bak"
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
  # reattach: zellij/tmux/screen 等のマルチプレクサ内ではセッションが GUI から
  # 分離され pam_tid が Touch ID ダイアログを出せない。pam_reattach (nixpkgs) を
  # auth optional で前置し、ユーザの bootstrap session へ再接続させて解決する。
  # (Touch ID センサの無い Mac mini では単に password 認証にフォールバックするだけで無害)
  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
  };

  users.users.${user.username} = {
    name = user.username;
    home = "/Users/${user.username}";
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # host 非依存の macOS 設定 (キーボード/ログイン/プライバシー)。
  # dock/finder/trackpad 等の GUI/周辺機器寄りは各ホスト側で宣言する。
  system.defaults = {
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
    };
  };
}
