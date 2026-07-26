# Darwin chrome component (ECS: profile)。テーマ依存の WM/bar/borders/sioyek/Obsidian。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  c = import ../../lib/theme.nix; # アクティブテーマのパレット (切替は nix/lib/theme.nix の active)
  rgb = import ../../lib/hex-rgb.nix { inherit lib; }; # hex → "r g b" 0-1 float (sioyek 用)

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

  # Obsidian: theme.nix のパレットを CSS 変数へ。Obsidian の外観 = "system" (OS 追従) に
  # 合わせ .theme-dark / .theme-light 双方を生成 (sketchybar の dark/light 二重埋めと同思想)。
  obsidianVars = p: ''
    --background-primary:         #${p.base};
    --background-primary-alt:     #${p.surface};
    --background-secondary:       #${p.surface};
    --background-secondary-alt:   #${p.overlay};
    --text-normal:                #${p.text};
    --text-muted:                 #${p.subtle};
    --text-faint:                 #${p.muted};
    --text-accent:                #${p.iris};
    --text-accent-hover:          #${p.rose};
    --interactive-accent:         #${p.iris};
    --interactive-accent-hover:   #${p.rose};
    --background-modifier-border: #${p.hlMed};
    /* UI クロム (タイトルバー/リボン/タブ/ステータスバー/ナビ/スクロールバー) */
    --titlebar-background:         #${p.overlay};
    --titlebar-background-focused: #${p.overlay};
    --titlebar-text-color:         #${p.text};
    --ribbon-background:           #${p.overlay};
    --tab-container-background:     #${p.overlay};
    --tab-background-active:        #${p.hlMed};
    --tab-text-color-focused-active-current: #${p.text};
    --status-bar-background:        #${p.surface};
    --status-bar-text-color:        #${p.subtle};
    --divider-color:                #${p.hlMed};
    --scrollbar-thumb-bg:           #${p.hlMed};
    --scrollbar-active-thumb-bg:    #${p.muted};
    --nav-item-background-active:   #${p.overlay};'';
  # 半透明: translucency ON (.is-translucent) 時のみ背景へ alpha を載せ macOS vibrancy を透かす。
  # alpha は #RRGGBBAA の AA(16進): cc≒80% / b3≒70% / 99≒60% / 80≒50%。小さいほど透ける。
  translucentAlpha = "b3"; # 本文・サイドバー (vibrancy と相性の良いフロスト半透明 ≒70%)
  chromeAlpha = "99"; # 外周(タイトルバー/タブ/リボン)を少し強めに透かす(≒60%)
  obsidianTranslucent = p: ''
    --background-primary:          #${p.base}${translucentAlpha};
    --background-primary-alt:      #${p.surface}${translucentAlpha};
    --background-secondary:        #${p.surface}${translucentAlpha};
    --background-secondary-alt:    #${p.overlay}${translucentAlpha};
    --titlebar-background:         #${p.overlay}${chromeAlpha};
    --titlebar-background-focused: #${p.overlay}${chromeAlpha};
    --ribbon-background:           #${p.overlay}${chromeAlpha};
    --tab-container-background:    #${p.overlay}${chromeAlpha};
    --status-bar-background:       #${p.surface}${translucentAlpha};'';
  # スニペットは Obsidian が「読むだけ」なので Nix 所有 (生成物) でも編集・同期と衝突しない。
  obsidianThemeCss = pkgs.writeText "nix-theme.css" ''
    /* ============================================================
       AUTO-GENERATED from nix/lib/theme.nix — 手で編集しない。
       テーマ変更は nix/lib/theme.nix の active を変えて `just rebuild`。
       ============================================================ */
    .theme-dark {
    ${obsidianVars c.dark}
    }
    .theme-light {
    ${obsidianVars c.light}
    }
    /* 半透明 (設定→外観→半透明 ON 時のみ適用) */
    .theme-dark.is-translucent {
    ${obsidianTranslucent c.dark}
    }
    .theme-light.is-translucent {
    ${obsidianTranslucent c.light}
    }
    /* タブ/タイトルバー帯を確実にテーマ追従 (Minimal の黒上書き対策・変数で勝てない時用) */
    .workspace-tab-header-container,
    .workspace-tabs .workspace-tab-header-container-inner,
    .titlebar,
    .workspace-ribbon.mod-left {
      background-color: var(--titlebar-background) !important;
    }
    /* タイポグラフィ: フォント自体は据え置き、行間・余白・スムージングを微調整 */
    body { -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
    .markdown-preview-view,
    .markdown-source-view.mod-cm6 .cm-content {
      --line-height-normal: 1.75;
      --p-spacing: 0.85em;
    }
    .markdown-rendered h1,
    .markdown-rendered h2,
    .markdown-rendered h3 { line-height: 1.3; }
  '';
in
{
  # aerospace: 解像度可変 gaps/padding。config include 非対応 + nix symlink は read-only なので、
  # symlink ではなく activation で ~/.config/aerospace/aerospace.toml を生成する。
  # メインディスプレイ解像度から gaps/accordion-padding をスケール → dry-run 検証 → reload-config。
  # source 内の @DOTFILES@ は生成時に現在の $HOME/.dotfiles へ展開する。
  home.activation.aerospaceConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.bash}/bin/bash ${../../../scripts/aerospace-config.sh} ${../../../configs/wm/aerospace/aerospace.toml}
  '';
  home.file.".config/sketchybar" = {
    source = ../../../configs/wm/sketchybar;
    recursive = true;
  };
  # sketchybar の色は nix/lib/theme.nix から生成 (静的 colors.sh は廃止)。
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

  # sketchybar の display map (aerospace monitor -> sketchybar display index) を
  # ディスプレイ構成変化時に再計算し /tmp/sketchybar-aero-display.map へ書き出す常駐 watcher。
  # これが無いと再起動で map が消え space.* が壊れる (手動 sketchybar-refresh が必要になる)。
  # 旧来は手動 plist だったが /Users/<旧名> ハードコードで壊れていたため nix 宣言へ移行。
  launchd.agents.sketchybar-displaywatch = {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.homeDirectory}/.config/sketchybar/helpers/display_watch.sh"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      ThrottleInterval = 10;
      StandardErrorPath = "/tmp/sketchybar-displaywatch.err";
      StandardOutPath = "/tmp/sketchybar-displaywatch.log";
    };
  };

  # sioyek: 色は nix/lib/theme.nix から生成 (hex→0-1 float は lib/hex-rgb.nix)。
  # macOS の sioyek は ~/Library/Application Support/sioyek/ を config dir に使う
  # (XDG 非対応)。prefs_user.config がユーザ上書き設定。sioyek 自身は auto.config/
  # db を同 dir に書くが prefs_user.config は読むだけなので store symlink で問題なし。
  home.file."Library/Application Support/sioyek/prefs_user.config".text = ''
    # Rosé Pine — generated from nix/lib/theme.nix
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

  # Obsidian: theme.nix 由来のカラースニペットを vault に配置 (テーマ切替で追従)。
  # ・vault が設定の本体。ここは生成スニペット 1 枚だけ Nix 所有 (他の .obsidian は触らない)。
  # ・symlink でなく実コピー → LiveSync/git でスマホへも伝播。毎回上書きで変更を反映。
  # ・初回のみ Obsidian で「設定→外観→CSS スニペット→nix-theme」を ON にする (以降は同期で維持)。
  home.activation.obsidianTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    obsidian_dir="${config.home.homeDirectory}/Documents/notes/.obsidian"
    if [ -d "$obsidian_dir" ]; then
      /bin/mkdir -p "$obsidian_dir/snippets"
      # Obsidian が開いたファイルには com.apple.macl (TCC) が付与され、FDA 無しの
      #   activation からは install の rename が EPERM になる。スニペットは vault が本体
      #   (LiveSync で伝播) なので、更新できない場合は警告に留めて switch 全体は止めない。
      if ! /usr/bin/install -m 644 ${obsidianThemeCss} "$obsidian_dir/snippets/nix-theme.css" 2>/dev/null; then
        echo "warning: obsidianTheme: nix-theme.css を更新できませんでした (Obsidian の TCC ロックの可能性)。vault 側が本体のためスキップ。" >&2
      fi
    fi
  '';
}
