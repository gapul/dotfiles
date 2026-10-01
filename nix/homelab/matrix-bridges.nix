# Matrix bridges. The first wave is only the ones that need no externally prepared credentials.
#
# This could not have been written this way while we were on Conduit. Appservice registrations
# lived inside RocksDB and could only be changed from the admin room, so the only option was to
# hand-place config.yaml in the container. Switching to Synapse made registrations a config
# file, so nixpkgs' services.mautrix-* can be used as-is (see #516).
#
# registerToSynapse defaults to true. The module generates the registration file and adds it
# to services.matrix-synapse.settings.app_service_config_files. All that needs writing here
# is "who connects where".
#
# Not included here:
#   telegram / slack / gmessages / twitter / linkedin
#             — no nixpkgs module (telegram only has the old Python version, and
#               twitter / linkedin have no package either, so they are written in pkgs/).
#               Written in matrix-bridges-v2.nix via mk-matrix-bridgev2.nix.
#   imessage  — no module. Lives on the macmini side (home/macmini-imessage.nix).
#   googlechat — mautrix-googlechat is an old-generation Python bridge; nixpkgs has the package
#               but no module. Its config shape differs from bridgev2, so it is written by hand
#               in matrix-googlechat.nix.
#   google voice — Beeper's implementation is closed (the public beeper/googlevoice was
#               archived in 2023). Nothing we can run ourselves.
#   line      — neither a module nor a package, so both are written by hand (matrix-line.nix).
#   teams     — only an experimental implementation for personal teams.live.com. A company
#               tenant needs an Azure app registration, so it is a question of permission anyway.
#   simplex   — structurally impossible. Its design hinges on having no identifiers, so the
#               stable ID that puppeting needs does not exist.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Synapse listens on 8008 on the same box. The bridges are host units too, so localhost is fine.
  address = "http://127.0.0.1:8008";
  domain = "gapul.net";
  admin = "@gapul:${domain}";

  # The default is permissions = { "*" = "relay" }, which lets anyone use it as a relay.
  # This is a single-user box, so close it.
  permissions = {
    ${admin} = "admin";
  };

  homeserver = {
    inherit address domain;
  };

  # Backfill of past history. This has to be decided **before logging in**.
  #
  # Deep history can only be fetched once, when the portal is first created. The default is
  # 50 messages; going further back later needs the "backfill queue", but upstream's config
  # says:
  #
  #   Settings for the backwards backfill queue. This only applies when connecting to
  #   Beeper as standard Matrix servers don't support inserting messages into history.
  #
  # Plain Synapse cannot insert into the middle of history (MSC2716 was dropped). Only the
  # initial pass, which streams into an empty room in order, works, so take as much as
  # possible there. If you go in with the defaults, redoing it later means deleting the rooms.
  #
  # How much can be fetched depends on the other side, not on settings here:
  #   Telegram / Discord — history is on the server. The deepest backfill
  #   Meta / LinkedIn / Slack — on the server
  #   Signal — only on the device. Mostly what arrives after linking; past history is
  #            basically not available
  # Bridge-side encryption (end-to-bridge encryption).
  #
  # Element / Element X create new DMs encrypted, so without this, commands in DMs with the
  # bridge bots never arrive (on 2026-09-13 the LINE login was rejected with
  # "this bridge has not been configured to support encryption").
  #
  #   allow — works in encrypted rooms too (portals created before 2026-09-26)
  #   default = false — portals we create are plaintext (2026-09-26). On a single home server
  #             the bridge and Synapse are under the same control, so E2BE protects nothing,
  #             and instead it brings a "sender differs from device owner" warning (encrypted
  #             with the bot's device key, so it is always attached to ghost and double-puppet
  #             messages), unreadability via the bot token path, and lost history if the keys
  #             are lost. Existing rooms stay as they are because the Matrix spec does not
  #             allow reverting. The LINE history import also assumes plaintext
  #   require = false — do not reject unencrypted rooms either (existing admin rooms, etc.)
  #   self_sign — Element X does not share keys with unverified devices, so the bridge
  #               cross-signs its own device. Without it, messages sent from Element X are unreadable
  #   msc4190 — the appservice manages its own devices. Usable without an experimental
  #             feature flag since Synapse 1.141 (currently 1.159)
  #
  # pickle_key (the key used when storing keys in the bridge DB) is generated per host by
  # matrix-bridge-secrets.nix. Only mautrix-meta keeps nixpkgs' default fixed value: encryption
  # is already enabled there and keys are in its DB, so changing it would make them undecryptable.
  encryption = {
    allow = true;
    default = false;
    require = false;
    msc4190 = true;
    self_sign = true;
  };

  backfill = {
    enabled = true;
    # 5000 is a compromise between "take as much as we want" and "the initial sync finishes".
    # Upstream also says "higher values take longer because everything is fetched before
    # sending starts".
    max_initial_messages = 5000;
    max_catchup_messages = 5000;
  };
in
{
  # The mautrix bridges depend on libolm, which the Matrix Foundation deprecated in 2024,
  # and nixpkgs marks it insecure.
  #
  # Allowed knowingly. Reasons:
  #   - This libolm is only used for "bridge-side E2EE", which is not enabled here. The
  #     bridges and Synapse talk over localhost on the same box, and the encryption boundary
  #     is on the remote network's side (Discord, Meta), which sees plaintext anyway.
  #   - There were two ways out and neither works. goolm (pure Go implementation) has a
  #     withGoolm flag for signal / meta / slack / gmessages, but the mautrix-discord package
  #     is an old 0.7.7 without the flag, so discord needs the allowance regardless. Switching
  #     just three to an experimental implementation (upstream says "not recommended for
  #     production") leaves the allowlist open and only makes things harder to read.
  #
  # **Revisit this decision when enabling E2EE.** libolm will then actually be in use, so the
  # choice between goolm and containers has to be made again.
  #
  # Addendum 2026-09-14: bridge-side encryption is now enabled, so libolm is actually in use.
  # After revisiting the decision, the allowance stays:
  #   - libolm's known issue is a timing side channel; observing it requires being able to
  #     time the crypto operations. The bridges and Synapse talk over localhost on the same
  #     box, and anyone on that box can already read the DB in plaintext. The boundary being
  #     protected does not change
  #   - upstream does not recommend goolm for production, and mautrix-discord 0.7.7 has no
  #     option at all
  nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

  # Double puppeting for the three nixpkgs-module bridges: the env files come from
  # matrix-bridge-secrets.nix, the modules envsubst "$DOUBLE_PUPPET_SECRET" into the config.
  # Without it the bridges only invite @gapul to portals and the personal space, and own
  # messages sent from the phone show up relayed by the bot.
  services.mautrix-discord = {
    enable = true;
    registerToSynapse = true;
    environmentFile = "/var/lib/matrix-bridge-secrets/discord.env";
    settings = {
      inherit homeserver;
      appservice = {
        id = "discord";
        port = 29334;
        bot.username = "discordbot";
        # nixpkgs' mautrix-discord is 0.7.7, with the pre-bridgev2 config shape.
        # The DB goes in appservice.database, not the top-level database.
        # signal and meta get defaults from the module, but discord's settings default
        # to {}, so without writing it here it keeps restarting with
        # "appservice.database not configured" (actually hit on 2026-08-31).
        database = {
          type = "sqlite3-fk-wal";
          uri = "file:/var/lib/mautrix-discord/mautrix-discord.db?_txlock=immediate";
        };
      };
      bridge = {
        inherit permissions;
        # Number of DM portals created at startup. The default of 5 stops at the 5 most recent,
        # and the rest get no room until the other side sends a message (actually hit on 2026-09-30).
        # 100 covers all existing DMs. Guilds are separate and chosen with `guilds bridge`.
        startup_private_channel_create_limit = 100;
        # Same policy as slack's mute_channels_by_default: guild channel portals start muted,
        # so only DMs and mentions notify (mentions are override push rules and win over the
        # room-level mute). Upstream notes it only mutes for one user, which is all we have.
        mute_channels_on_create = true;
        # mautrix-discord is still a v1 bridge: the key is login_shared_secret_map here.
        login_shared_secret_map.${domain} = "$DOUBLE_PUPPET_SECRET";
        # Old-style config, so encryption also sits under bridge. self_sign does not exist in
        # this version, and there is no pickle_key (old bridges use a fixed value).
        encryption = {
          inherit (encryption)
            allow
            default
            require
            msc4190
            ;
        };
        # discord is 0.7.7, so backfill also uses the old format. Instead of bridgev2's
        # max_initial_messages, DMs / channels / threads are set individually.
        #
        # Channels do not get the same depth as DMs. Guild channels are orders of magnitude
        # larger, so fetching all of them initially means the sync never finishes (upstream also
        # says "higher values take longer because everything is fetched before sending starts").
        backfill = {
          forward_limits = {
            initial = {
              dm = 5000;
              channel = 1000;
              thread = 500;
            };
            # -1 means "everything since the last bridged message". DMs must not miss anything,
            # so unlimited; channels get a cap.
            missed = {
              dm = -1;
              channel = 1000;
              thread = 500;
            };
          };
        };
      };
    };
  };

  services.mautrix-signal = {
    enable = true;
    registerToSynapse = true;
    environmentFile = "/var/lib/matrix-bridge-secrets/signal.env";
    settings = {
      inherit homeserver backfill;
      encryption = encryption // {
        pickle_key = "$ENCRYPTION_PICKLE_KEY";
      };
      double_puppet.secrets.${domain} = "$DOUBLE_PUPPET_SECRET";
      bridge = { inherit permissions; };
    };
  };

  # WhatsApp. Log in by sending `login` to the bot → scan the QR with WhatsApp's "Linked
  # devices" on the phone. History comes from the device via history sync (request_full_sync
  # defaults to true in the module). The port is the module default 29318.
  services.mautrix-whatsapp = {
    enable = true;
    registerToSynapse = true;
    environmentFile = "/var/lib/matrix-bridge-secrets/whatsapp.env";
    settings = {
      inherit homeserver backfill;
      encryption = encryption // {
        pickle_key = "$ENCRYPTION_PICKLE_KEY";
      };
      double_puppet.secrets.${domain} = "$DOUBLE_PUPPET_SECRET";
      bridge = { inherit permissions; };
    };
  };

  # nixpkgs' whatsapp module creates the registration file in the main unit's preStart, and that
  # unit starts after Synapse. On the first deploy Synapse reads a nonexistent registration file
  # and crashes, and restarts at 100ms intervals hit StartLimitBurst=5 and stop (the pattern hit
  # with LINE on 2026-09-13; same fix as mk-matrix-bridgev2.nix). A oneshot that only creates the
  # registration is placed before Synapse. The main preStart is "create if missing", so nothing
  # is generated twice.
  systemd.services.mautrix-whatsapp-registration =
    let
      dataDir = "/var/lib/mautrix-whatsapp";
      registrationFile = "${dataDir}/whatsapp-registration.yaml";
      # Generating the registration only needs the appservice id / bot / port. The env var
      # placeholders go in as-is but are not read during registration generation.
      settingsFile =
        (pkgs.formats.json { }).generate "mautrix-whatsapp-registration-config.json"
          config.services.mautrix-whatsapp.settings;
    in
    {
      description = "Generate the mautrix-whatsapp appservice registration before Synapse starts";
      before = [ config.services.matrix-synapse.serviceUnit ];
      wantedBy = [ config.services.matrix-synapse.serviceUnit ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "mautrix-whatsapp";
        Group = "mautrix-whatsapp";
        StateDirectory = baseNameOf dataDir;
        WorkingDirectory = dataDir;
      };
      # --generate-registration writes the tokens back into the config it was given, so
      # it must not point at the store (2026-09-29: "read-only file system", the unit
      # failed after writing a 0600 registration and Synapse got EACCES once). Work on
      # a throwaway copy, and create the registration as 0640 directly (umask 0137)
      # so there is no window where Synapse can see it unreadable.
      script = ''
        if [ ! -f '${registrationFile}' ]; then
          umask 0137
          cp '${settingsFile}' '${dataDir}/registration-config.yaml'
          ${lib.getExe config.services.mautrix-whatsapp.package} \
            --generate-registration \
            --config='${dataDir}/registration-config.yaml' \
            --registration='${registrationFile}'
          rm -f '${dataDir}/registration-config.yaml'
        fi
        chmod 640 '${registrationFile}'
      '';
    };

  # Fix two upstream bugs in Instagram's older-chat import (doChatBackfill in
  # pkg/igconnector/chatsync.go, v0.2609.0, read on 2026-10-01). Messenger takes a different
  # path (pkg/connector/threadbackfill.go) that has neither.
  #   1. The loop is `for batchCount < BatchCount`, so batch_count = -1 (unlimited, also the
  #      upstream default) means zero extra pages: it takes the first inbox page and sets
  #      BackfillCompleted. That is why the first login only produced 15 chats.
  #   2. startCursor is never advanced inside the loop, so a positive count re-fetches the same
  #      second page over and over.
  # BackfillCompleted lives in the login's metadata, so log in again after this lands.
  services.mautrix-meta.package = pkgs.mautrix-meta.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace pkg/igconnector/chatsync.go \
        --replace-fail \
          'for batchCount < ic.Main.Config.ThreadBackfill.BatchCount {' \
          'for ic.Main.Config.ThreadBackfill.BatchCount < 0 || batchCount < ic.Main.Config.ThreadBackfill.BatchCount {' \
        --replace-fail \
          'if !resp.Mailbox.ThreadsByFolder.PageInfo.HasNextPage {' \
          'startCursor = resp.Mailbox.ThreadsByFolder.PageInfo.EndCursor; if !resp.Mailbox.ThreadsByFolder.PageInfo.HasNextPage {'
    '';
  });

  # Instagram and Messenger are separate instances of the same mautrix-meta, split by
  # network.mode. Always use distinct ports, appservice.id and bot names (if they match, one
  # registration overwrites the other and only the one added later works).
  services.mautrix-meta.instances = {
    instagram = {
      enable = true;
      registerToSynapse = true;
      environmentFile = "/var/lib/matrix-bridge-secrets/instagram.env";
      settings = {
        inherit homeserver;
        inherit backfill encryption;
        double_puppet.secrets.${domain} = "$DOUBLE_PUPPET_SECRET";
        network = {
          mode = "instagram";
          # Older conversations are fetched page by page after the initial sync. Left
          # unset the bridge saw batch_count = 0 and never started (no "Starting thread
          # backfill" in the log after the 2026-10-01 login; only the first inbox page,
          # 15 chats, got portals). Upstream's own defaults, written out explicitly.
          thread_backfill = {
            batch_count = -1;
            batch_delay = "2s";
          };
        };
        appservice = {
          id = "instagram";
          port = 29320;
          bot.username = "instagrambot";
        };
        bridge = { inherit permissions; };
      };
    };

    messenger = {
      enable = true;
      registerToSynapse = true;
      environmentFile = "/var/lib/matrix-bridge-secrets/messenger.env";
      settings = {
        inherit homeserver;
        inherit backfill encryption;
        double_puppet.secrets.${domain} = "$DOUBLE_PUPPET_SECRET";
        network = {
          mode = "messenger";
          # Same as instagram above.
          thread_backfill = {
            batch_count = -1;
            batch_delay = "2s";
          };
        };
        appservice = {
          id = "messenger";
          port = 29321;
          bot.username = "messengerbot";
        };
        bridge = { inherit permissions; };
      };
    };
  };
}
