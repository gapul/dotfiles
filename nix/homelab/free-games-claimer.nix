{
  # Automatically claims free giveaways on Epic / Prime Gaming / Steam. Added to CT101 on 2026-08-09,
  # too late for the compose2nix bulk conversion, so it was left out of the declarations during the migration.
  #
  # The image is pinned by digest, not tag. It points at a build verified against commit 4fc0849 of the
  # public repo, with a matching sha256 for src/package.json. Since it holds store login credentials and
  # automates them, always read the diff before swapping it on update.
  # Do not go back to :latest.
  virtualisation.oci-containers.containers.fgc = {
    image = "ghcr.io/feldorn/free-games-claimer@sha256:640b1769d126c2272d664647bfeffa8b513d1025795ddb7791f91b2a7a1df5a6";
    volumes = [ "free-games-claimer_fgc:/fgc/data:rw" ];
    environment = {
      TZ = "Asia/Tokyo";
      LANG = "ja_JP.UTF-8";
      # microsoft.js (Bing Rewards) and gog.js are deliberately left out: the former is a ban risk, the
      # latter won't run without GOG_OTP_BACKUP_CODES in place.
      # fab.js is Epic's 3D assets (Limited-Time Free on fab.com). Auth is Epic OAuth, reusing the same
      # browser profile and credentials as epic-games.js.
      # Order matters: placed right after epic-games.js, the SSO session is still warm, so no second
      # login is needed.
      CLAIM_CMD = "prime-gaming.js; epic-games.js; fab.js; steam.js";
      CLAIM_CMD_MANUAL = "prime-gaming.js; epic-games.js; fab.js; steam.js";
      # fab.js does not run just by being in CLAIM_CMD. Its site definition is opt-in
      # (defaultActive=false), so without this it stays inactive in the panel.
      FAB_ACTIVE = "1";
      LOOP = "86400";
      START_TIME = "09:00";
      RUN_ON_STARTUP = "0";
      # Microsoft Rewards explicitly disabled. Merely removing it from CLAIM_CMD still has the scheduler
      # check the session every morning, and in fact the 2026-08-16 run touched it as logged in.
      # Automated point collection is an area where Microsoft actually suspends accounts, so err on the
      # side of not touching it.
      MS_ACTIVE = "0";
      MS_MOBILE_ACTIVE = "0";

      # Watchers that only notify without claiming. They involve no login, so no account risk,
      # and adding more has almost no side effects.
      UBISOFT_ACTIVE = "1";
      HUMBLE_ACTIVE = "1";
      FANATICAL_ACTIVE = "1";
      LENOVO_ACTIVE = "1";
      # IndieGala opens the freebies page in a real browser without login and diffs it.
      # PSN and Xbox don't even use a browser; they just query GamerPower's public API.
      # PS Plus monthly games and Xbox Free Play Days show up here.
      INDIEGALA_ACTIVE = "1";
      PSN_ACTIVE = "1";
      XBOX_ACTIVE = "1";
      NOTIFY_TITLE = "free-games";
      NOTIFY_LEVEL = "actions";
      # It still pointed at the old host's IP, so moved to the new host.
      PUBLIC_URL = "http://192.168.116.98:7080";
    };
    # NOTIFY (ntfy publish URL) and PANEL_PASSWORD. The latter is also used for VNC_PASSWORD.
    environmentFiles = [ "/var/lib/secrets/free-games-claimer.env" ];
    ports = [
      "6080:6080" # noVNC. Entry point for doing the first login to each store by hand
      "7080:7080" # Control panel
    ];
    log-driver = "journald";
    extraOptions = [ "--network-alias=fgc" ];
  };
}
