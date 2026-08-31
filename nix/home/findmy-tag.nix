{ config, pkgs, ... }:
# Polls Apple's Find My network for our own DIY tags (~/Developer/github.com/
# gapul/generic-airtag) and appends what it gets to that repo's reports.db.
#
# Why every 10 minutes and not, say, hourly: the fetch endpoint ignores the date
# range in the request and returns only the newest handful of reports per key —
# 8, measured on this account. Reports older than that stop being served long
# before Apple's 7-day retention expires, so whatever a poll does not save is
# lost for good. A tag being seen continuously produces roughly 8 reports per 15
# minutes, which is what sets the interval.
let
  repo = "${config.home.homeDirectory}/Developer/github.com/gapul/generic-airtag";

  # The devShell's python, rebuilt here so launchd does not have to evaluate a
  # flake (and reach the network) every ten minutes. Keep in sync with the
  # repo's flake.nix; srp/pbkdf2/pycryptodome are only needed by the vendored
  # GSA login, which runs on the first login and never again.
  python = pkgs.python3.withPackages (ps: [
    ps.requests
    ps.cryptography
    ps.pyobjc-core # AOSKit, for anisette generated on this Mac
    ps.pyobjc-framework-Cocoa
    ps.srp
    ps.pbkdf2
    ps.pycryptodome
  ]);

  # Exits quietly when the repo is absent or nobody has logged in yet, so the
  # agent is harmless on a machine where this project was never set up.
  poll = pkgs.writeShellScript "findmy-tag-poll" ''
    [ -d "${repo}" ] || exit 0
    [ -r "${repo}/auth.json" ] || exit 0
    cd "${repo}" && exec ${python}/bin/python src/fetch.py
  '';
in
{
  launchd.agents.findmy-tag = {
    enable = true;
    config = {
      ProgramArguments = [ "${poll}" ];
      StartInterval = 600;
      # A poll missed while the laptop was asleep is a gap in the history that
      # cannot be backfilled, so fetch immediately on wake/login too.
      RunAtLoad = true;
      ProcessType = "Background";
      # No log rotation: the script prints one line per run. Errors are the only
      # reason to look, and silence here means the agent never ran at all.
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/findmy-tag.log";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/findmy-tag.log";
    };
  };
}
