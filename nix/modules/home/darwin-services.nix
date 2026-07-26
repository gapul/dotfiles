# Darwin services component (ECS: profile)。常駐 LaunchAgent / env 配布。
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Syncthing.app を使わず、Home Manager の LaunchAgent として常駐させる。
  # 既存の ~/Library/Application Support/Syncthing の設定・デバイスIDをそのまま使う。
  services.syncthing.enable = true;

  # Ollama.app のメニューバー常駐を、Nix版 ollama の LaunchAgent に置き換える。
  launchd.agents.ollama = {
    enable = true;
    # 起動仕様は nix/lib/ollama-agent.nix が SSO (macmini と共有)。差分だけ付ける。
    config = (import ../../lib/ollama-agent.nix { inherit pkgs; }) // {
      ProcessType = "Background";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/Ollama/ollama.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/Ollama/ollama.log";
    };
  };

  home.activation.cliServiceLogDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.home.homeDirectory}/Library/Logs/Ollama" \
      "${config.home.homeDirectory}/Library/Logs/Syncthing"
  '';

  # シェル非依存の env 配布: GUI アプリ / launchd 配下プロセスは zsh の .zshenv
  # (hm-session-vars.sh の読み手は実質 zsh のみ) を経由しないため、home.sessionVariables
  # の env を一切受け取れない。最も顕著なのは GNUPGHOME 未設定で gpg が空の ~/.gnupg を
  # 再生成する事故だが、EDITOR/PAGER/各種 telemetry opt-out/XDG 基底/CARGO_HOME 等も
  # GUI 側で取り逃す。ログイン時に launchctl setenv で session 全体へ流し込み zsh 依存を断つ。
  #
  # ハードコードせず home.sessionVariables から自動生成 (単一ソース・ドリフト防止)。
  # 値は escapeShellArg で安全化 (MANPAGER 等の空白/引用符を含む値に対応)。
  # 値に "$" を含む変数 (例: home-manager が注入する TERMINFO_DIRS の
  # "...:$TERMINFO_DIRS${TERMINFO_DIRS:+:}...") は export 時のシェル展開前提であり、
  # 展開しない launchctl setenv では壊れる (リテラル $ が入る) ため除外し zsh に委ねる。
  launchd.agents.session-env = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        (lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: value: "launchctl setenv ${name} ${lib.escapeShellArg (toString value)}"
          ) (lib.filterAttrs (_: value: !lib.hasInfix "$" (toString value)) config.home.sessionVariables)
        ))
      ];
      RunAtLoad = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/session-env.err";
      StandardOutPath = "/tmp/session-env.out";
    };
  };

  # GUI/IDE 経由で起動する Codex は shell startup file を読まないため、
  # launchd user session にも XDG 寄せした Codex home を配る。
  home.activation.codexLaunchdEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/launchctl setenv CODEX_HOME "${config.xdg.dataHome}/codex"
    /bin/launchctl setenv CODEX_SQLITE_HOME "${config.xdg.stateHome}/codex/sqlite"
  '';
}
