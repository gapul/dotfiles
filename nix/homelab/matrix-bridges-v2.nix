# bridgev2 bridges without a nixpkgs module, built on mk-matrix-bridgev2.nix.
# Log in by DMing the bot (@<id>bot:gapul.net) and sending `login`.
#
# Ports sit next to the others in matrix-bridges.nix / matrix-line.nix
# (discord 29334, instagram 29320, messenger 29321, signal 29328, line 29340).
{
  imports = [
    # Slack. Log in with a token + cookie from the browser (d / xoxc-) or with
    # email/password. Slack keeps history server-side, so backfill goes deep.
    (import ./mk-matrix-bridgev2.nix {
      name = "mautrix-slack";
      id = "slack";
      title = "Slack";
      package = pkgs: pkgs.mautrix-slack;
      port = 29335;
    })

    # Google Messages (SMS/RCS via an Android phone). Pairs like Messages for
    # Web, so the phone must stay online; history comes from the phone.
    (import ./mk-matrix-bridgev2.nix {
      name = "mautrix-gmessages";
      id = "gmessages";
      title = "Google Messages";
      package = pkgs: pkgs.mautrix-gmessages;
      port = 29336;
    })

    # Telegram. Needs an app's api_id / api_hash from https://my.telegram.org/apps,
    # placed as root-owned /var/lib/secrets/mautrix-telegram.env:
    #
    #   TELEGRAM_API_ID=<api_id>
    #   TELEGRAM_API_HASH=<api_hash>
    #
    # then `systemctl restart mautrix-telegram-config mautrix-telegram`.
    (import ./mk-matrix-bridgev2.nix {
      name = "mautrix-telegram";
      id = "telegram";
      title = "Telegram";
      package = pkgs: pkgs.callPackage ../pkgs/mautrix-telegram.nix { };
      port = 29317;
      # Animated stickers are converted to gif.
      extraPath = pkgs: [ pkgs.lottieconverter ];
      secretsFile = "/var/lib/secrets/mautrix-telegram.env";
      secretsJq = ''

        | .[0].network.api_id = (env.TELEGRAM_API_ID // "0" | tonumber)
        | .[0].network.api_hash = (env.TELEGRAM_API_HASH // "")'';
    })
  ];
}
