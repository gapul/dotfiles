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
  # same Chrome on 9222 anyway, so the isolation bought nothing. Listening on 8931 and pointing
  # every session at `http://localhost:8931/mcp` collapses that to one process (70MB idle).
  #
  # Sessions still share the browser, so a parallel run must give each session its own tab
  # (`browser_tabs {action:"new"}` before navigating) — verified: without it two sessions grab the
  # same page and the second navigation wins.
  #
  # localhost-bound by the server itself, and it rejects any request whose Host is not
  # `localhost:8931` (127.0.0.1 in the URL gets a 4xx — write the URL with localhost).
  # The connection to Chrome is lazy, so this stays cheap while Chrome is down, which is the
  # normal state: Chrome is started only for a job (see CLAUDE.md) and killed after.
  # Binary comes from nixpkgs (0.0.69). It used to be the pnpm global install, but that store
  # evaporated: both ~/Library/pnpm/bin/node and the @playwright/mcp package were symlinks into
  # store paths that no longer exist, so the agent died with "node: not found" and then
  # "Cannot find module .../cli.js". npm's latest is 0.0.79 — a patch ahead, which is a cheap
  # price for not depending on a global store nothing declares.
  # Lightpanda: the cheap CDP target for background work. 19MB resident against Chrome's 296MB
  # (both measured here), so unlike Chrome this one can just stay up — there is no "start it for
  # the job and kill it after" dance. Chrome stays the exception, for logins, captchas and the
  # SPAs Lightpanda renders empty.
  launchd.agents.lightpanda = {
    enable = true;
    config = {
      ProgramArguments = [
        "/run/current-system/sw/bin/lp"
        "serve"
        # 9333 ではない。あそこには別に立てたヘッドレス Chrome が既に居て
        # (/json/version が Chrome/152 を返す)、Lightpanda が AddressInUse で
        # 起動できなかった。9223 は 9222 の実 Chrome の隣という意味。
        "--port"
        "9223"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/lightpanda.err";
      StandardOutPath = "/tmp/lightpanda.log";
    };
  };

  # Second playwright-mcp, pointed at Lightpanda instead of Chrome. Two instances rather than
  # switching one: the Chrome-backed 8931 keeps working exactly as before, and the caller picks
  # a port instead of a mode. Both connect lazily, so an idle one costs nothing.
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

  launchd.agents.playwright-mcp = {
    enable = true;
    config = {
      ProgramArguments = [
        "${lib.getExe pkgs.playwright-mcp}"
        "--cdp-endpoint"
        "http://127.0.0.1:9222"
        "--port"
        "8931"
        "--output-dir"
        "${config.home.homeDirectory}/tmp/playwright-mcp"
      ];
      EnvironmentVariables.PATH = mcpPath;
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/playwright-mcp.err";
      StandardOutPath = "/tmp/playwright-mcp.log";
    };
  };

  # Shell-independent env distribution: GUI apps / processes under launchd don't go through
  # zsh's .zshenv (hm-session-vars.sh is effectively only read by zsh), so they receive none of
  # home.sessionVariables' env. The most notable case is the accident where an unset GNUPGHOME makes
  # gpg regenerate an empty ~/.gnupg, but EDITOR/PAGER/various telemetry opt-outs/XDG bases/CARGO_HOME etc.
  # are also missed on the GUI side. At login, push them into the whole session via launchctl setenv to cut the zsh dependency.
  #
  # Auto-generated from home.sessionVariables rather than hardcoded (single source, drift prevention).
  # Values are made safe with escapeShellArg (handles values with spaces/quotes like MANPAGER).
  # Variables whose value contains "$" (e.g. the TERMINFO_DIRS that home-manager injects,
  # "...:$TERMINFO_DIRS${TERMINFO_DIRS:+:}...") assume shell expansion at export time and
  # break under the non-expanding launchctl setenv (a literal $ gets in), so they're excluded and left to zsh.
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
