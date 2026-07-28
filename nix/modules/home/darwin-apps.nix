# Darwin apps component (ECS: profile)。GUI アプリ設定・入力系・plist import。
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # tealdeer: ~/Library/Application Support 配下 (Mac 規約)
  home.file."Library/Application Support/tealdeer/config.toml".text = ''
    [updates]
    auto_update = true
    auto_update_interval_hours = 720
    archive_source = "https://github.com/tldr-pages/tldr/releases/latest/download/tldr.zip"
  '';

  # espanso: 汎用スニペット (公開) — Mac の Container 内パスへ
  home.file."Library/Application Support/espanso/match/base.yml".source =
    ../../../configs/espanso/base.yml;

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
  home.file.".config/qmk/qmk.ini".text = ''
    [config]

    [user]
    qmk_home = ${config.home.homeDirectory}/repos/qmk

    [console]

    [general]
  '';

  # karabiner は dotfiles 直接書き戻し (mkOutOfStoreSymlink)
  home.file.".config/karabiner".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/keyboard/karabiner";

  # Hammerspoon: Space-Hyper+AeroSpace と競合しないモーダルなキーボードマウス。
  # init.lua が hs.autoLaunch(true) を設定するため、一度起動すればログイン時も常駐する。
  home.file.".hammerspoon".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/keyboard/hammerspoon";

  # neru: マウス無しの全画面ナビ (grid/hints/scroll。Shortcat の後継)。
  # config.toml を neru CLI / 手編集でライブ調整するため karabiner と同じ
  # ディレクトリ mkOutOfStoreSymlink。runtime cruft は同梱の .gitignore で除外。
  home.file.".config/neru".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/keyboard/neru";

  # neru の launchd 常駐 (ログイン時起動 + 死活監視) を純正サービス管理で登録。
  # plist を手書き複製すると純正 label com.y3owk1n.neru と二重起動になるため、
  # neru services install を冪等に呼ぶ。config.toml (上の symlink) が存在してから
  # 起動するので「config より先に daemon が上がりホットキー未登録」の初回レースも防ぐ。
  # Neru.app は brew cask のため、バイナリが入るまで (未 install 時) は skip。
  home.activation.neruService = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    NERU=/opt/homebrew/bin/neru
    if [ -x "$NERU" ] && ! "$NERU" services status 2>/dev/null | grep -qi loaded; then
      "$NERU" services install || true
    fi
  '';

  # mpv ランチャー (AppleScript droplet)。mpv 本体は brew formula (darwin.nix の
  # homebrew.brews) で、CLI バイナリのみ・.app を吐かないため、Finder の関連付け /
  # ドラッグ&ドロップ再生用にこの droplet を被せている。中身は
  # `on open` → /opt/homebrew/bin/mpv <files> & を呼ぶだけ。
  # recursive は付けない: バンドル丸ごとを 1 symlink にして adhoc 署名の seal を保つ。
  home.file."Applications/mpv.app".source = ../../../configs/media/mpv-app/mpv.app;

  # macSKK / azooKey skkserv: sandboxed app の preferences を defaults import
  home.activation.skkPlistImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /usr/bin/defaults import net.mtgto.inputmethod.macSKK \
      ${../../../configs/ime/skk/macSKK.plist}
    if [ -f /Applications/azooKey\ skkserv.app/Contents/MacOS/azooKey\ skkserv ]; then
      /usr/bin/defaults import io.github.gitusp.azoo-key-skkserv \
        ${../../../configs/ime/skk/azoo-key-skkserv.plist}
    fi
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';

  # macSKK kana-rule (ローマ字変換ルール) を配置
  # plist ではなく sandbox Container 内の Documents ファイルなので実コピーで反映
  home.activation.skkKanaRule = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    skk_settings="${config.home.homeDirectory}/Library/Containers/net.mtgto.inputmethod.macSKK/Data/Documents/Settings"
    if [ -d "$skk_settings" ]; then
      /usr/bin/install -m 644 \
        ${../../../configs/ime/skk/kana-rule.conf} \
        "$skk_settings/kana-rule.conf"
    fi
  '';

  # Maccy (clipboard manager) 設定 — clipboard 履歴は SQLite で別ファイル、触らない
  home.activation.maccyPlistImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/Library/Containers/org.p0deje.Maccy" ]; then
      /usr/bin/defaults import org.p0deje.Maccy \
        ${../../../configs/clipboard/maccy/Maccy.plist}
      /usr/bin/killall cfprefsd 2>/dev/null || true
    fi
  '';

  # GUI ユーティリティ系の plist 管理。
  # (Shortcat は neru に移行して撤去。Mos / AltTab はアンインストール済み)
  # Plash は websites(壁紙定義)と security-scoped bookmark をライブ側に持つため、
  # 全置換 import すると壁紙一式が消える。enforce したい 3 キーだけ surgical に書く。
  home.activation.guiAppsPlistImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/Library/Containers/com.sindresorhus.Plash" ]; then
      /usr/bin/defaults write com.sindresorhus.Plash deactivateOnBattery    -bool true
      /usr/bin/defaults write com.sindresorhus.Plash extendPlashBelowMenuBar -bool true
      /usr/bin/defaults write com.sindresorhus.Plash showOnAllSpaces         -bool true
    fi
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';

  # Skim: VimTeX 連携。逆方向検索 (PDF クリック→Neovim 該当行) と保存時の自動リロード。
  # 他の Skim 設定を壊さないよう、対象キーのみ surgical に書き込む。
  home.activation.skimSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /usr/bin/defaults write net.sourceforge.skim-app.skim SKTeXEditorPreset -string Custom
    /usr/bin/defaults write net.sourceforge.skim-app.skim SKTeXEditorCommand -string ${pkgs.neovim}/bin/nvim
    /usr/bin/defaults write net.sourceforge.skim-app.skim SKTeXEditorArguments -string "--headless -c \"VimtexInverseSearch %line '%file'\""
    /usr/bin/defaults write net.sourceforge.skim-app.skim SKAutoReloadFileUpdate -bool true
    /usr/bin/defaults write net.sourceforge.skim-app.skim SKAutoCheckFileUpdate -bool true
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
