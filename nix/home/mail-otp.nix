{ config, pkgs, ... }:
# Verification codes arriving by mail land on the clipboard with a notification
# (configs/cli/mail-otp/watch.py). macOS' own version only feeds Safari from
# Mail.app; this one works for whatever browser has the form open.
#
# Accounts are read from aerc's accounts.conf, so only Gmail today. The Stalwart
# mirrors (mail.gapul.net) are copied hourly and would be an hour late.
{
  launchd.agents.mail-otp = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "${../../configs/cli/mail-otp/watch.py}"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mail-otp.log";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mail-otp.log";
    };
  };
}
