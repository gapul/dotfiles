# Darwin services component (ECS: profile). Resident LaunchAgents / env distribution.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Run resident as a Home Manager LaunchAgent instead of using Syncthing.app.
  # Reuse the existing ~/Library/Application Support/Syncthing config and device ID as-is.
  services.syncthing.enable = true;

  # Replace Ollama.app's menu-bar resident with a LaunchAgent for the Nix ollama.
  launchd.agents.ollama = {
    enable = true;
    # The launch spec is the SSO in nix/lib/ollama-agent.nix (shared with macmini). Add only the diffs.
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
