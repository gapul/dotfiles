{
  config,
  pkgs,
  lib,
  user,
  ...
}:
{
  imports = [
    ../modules/home/darwin-chrome.nix
    ../modules/home/darwin-services.nix
    ../modules/home/darwin-apps.nix
  ];

  # macOS 専用の home-manager 設定
  # 共通部分は home/common.nix に分離

  home.homeDirectory = "/Users/${user.username}";

  home.sessionVariables = {
    HOMEBREW_NO_ANALYTICS = "1";
    # NOTE: brew の trust.json は XDG 化不可。activation の brew bundle は
    # `sudo --preserve-env=PATH --set-home` で XDG_CONFIG_HOME を剥がし必ず ~/.homebrew を読む。
    # かつ brew は XDG_CONFIG_HOME を HOMEBREW_USER_CONFIG_HOME より優先するため、対話シェルの
    # 素の trust は ~/.config/homebrew に逸れて二重化していた。下の
    # `.config/homebrew → ~/.homebrew` symlink で両経路が同一実体に収束する
    # (Justfile rebuild の `env -u XDG_CONFIG_HOME` は無害なので温存)。
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
    # nh: darwin は darwinConfigurations.<user> 形式で可。home は nh 4.3.2 だと
    # #名前/#...activationPackage どちらも不可 → flake のみ(#なし)にして user 名で
    # homeConfigurations.<user> を自動判別させるのが唯一通る形。
    NH_DARWIN_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix#darwinConfigurations.${user.username}";
    NH_HOME_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix";
  };

  # brew trust.json の二重化解消: 対話シェル (XDG_CONFIG_HOME 優先で
  # ~/.config/homebrew を読む) と sudo/rebuild 経路 (~/.homebrew) を
  # symlink で同一実体に収束させる。正は ~/.homebrew (sudo 側は XDG を見ない)。
  home.file.".config/homebrew".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.homebrew";

  # XDG 非対応ツールの実データを XDG 配下へ移し、既定パスは symlink で維持する
  # (terminfo と同方式)。分類: 資格情報/長期データ=data、テレメトリ状態=state。
  home.file.".appstoreconnect".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/appstoreconnect";
  home.file.".cloudflared".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/cloudflared";
  home.file.".ollama".source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/ollama";
  home.file.".dart-tool".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/dart-tool";
  # symlink 先が無いとツールの書き込みが ENOENT になるため実体を先に確保
  home.activation.xdgSymlinkTargets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.xdg.dataHome}/appstoreconnect" \
      "${config.xdg.dataHome}/cloudflared" \
      "${config.xdg.dataHome}/ollama" \
      "${config.xdg.stateHome}/dart-tool"
  '';

  home.sessionPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "${config.home.homeDirectory}/Library/pnpm"
    "${config.home.homeDirectory}/Library/pnpm/bin"
  ];

  # zsh の Mac 専用 init を append (common の initContent の後ろに追加)
  programs.zsh.initContent = lib.mkAfter ''
    if [[ -f /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    # Bitwarden SSH agent: Desktop(直接DL版)が有効化時に作る socket があれば優先。
    # 鍵は Bitwarden Vault に保管し、接続毎に Desktop が承認(Touch ID)する。
    # Bitwarden 未起動/未有効でも壊れないよう、socket 不在時は launchd 既定へフォールバック。
    if [[ -S "$HOME/.bitwarden-ssh-agent.sock" ]]; then
      export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
    fi

    # CocoaPods (nix ruby と衝突回避)
    unset GEM_HOME GEM_PATH

    # sketchybar 再構成ラッパー (ディスプレイ抜き差し後に呼ぶ)
    function sketchybar-refresh() {
      bash ~/.config/sketchybar/helpers/refresh-displays.sh "$@"
    }

    # クラムシェルスリープの一時無効化トグル。
    # フタを閉じても裏で処理を動かし続けたいときに使う。
    # 再起動でリセットされる一時設定。off で通常に戻す。
    function nosleep() {
      case "$1" in
        off)
          sudo pmset -a disablesleep 0 && echo "スリープ無効を解除しました (通常のスリープに戻ります)"
          ;;
        status|"")
          if pmset -g | grep -q "SleepDisabled.*1"; then
            echo "現在: スリープ無効 (フタを閉じても動作継続)"
          else
            echo "現在: 通常 (フタを閉じるとスリープ)"
          fi
          ;;
        on)
          sudo pmset -a disablesleep 1 && echo "スリープを無効化しました (フタを閉じても動作継続 / 電源接続を推奨)"
          ;;
        *)
          echo "使い方: nosleep [on|off|status]"
          ;;
      esac
    }
  '';

  # mac 専用パッケージ
  home.packages = with pkgs; [
    bun # karabiner.ts 設定の生成・型検査
    brewCasks.qview # brew-nix試験対象: 単純な.app配布の軽量画像ビューア
    pngpaste # obsidian.nvim / img-clip の macOS 画像貼付に必要
    syncthing # Syncthing CLI (常駐は services.syncthing の LaunchAgent)
    xcodegen # project.yml → .xcodeproj 生成 (Mac 専用、Linux nixpkgs では meta.platforms = darwin のため)
    (callPackage ../pkgs/slk.nix { }) # Slack TUI (公式 GitHub Release を固定)
  ];

  home.file.".config/ghostty" = {
    source = ../../configs/terminals/ghostty;
    recursive = true;
  };
  # Ghostty: 解像度可変フォントサイズ。メインディスプレイの論理縦解像度から font-size を
  # 算出し ~/.config/ghostty.local/font-size.conf に書き出す (config が ? 付きで include)。
  # nh home switch のたびに再計算。解像度を変えたら再度 switch するか、
  # scripts/ghostty-fontsize.sh を手で実行 → Ghostty で config reload すれば反映される。
  home.activation.ghosttyFontSize = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.bash}/bin/bash ${../../scripts/ghostty-fontsize.sh}
  '';

  # lazygit: この Mac は XDG_CONFIG_HOME=~/.config を設定しているため、lazygit は
  # ~/.config/lazygit/config.yml を優先して読む。一方 programs.lazygit は Darwin では
  # ~/Library/Application Support/lazygit/ に書き出すため、common.nix の theme 設定が
  # 実際には適用されない (~/.config 側の空ファイルが優先されてしまう)。
  # そこで programs.lazygit.settings を XDG パスにも生成し、確実に効かせる。
  # (この定義は Darwin 限定。Linux では HM の lazygit module 自身が同じパスを
  #  定義するため、common.nix に置くと衝突する)
  xdg.configFile."lazygit/config.yml".source =
    (pkgs.formats.yaml { }).generate "lazygit-config.yml"
      config.programs.lazygit.settings;
}
