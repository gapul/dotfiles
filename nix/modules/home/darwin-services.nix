# Darwin services component (ECS: profile). Resident LaunchAgents / env distribution.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # launchd starts with almost nothing on PATH, so the agents that shell out to other binaries
  # get this. The ask broker looks up `bw` and `terminal-browser` at runtime rather than baking in
  # store paths, so both have to be findable here.
  #
  # (This used to carry a long note about pnpm's global store having gone stale under the
  #  Playwright MCP agent. That agent is gone; the note went with it.)
  agentPath = lib.concatStringsSep ":" [
    "/run/current-system/sw/bin"
    "${config.home.homeDirectory}/.local/state/nix/profile/bin"
    "/usr/bin"
    "/bin"
  ];

  # Runtime for the ask broker. mcp is the official SDK (FastMCP lives inside it) and websockets
  # is what talks CDP to the browser — values are typed over the wire rather than handed to a
  # command, because `ps` shows another process's arguments to the same user.
  askPython = pkgs.python3.withPackages (ps: [
    ps.mcp
    ps.websockets
    ps.uvicorn
  ]);
in
{
  home.file.".local/bin/ask-native-fill".source = ../../../configs/ask/native_fill.py;

  # Run resident as a Home Manager LaunchAgent instead of using Syncthing.app.
  # Reuse the existing ~/Library/Application Support/Syncthing config and device ID as-is.
  services.syncthing = {
    enable = true;
    # Declaration paired with the homeserver side (homelab/syncthing.nix). Writing it here removes the
    # manual step of accepting it in the GUI when adding.
    #
    # **Set both overrides to false.** The default is true, in which case what is written here becomes
    # the sole source of truth and the existing folders / devices added in the GUI (synchub and iphone)
    # disappear. As the comment above says, this Mac's syncthing config is deliberately not declared
    # and reuses the existing one, so that must not be broken.
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
      # Outside ~/Sync/syncthing on purpose: that directory is the synchub folder, and nesting
      # the inbox inside it would ship every PDF to the iPhone share as well. Transient, so
      # restic not covering it is fine.
      folders."paperless-inbox" = {
        label = "Paperless Inbox";
        path = "${config.home.homeDirectory}/Sync/paperless-inbox";
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

  # (A resident Playwright MCP server lived here, on 8932, attached over CDP to Lightpanda on
  #  9223. Removed 2026-09-10, having been broken the whole time and unmissed: the MCP entry in
  #  ~/.config/claude/.claude.json pointed at 8931 while the agent listened on 8932, so nothing
  #  ever connected, and Lightpanda was never started at all because no agent declared it.
  #
  #  It is not being repaired, for two reasons. The everyday Chromium path is agent-browser, which
  #  ships inside terminal-browser and represents a page in 200-400 tokens where the MCP protocol
  #  carries the accessibility tree in-context on every turn — measured upstream at 114k tokens
  #  against 27k for the same task. And the cross-browser case, which is the one thing Playwright
  #  genuinely has over agent-browser, did not work in this shape anyway: `--cdp-endpoint` attaches
  #  to an existing Chromium, so Firefox and WebKit were never reachable through it.
  #
  #  Cross-browser testing now runs on demand through the `playwright-test` wrapper below rather
  #  than from a daemon, because it is an occasional job and a daemon nobody notices is broken is
  #  worse than no daemon.)

  # ask broker: holds the Bitwarden session, asks the human, and does the typing, so that a
  # password never has to be pasted into a conversation with an agent. Protocol and reasoning in
  # docs/ask-protocol.md; the iPhone and Watch client that answers away from the desk is in
  # github.com/gapul/ask.
  #
  # Bound to 127.0.0.1 to start with. It is meant to listen on the tailnet as well, so an agent
  # working on the mac mini reaches this same broker, but local-only is the right default until
  # that is actually wanted — the thing holds a vault session.
  #
  # No sops secrets declared yet on purpose: the Bitwarden password and the Matrix token do not
  # exist in secrets/darwin.yaml yet, and declaring a secret that is not there fails activation.
  # The broker reads ~/.config/ask/broker.toml, which is hand-made from config.example.toml, and
  # degrades rather than dying when neither is configured: elicitation still works, login_fill
  # refuses. Move the config into sops.templates once the values are in.
  launchd.agents.ask-broker = {
    enable = true;
    config = {
      ProgramArguments = [
        "${askPython}/bin/python3"
        "${../../../configs/ask/ask_broker.py}"
      ];
      # bw and terminal-browser are both looked up at runtime rather than baked in, so they have
      # to be on the agent's PATH; launchd starts with almost nothing.
      EnvironmentVariables.PATH = agentPath;
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/ask-broker.err";
      StandardOutPath = "/tmp/ask-broker.log";
    };
  };

  # Reverse tunnel to the work machine (sean 127.0.0.1:2222 -> this Mac's 22); the Host
  # sean-revtunnel entry in ssh_config carries the forward and the keepalives. Its own
  # connection rather than a RemoteForward on mvrx-nolang-dev: on the shared mux master the -R
  # is tried once when the master starts, a failure is ignored, and nothing retries it
  # (2026-10-02). A dead link makes ssh exit within ~90s and KeepAlive brings it back.
  # ThrottleInterval: off the network ssh exits immediately, so this is the retry pace.
  launchd.agents.sean-revtunnel = {
    enable = true;
    config = {
      ProgramArguments = [
        "/usr/bin/ssh"
        "-N"
        "sean-revtunnel"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/sean-revtunnel.err";
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
