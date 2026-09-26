{ pkgs, ... }:
# Keep Mail.app running so macOS can offer verification codes from mail as
# AutoFill (system-wide since macOS 26, so it reaches Zen as well as Safari).
# The codes are only detected in mail that Mail.app itself has received, and
# Mail.app only fetches while it is running — which it never was here, since
# mail is read in aerc. Launch it hidden at login and leave it there.
#
# This replaced a homegrown IMAP watcher (mail-otp, PR #772) that copied codes
# to the clipboard: one mechanism is enough, and the native one needs no code.
{
  launchd.agents.mail-app = {
    enable = true;
    config = {
      ProgramArguments = [
        "/usr/bin/open"
        "-gj" # background, hidden: no window steals focus at login
        "-a"
        "Mail"
      ];
      RunAtLoad = true;
      # Bring it back if it gets quit; `open` on a running app with -g is a no-op.
      StartInterval = 600;
      ProcessType = "Background";
    };
  };
}
