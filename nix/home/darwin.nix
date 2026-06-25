{ config, pkgs, lib, user, ... }: {
  # macOS 専用の home-manager 設定
  # 共通部分は home/common.nix に分離

  home.homeDirectory = "/Users/${user.username}";

  home.sessionVariables = {
    HOMEBREW_NO_ANALYTICS = "1";
    # trust.json を ~/.homebrew → XDG_CONFIG へ (既定は $HOME/.homebrew, trust.rb:27)。
    # 影響は対話 brew のみ。nh の system activation は HOME=~root で brew を回すため不変。
    HOMEBREW_USER_CONFIG_HOME = "${config.xdg.configHome}/homebrew";
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
    # nh 4.x: programs.nh.flake は古い FLAKE 変数しか set しないので、
    # darwinConfigurations.<user> / homeConfigurations.<user> まで明示
    NH_DARWIN_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix#darwinConfigurations.${user.username}";
    NH_HOME_FLAKE   = "${config.home.homeDirectory}/.dotfiles/nix#homeConfigurations.${user.username}.activationPackage";
  };

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

    # CocoaPods (nix ruby と衝突回避)
    unset GEM_HOME GEM_PATH

    # sketchybar 再構成ラッパー (ディスプレイ抜き差し後に呼ぶ)
    function sketchybar-refresh() {
      bash ~/.config/sketchybar/helpers/refresh-displays.sh "$@"
    }
  '';

  # mac 専用パッケージ
  home.packages = with pkgs; [
    pngpaste              # obsidian.nvim / img-clip の macOS 画像貼付に必要
  ];

  # tealdeer: ~/Library/Application Support 配下 (Mac 規約)
  home.file."Library/Application Support/tealdeer/config.toml".text = ''
    [updates]
    auto_update = true
    auto_update_interval_hours = 720
    archive_source = "https://github.com/tldr-pages/tldr/releases/latest/download/tldr.zip"
  '';

  # espanso: 汎用スニペット (公開) — Mac の Container 内パスへ
  home.file."Library/Application Support/espanso/match/base.yml".source =
    ../../configs/espanso/base.yml;

  # macOS 専用 SOPS template (espanso の personal は Container パス)
  sops.templates."espanso-personal.yml" = {
    path = "${config.home.homeDirectory}/Library/Application Support/espanso/match/personal.yml";
    content = ''
      # espanso matches (PRIVATE) — sops.templates 生成。PII は secrets.yaml の pii: に集約
      matches:
        - trigger: ":gmail"
          label: "個人 Gmail"
          replace: "${config.sops.placeholder."pii/email_personal"}"
        - trigger: ":umail"
          label: "東大メール"
          replace: "${config.sops.placeholder."pii/email_school"}"
        - trigger: ":wmail"
          label: "業務メール"
          replace: "${config.sops.placeholder."pii/email_work"}"
        - trigger: ":sig"
          label: "署名"
          replace: |
            ----
            ${config.sops.placeholder."pii/name"}
            ${config.sops.placeholder."pii/email_work"}
    '';
  };

  # macOS 専用 GUI app の config (dotfiles/configs/* → ~/.config に symlink)
  home.file.".config/ghostty" = {
    source = ../../configs/terminals/ghostty;
    recursive = true;
  };
  home.file.".config/aerospace" = {
    source = ../../configs/wm/aerospace;
    recursive = true;
  };
  home.file.".config/sketchybar" = {
    source = ../../configs/wm/sketchybar;
    recursive = true;
  };

  # karabiner は dotfiles 直接書き戻し (mkOutOfStoreSymlink)
  home.file.".config/karabiner".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/configs/keyboard/karabiner";

  # macSKK / azooKey skkserv: sandboxed app の preferences を defaults import
  home.activation.skkPlistImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /usr/bin/defaults import net.mtgto.inputmethod.macSKK \
      ${../../configs/ime/skk/macSKK.plist}
    if [ -f /Applications/azooKey\ skkserv.app/Contents/MacOS/azooKey\ skkserv ]; then
      /usr/bin/defaults import io.github.gitusp.azoo-key-skkserv \
        ${../../configs/ime/skk/azoo-key-skkserv.plist}
    fi
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';

  # Maccy (clipboard manager) 設定 — clipboard 履歴は SQLite で別ファイル、触らない
  home.activation.maccyPlistImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/Library/Containers/org.p0deje.Maccy" ]; then
      /usr/bin/defaults import org.p0deje.Maccy \
        ${../../configs/clipboard/maccy/Maccy.plist}
      /usr/bin/killall cfprefsd 2>/dev/null || true
    fi
  '';

  # GUI ユーティリティ系 (AltTab / Mos / Plash / Shortcat) の plist 一括 import
  home.activation.guiAppsPlistImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /usr/bin/defaults import com.lwouis.alt-tab-macos \
      ${../../configs/apps/com.lwouis.alt-tab-macos.plist}
    /usr/bin/defaults import com.caldis.Mos \
      ${../../configs/apps/com.caldis.Mos.plist}
    /usr/bin/defaults import com.sproutcube.Shortcat \
      ${../../configs/apps/com.sproutcube.Shortcat.plist}
    if [ -d "$HOME/Library/Containers/com.sindresorhus.Plash" ]; then
      /usr/bin/defaults import com.sindresorhus.Plash \
        ${../../configs/apps/com.sindresorhus.Plash.plist}
    fi
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';

  # ログイン項目: ヘッドレス起動しない GUI 常駐アプリを auto-launch
  home.activation.macosLoginItems = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    LOGIN_APPS=(
      "/Applications/AeroSpace.app"
      "/Applications/Ghostty.app"
    )
    for app in "''${LOGIN_APPS[@]}"; do
      name=$(basename "$app" .app)
      if ! /usr/bin/osascript -e "tell application \"System Events\" to (name of login items) contains \"$name\"" 2>/dev/null | grep -q true; then
        /usr/bin/osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$app\", hidden:false}" >/dev/null 2>&1 || true
      fi
    done
  '';
}
