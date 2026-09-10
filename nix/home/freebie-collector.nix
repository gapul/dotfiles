{
  config,
  lib,
  pkgs,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  collector = "${config.home.homeDirectory}/.local/bin/freebie-collector";
  repo = "${config.home.homeDirectory}/Documents/assets";
in
{
  home.file.".local/bin/freebie-collector" = {
    source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/freebie-collector/collector.py";
    executable = true;
  };
  xdg.configFile."freebie-collector/sources.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/configs/macmini/freebie-collector/sources.json";

  home.activation.freebieCollectorDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /bin/mkdir -p \
      "${config.home.homeDirectory}/.local/state/freebie-collector" \
      "${config.home.homeDirectory}/Downloads/freebie-inbox"
  '';

  launchd.agents.freebie-collector = import ../lib/launchd-agent.nix {
    program = "${pkgs.writeShellScript "freebie-collector-run" ''
      export PATH="${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
      if [ ! -d "${repo}/.git" ]; then
        /bin/mkdir -p "$(/usr/bin/dirname "${repo}")"
        git clone "ssh://gapul@homeserver/srv/annex/assets.git" "${repo}" || exit 1
        cd "${repo}"
        git annex init "macmini"
      fi
      exec ${pkgs.python3}/bin/python3 "${collector}" run
    ''}";
    schedule = [
      {
        Hour = 8;
        Minute = 15;
      }
      {
        Hour = 20;
        Minute = 15;
      }
    ];
    longRunning = true;
  };
}
