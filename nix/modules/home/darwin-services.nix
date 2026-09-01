# Darwin services component (ECS: profile). Resident LaunchAgents / env distribution.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # launchd は素の PATH で起動するので、必要なものを列挙しておく。
  # 経緯: 元は pnpm の global install を使っていたが、その store が消えていた。node も
  # @playwright/mcp も、存在しない store パスを指す symlink になっていて、agent は
  # "exec: node: not found" → "Cannot find module .../cli.js" と順に死んでいた。今は
  # どちらも宣言側から取るので pnpm への依存は無い。PATH を残すのは playwright が
  # 実行時に呼ぶもの (node など) のため。
  mcpPath = lib.concatStringsSep ":" [
    "/run/current-system/sw/bin"
    "/usr/bin"
    "/bin"
  ];
in
{
  # Run resident as a Home Manager LaunchAgent instead of using Syncthing.app.
  # Reuse the existing ~/Library/Application Support/Syncthing config and device ID as-is.
  services.syncthing = {
    enable = true;
    # homeserver 側 (homelab/syncthing.nix) と対になる宣言。ここで書いておくと
    # 追加時に GUI で受け入れる手作業が要らない。
    #
    # **override を両方 false にすること。** 既定は true で、その場合ここに書いた
    # ものが唯一の正になり、GUI で足した既存の folder / device (synchub と iphone)
    # が消える。上のコメントが言っているとおり、この Mac の syncthing 設定は
    # 意図的に宣言化されておらず既存を再利用しているので、そこを壊してはいけない。
    overrideDevices = false;
    overrideFolders = false;
    settings = {
      devices."homeserver".id = "Y72TVZZ-IE3MUPY-3YI6D63-HON47QT-2UYVWHN-5C5N5RY-T2H4ID7-T776ZQF";
      folders."personal-history" = {
        label = "Personal History";
        path = "${config.home.homeDirectory}/Sync/syncthing/personal-history";
        devices = [ "homeserver" ];
        type = "sendreceive";
      };
    };
  };

  # (An ollama serve LaunchAgent was here. This machine never held a single model — inference
  #  runs on the mac mini — so it was a resident daemon with nothing to serve.)

  home.activation.cliServiceLogDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/mkdir -p \
      "${config.home.homeDirectory}/Library/Logs/Syncthing"
  '';

  # One shared Playwright MCP server instead of one per Claude session.
  # The MCP entry in ~/.config/claude/.claude.json used to be `stdio`, which means every session
  # spawns its own server process: measured 2026-08-15 at 15 sessions = 15 node processes, 176MB,
  # and ~120MB each once a session actually drives the browser. All of them attach over CDP to the
  # same browser anyway, so the isolation bought nothing. Listening on a port and pointing every
  # session at it collapses that to one process (70MB idle).
  #
  # Sessions still share the browser, so a parallel run must give each session its own tab
  # (`browser_tabs {action:"new"}` before navigating) — verified: without it two sessions grab the
  # same page and the second navigation wins.
  #
  # localhost-bound by the server itself, and it rejects any request whose Host is not
  # `localhost:8932` (127.0.0.1 in the URL gets a 4xx — write the URL with localhost).
  #
  # There used to be a second instance on 8931 aimed at 9222, for whatever full browser was
  # started for a job. It went away with Chrome: terminal-browser took that role and cannot be
  # driven this way — it does expose CDP, but on a port that changes every launch (measured
  # 53218 → 53337), so no static --cdp-endpoint can find it. It is driven by its own
  # `terminal-browser action` instead. Binary comes from nixpkgs (0.0.69).
  # Playwright MCP, pointed at Lightpanda. Connects lazily, so it costs nothing while idle.
  launchd.agents.playwright-mcp-light = {
    enable = true;
    config = {
      ProgramArguments = [
        "${lib.getExe pkgs.playwright-mcp}"
        "--cdp-endpoint"
        "http://127.0.0.1:9223"
        "--port"
        "8932"
        "--output-dir"
        "${config.home.homeDirectory}/tmp/playwright-mcp-light"
      ];
      EnvironmentVariables.PATH = mcpPath;
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/playwright-mcp-light.err";
      StandardOutPath = "/tmp/playwright-mcp-light.log";
    };
  };

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

  # Codex launched via GUI/IDE doesn't read shell startup files, so
  # also distribute the XDG-aligned Codex home to the launchd user session.
  home.activation.codexLaunchdEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /bin/launchctl setenv CODEX_HOME "${config.xdg.dataHome}/codex"
    /bin/launchctl setenv CODEX_SQLITE_HOME "${config.xdg.stateHome}/codex/sqlite"
  '';
}
