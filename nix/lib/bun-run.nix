# How every Bun script in this repo is started. Plain `bun script.ts` reads `.env*` and
# `bunfig.toml` from the working directory (bunfig can `preload` arbitrary code) and installs a
# missing import from npm on the fly. For a service or CLI the working directory is whatever the
# caller had, e.g. a CI checkout on the macmini runner, so a file left there could inject
# environment (tokens, API endpoints) or code into a process that holds credentials. These flags
# turn all three off; scripts only import node: builtins and siblings, so nothing else changes.
{ pkgs }:
rec {
  argv = [
    "${pkgs.bun}/bin/bun"
    "--no-env-file"
    "--config=${pkgs.writeText "bunfig.toml" ""}"
    "--no-install"
  ];
  # For ExecStart / script / launchd command strings. Store paths contain no spaces.
  cmd = builtins.concatStringsSep " " argv;
}
