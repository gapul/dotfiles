{ config, pkgs, ... }:
# Polls Apple's Find My network for our own DIY tags (~/Developer/github.com/
# gapul/generic-airtag) and appends what it gets to that repo's reports.db.
#
# Why the mini and not the laptop: a missed poll is a permanent hole (see below),
# and a laptop with its lid shut misses every poll. Why not homeserver: the
# anisette headers Apple demands come from AOSKit, which only exists on macOS —
# a Linux host would need an anisette server fabricating a device identity,
# which is the part of the usual setup this project exists to avoid. The mini
# does not even need to be signed into iCloud; AOSKit answers for the machine,
# not the user.
#
# The search-party token in auth.json is bound to the machine that obtained it:
# copying it here from the laptop returns 401. Each machine logs in once.
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
      # Nothing backfills a gap, so poll immediately after a reboot rather than
      # waiting out the first interval.
      RunAtLoad = true;
      ProcessType = "Background";
      # No log rotation: the script prints one line per run. Errors are the only
      # reason to look, and silence here means the agent never ran at all.
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/findmy-tag.log";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/findmy-tag.log";
    };
  };
}
