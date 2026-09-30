# bridgev2 bridges without a nixpkgs module, built on mk-matrix-bridgev2.nix.
# Log in by DMing the bot (@<id>bot:gapul.net) and sending `login`.
#
# Ports sit next to the others in matrix-bridges.nix / matrix-line.nix
# (discord 29334, instagram 29320, messenger 29321, signal 29328, line 29340).
# twitter / linkedin use the upstream defaults (29327 / 29329); bluesky has no
# upstream default worth keeping, so it takes the next free slot (29337); email likewise (29338).
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
      # Every workspace in full (channels + DMs), but channel portals start muted so
      # only DMs and mentions notify (mentions are override push rules, which win
      # over the room-level mute). Applies to portals created after this lands.
      network.mute_channels_by_default = true;
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

    # X (Twitter). Log in with the auth_token + ct0 cookies from a logged-in
    # browser session (`login` → cookies). DMs only; history sits on X's side,
    # so backfill goes deep.
    (import ./mk-matrix-bridgev2.nix {
      name = "mautrix-twitter";
      id = "twitter";
      title = "X";
      package = pkgs: pkgs.callPackage ../pkgs/mautrix-twitter.nix { };
      port = 29327;
      # Call it X in bridge info and the management room welcome.
      network.x = true;
    })

    # LinkedIn. Log in with the li_at + JSESSIONID cookies from a logged-in
    # browser session (`login` → cookies). Messaging only.
    (import ./mk-matrix-bridgev2.nix {
      name = "mautrix-linkedin";
      id = "linkedin";
      title = "LinkedIn";
      package = pkgs: pkgs.callPackage ../pkgs/mautrix-linkedin.nix { };
      port = 29329;
      # Upstream creates portals for the 10 most recent chats only; take them all
      # so the first sync matches the backfill policy of the other bridges.
      network.sync.create_limit = 0;
    })
    # Bluesky (DMs only). Log in with the handle and an app password from
    # Settings → Privacy and security → App passwords; the main password works
    # too but an app password can be revoked on its own.
    (import ./mk-matrix-bridgev2.nix {
      name = "mautrix-bluesky";
      id = "bluesky";
      title = "Bluesky";
      package = pkgs: pkgs.callPackage ../pkgs/mautrix-bluesky.nix { };
      port = 29337;
    })

    # Email over IMAP (matrimail): one email thread = one room, IMAP IDLE for
    # delivery, replies/compose over SMTP submission (587) or the Gmail API.
    # Postmoogle would have been the obvious choice but it is an SMTP server
    # that must be reachable on port 25, and the home line is OP25B (mail.nix).
    # Log in with `login` → email + app password (Google accounts: the same app
    # passwords mail.nix uses for imapsync), then pick folders/labels to watch.
    (import ./mk-matrix-bridgev2.nix {
      name = "matrimail";
      id = "email";
      title = "Email";
      package = pkgs: pkgs.callPackage ../pkgs/matrimail.nix { };
      port = 29338;
      network = {
        # Upstream default is 3 minutes / 25 mails at startup. Take a day so a
        # bridge restart never loses mail; older history stays in Stalwart.
        imap = {
          startup_backfill_seconds = 86400;
          startup_backfill_max = 500;
        };
      };
    })
  ];
}
