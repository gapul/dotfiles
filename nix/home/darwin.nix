{
  config,
  pkgs,
  lib,
  user,
  ...
}:
let
  c = import ../lib/theme.nix; # アクティブテーマのパレット (切替は nix/lib/theme.nix の active)
  rgb = import ../lib/hex-rgb.nix { inherit lib; }; # hex → "r g b" 0-1 float (sioyek 用)

  # sketchybar colors.sh の「パレット依存 export 群」を palette p から生成。
  # dark/light 双方を colors.sh に埋め、AppleInterfaceStyle で分岐させて OS 追従させる。
  sbHex = p: ''
    # rose-pine の役割色を sketchybar の意味付けへ忠実マッピング。
    # (rose-pine は純粋な緑/橙を持たないため、success=foam / warm=rose を採用)
    export BLACK=0xff${p.base}    # 背景 (最暗/最明)
    export WHITE=0xff${p.text}    # 前景・テキスト
    export RED=0xff${p.love}      # error / critical
    export GREEN=0xff${p.foam}    # success / active (rose-pine の positive)
    export BLUE=0xff${p.pine}     # info
    export YELLOW=0xff${p.gold}   # warning
    export ORANGE=0xff${p.rose}   # warm accent
    export MAGENTA=0xff${p.iris}  # primary accent (rose-pine signature)
    export GREY=0xff${p.muted}    # inactive / subtle
    export ACCENT=0xff${p.iris}   # アクティブ要素のアクセント
    # 背景 pill: surface=不透明 / overlay・hlMed は 0xcc に上げて light でも視認
    export BG0=0xff${p.surface}
    export BG1=0xcc${p.overlay}
    export BG2=0xcc${p.hlMed}
    export BATTERY_1=0xff${p.foam}
    export BATTERY_2=0xff${p.gold}
    export BATTERY_3=0xff${p.rose}
    export BATTERY_4=0xff${p.love}
    export BATTERY_5=0xff${p.love}'';
in
{
  # macOS 専用の home-manager 設定
  # 共通部分は home/common.nix に分離

  home.homeDirectory = "/Users/${user.username}";

  home.sessionVariables = {
    HOMEBREW_NO_ANALYTICS = "1";
    # NOTE: brew の trust.json は XDG 化不可。activation の brew bundle は
    # `sudo --preserve-env=PATH --set-home` で XDG_CONFIG_HOME を剥がし必ず ~/.homebrew を読む。
    # かつ brew は XDG_CONFIG_HOME を HOMEBREW_USER_CONFIG_HOME より優先するため、対話シェルの
    # 素の trust は ~/.config/homebrew に逸れる。Justfile rebuild が `env -u XDG_CONFIG_HOME` で
    # ~/.homebrew に揃えて書くことで一致させる ([[project_homebrew_trust_sudo]])。
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
    # nh: darwin は darwinConfigurations.<user> 形式で可。home は nh 4.3.2 だと
    # #名前/#...activationPackage どちらも不可 → flake のみ(#なし)にして user 名で
    # homeConfigurations.<user> を自動判別させるのが唯一通る形。
    NH_DARWIN_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix#darwinConfigurations.${user.username}";
    NH_HOME_FLAKE = "${config.home.homeDirectory}/.dotfiles/nix";
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
    pngpaste # obsidian.nvim / img-clip の macOS 画像貼付に必要
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
  # sketchybar の色は nix/lib/rose-pine.nix から生成 (静的 colors.sh は廃止)。
  # 他の sketchybar スクリプトは従来どおり $WHITE 等でこれを source する。
  home.file.".config/sketchybar/colors.sh".text = ''
    #!/bin/bash
    # Rosé Pine — dark/light を macOS 外観 (AppleInterfaceStyle) で自動選択。
    # 色は nix/lib/theme.nix の dark/light パレット由来 (単一ソース)。
    # 外観変化時は theme-watch agent が `sketchybar --reload` し、ここが再評価される。
    if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
    ${sbHex c.dark}
    else
    ${sbHex c.light}
    fi
    export TRANSPARENT=0x00000000

    # General bar colors (パレット非依存・上の export から導出)
    export BAR_COLOR=$BG0
    export BAR_BORDER_COLOR=$BG2
    export BACKGROUND_1=$BG1
    export BACKGROUND_2=$BG2
    export ICON_COLOR=$WHITE
    export LABEL_COLOR=$WHITE
    export POPUP_BACKGROUND_COLOR=$BAR_COLOR
    export POPUP_BORDER_COLOR=$WHITE
    export SHADOW_COLOR=$BLACK
  '';
  # borders は AeroSpace から引数なし `borders` で起動され bordersrc を実行する。
  # executable=true でないと borders が実行できない (設定の単一ソース)。
  # 色は theme.nix の dark/light 由来。macOS 外観で active/inactive を分岐し OS 追従。
  # 外観変化時は theme-watch agent が bordersrc を再実行し、走行中の borders daemon に反映。
  home.file.".config/borders/bordersrc" = {
    executable = true;
    text = ''
      #!/bin/bash
      # JankyBorders 設定 = アクティブウィンドウ枠の単一ソース。色は Rosé Pine palette 由来。
      if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
        active=0xff${c.dark.iris}
        inactive=0xff${c.dark.muted}
      else
        active=0xff${c.light.iris}
        inactive=0xff${c.light.muted}
      fi
      options=(
        active_color=$active
        inactive_color=$inactive
        width=4.0
      )
      borders "''${options[@]}"
    '';
  };

  # theme-watch: macOS 外観 (ライト/ダーク) の変化を監視し、shell 系 chrome を再適用する。
  # sketchybar/borders は colors.sh/bordersrc 内で AppleInterfaceStyle を見て分岐するので、
  # 変化時に reload/再実行するだけで OS 追従できる。外部バイナリ不要のポーリング方式。
  home.file.".config/theme/theme-watch.sh" = {
    executable = true;
    text = ''
      #!/bin/bash
      # macOS 外観変化を監視 → sketchybar reload + borders 再適用 (theme.nix カテゴリB の追従)
      export PATH="/opt/homebrew/bin:$PATH"
      last=""
      while true; do
        cur="$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"
        if [ "$cur" != "$last" ]; then
          last="$cur"
          [ -x "$HOME/.config/borders/bordersrc" ] && "$HOME/.config/borders/bordersrc" >/dev/null 2>&1 &
          sketchybar --reload >/dev/null 2>&1
        fi
        sleep 2
      done
    '';
  };

  # 上記 watcher を常駐 launchd agent として起動 (ログイン時+死活監視)。
  launchd.agents.theme-watch = {
    enable = true;
    config = {
      ProgramArguments = [ "${config.home.homeDirectory}/.config/theme/theme-watch.sh" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/theme-watch.err";
      StandardOutPath = "/tmp/theme-watch.out";
    };
  };

  # sioyek: 色は nix/lib/rose-pine.nix から生成 (hex→0-1 float は lib/hex-rgb.nix)。
  # macOS の sioyek は ~/Library/Application Support/sioyek/ を config dir に使う
  # (XDG 非対応)。prefs_user.config がユーザ上書き設定。sioyek 自身は auto.config/
  # db を同 dir に書くが prefs_user.config は読むだけなので store symlink で問題なし。
  home.file."Library/Application Support/sioyek/prefs_user.config".text = ''
    # Rosé Pine — generated from nix/lib/rose-pine.nix
    # UI chrome
    background_color ${rgb c.base}
    status_bar_color ${rgb c.surface}
    status_bar_text_color ${rgb c.text}
    # ページ境界をガター(base)に馴染ませる
    page_separator_width 2
    page_separator_color ${rgb c.hlMed}
    # highlights
    text_highlight_color ${rgb c.gold}
    search_highlight_color ${rgb c.love}
    link_highlight_color ${rgb c.foam}
    synctex_highlight_color ${rgb c.pine}
    visual_mark_color ${rgb c.iris} 0.3
    # custom color mode (ダーク読書時のページ色) / dark mode
    custom_background_color ${rgb c.base}
    custom_text_color ${rgb c.text}
    dark_mode_background_color ${rgb c.base}
    dark_mode_contrast 0.85
  '';

  # sioyek キーバインド上書き: custom color mode (rose-pine 地で読む) を F7 に割当。
  # F8=標準のダーク反転 と使い分け (デフォルトは toggle_custom_color 未割当)。
  home.file."Library/Application Support/sioyek/keys_user.config".text = ''
    # Rosé Pine custom color mode を F7 でトグル
    toggle_custom_color <f7>
  '';

  # karabiner は dotfiles 直接書き戻し (mkOutOfStoreSymlink)
  home.file.".config/karabiner".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/keyboard/karabiner";

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

  # macSKK kana-rule (ローマ字変換ルール) を配置
  # plist ではなく sandbox Container 内の Documents ファイルなので実コピーで反映
  home.activation.skkKanaRule = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    skk_settings="${config.home.homeDirectory}/Library/Containers/net.mtgto.inputmethod.macSKK/Data/Documents/Settings"
    if [ -d "$skk_settings" ]; then
      /usr/bin/install -m 644 \
        ${../../configs/ime/skk/kana-rule.conf} \
        "$skk_settings/kana-rule.conf"
    fi
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
