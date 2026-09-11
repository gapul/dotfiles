# Antigravity CLI component (ECS: profile). Google's terminal agent, `agy`.
#
# This is how a second model is reached from here. Not the browser: signing in to Gemini through
# an automated browser does not work, and was tried — Google returns the sign-in flow to its first
# step for anything driven over CDP, whatever the password is. And not gemini-cli, which was also
# tried and is over: it answers "this client is no longer supported" after authenticating, at any
# version, and nixpkgs marks it for removal for the same reason. Auth is the account's own OAuth
# (one interactive `agy` per machine), which is what the AI Pro subscription applies to.
#
# The rolling agents lineage on purpose: Google refuses old clients outright, so pinning this
# particular tool would only decide in advance the day it stops working.
{
  config,
  lib,
  pkgs,
  nixpkgsAgents,
  ...
}:
let
  agentPkgs = import ../../lib/unstable-pkgs.nix {
    nixpkgsUnstable = nixpkgsAgents;
    inherit (pkgs.stdenv.hostPlatform) system;
  };

  # Declared keys only. Pro rather than Flash by default because this is the tool reached for a
  # second opinion, where the answer matters more than what it costs; `--model` picks another per
  # call (`agy models` lists them, Claude and gpt-oss included).
  settings = {
    model = "gemini-3.1-pro-high";
    enableTelemetry = false;
  };

  wanted = pkgs.writeText "agy-settings.json" (builtins.toJSON settings);
  settingsFile = "${config.home.homeDirectory}/.gemini/antigravity-cli/settings.json";
in
{
  home.packages = [ agentPkgs.antigravity-cli ];

  # Merged rather than linked: agy owns this file and writes to it as it runs (every directory
  # trusted lands here). A read-only store symlink would be a file it cannot update, so the keys
  # declared above are merged into whatever it already has, and everything else is left alone.
  home.activation.agySettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 - <<'PY'
    import json, pathlib

    target = pathlib.Path("${settingsFile}")
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        current = json.loads(target.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        current = {}
    merged = {**current, **json.loads(pathlib.Path("${wanted}").read_text())}
    if merged != current:
        target.write_text(json.dumps(merged, indent=2) + "\n")
    PY
  '';
}
