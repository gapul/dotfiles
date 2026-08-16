{
  config,
  pkgs,
  mopidyPatches,
  ...
}:
# Mopidy stack for low-heat YouTube Music playback in the terminal.
# - Drop browser playback (video decoding + WindowServer compositing generate heat) and play audio only via GStreamer.
# - Account integration (library/mixes/radio = discovering new tracks) via mopidy-ytmusic + ytmusicapi.
# - Playback history is logged to ListenBrainz via mopidy-listenbrainz (continuing the previous setup).
# - Control from the MPD client rmpc (127.0.0.1:6600 is the default connection target).
#
# Vanilla nixpkgs mopidy-ytmusic 0.3.9 / mopidy-listenbrainz 0.3.0 don't work as-is against current YouTube/LB,
# so two patches are applied at build time (configs/media/mopidy/*.py):
#   1. ytdlp-patch.py     : swap stream resolution from the broken pytube cipher to yt-dlp
#   2. lb-patch.py        : fix the bug where sending an empty release_name causes a 400
let
  home = config.home.homeDirectory;

  # The runtime bundling core + extensions + patches is centralized in nix/lib/mopidy-env.nix (shared with the test mirror).
  mopidyEnv = import ../lib/mopidy-env.nix {
    inherit pkgs;
    patchDir = mopidyPatches;
  };

  confPath = "${home}/.config/mopidy/mopidy.conf";

  # The YouTube session cookies rotate every few hours, so the auth file has to be rewritable at
  # runtime (refresh-cookies.py re-extracts them from Chrome). The sops copy is only the seed used
  # on a fresh machine; the live file mopidy actually reads lives under state and is refreshed.
  authSeedPath = "${home}/.config/mopidy/browser.json";
  authPath = "${home}/.local/state/mopidy/browser.json";

  # At login, sops-nix (which generates config/auth) and mopidy startup may run concurrently.
  # Wait until the token is present in the config and the auth file is readable before starting.
  startScript = pkgs.writeShellScript "mopidy-start" ''
    conf="${confPath}"
    mkdir -p "$(dirname "${authPath}")"
    for _ in $(seq 1 60); do
      if [ -r "$conf" ] && [ -r "${authSeedPath}" ] && grep -q '^token = .' "$conf" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if [ ! -s "${authPath}" ] && [ -r "${authSeedPath}" ]; then
      cp "${authSeedPath}" "${authPath}"
      chmod 600 "${authPath}"
    fi
    exec ${mopidyEnv}/bin/mopidy --config "$conf"
  '';
in
{
  home.packages = [
    mopidyEnv
    pkgs.rmpc # MPD TUI client (connects to 127.0.0.1:6600 by default)
  ];

  # rmpc config: display lyrics from .lrc files in lyrics_dir (~/.cache/rmpc/lyrics).
  # On every song change, on_song_change runs the lyrics-fetch script (lrclib sync -> YTM async, in that order),
  # reflected immediately via hot-reload. The script uses ytmusicapi, so it runs with the mopidy env's python.
  xdg.configFile."rmpc/config.ron".text = ''
    #![enable(implicit_some)]
    (
        address: "127.0.0.1:6600",
        cache_dir: "~/.cache/rmpc",
        lyrics_dir: "~/.cache/rmpc/lyrics",
        enable_lyrics_hot_reload: true,
        on_song_change: ["${mopidyEnv}/bin/python", "${../../configs/media/rmpc/lyrics-fetch.py}"],
    )
  '';

  # YouTube auth seed (ytmusicapi browser format = JSON of headers + cookies).
  # Contains Google session cookies, so it's sops-managed. The start script copies it to authPath
  # once, and refresh-cookies.py keeps that copy fresh from Chrome after that.
  sops.secrets."ytmusic/browser_json" = {
    path = authSeedPath;
    mode = "0400";
  };

  # Declare the LB token for template embedding (no path needed since a placeholder is used).
  sops.secrets."listenbrainz/token" = { };

  # mopidy.conf contains the LB token, so it's generated via sops.templates (never stored in plaintext).
  sops.templates."mopidy.conf" = {
    path = confPath;
    content = ''
      [core]
      cache_dir = ${home}/.cache/mopidy
      data_dir = ${home}/.local/share/mopidy

      [audio]
      output = autoaudiosink

      [mpd]
      enabled = true
      hostname = 127.0.0.1
      port = 6600

      [http]
      enabled = true
      hostname = 127.0.0.1
      port = 6680

      [ytmusic]
      enabled = true
      oauth_json =
      auth_json = ${authPath}

      [listenbrainz]
      enabled = true
      token = ${config.sops.placeholder."listenbrainz/token"}
      url = api.listenbrainz.org
    '';
  };

  # Keep mopidy resident (launch at login + liveness monitoring). rmpc just connects to it.
  launchd.agents.mopidy = {
    enable = true;
    config = {
      ProgramArguments = [ "${startScript}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive"; # don't lower priority, for audio playback
      StandardOutPath = "/tmp/mopidy.out";
      StandardErrorPath = "/tmp/mopidy.err";
    };
  };

  # YouTube rotates its session cookies every few hours, so a static copy dies within hours.
  # Chrome keeps them alive while it runs, so briefly start the automation-profile Chrome on a
  # schedule, re-extract, and hand the result to mopidy. See configs/media/mopidy/refresh-cookies.py.
  launchd.agents.mopidy-cookies = {
    enable = true;
    config = {
      ProgramArguments = [
        "${mopidyEnv}/bin/python"
        "${../../configs/media/mopidy/refresh-cookies.py}"
      ];
      RunAtLoad = true;
      StartInterval = 7200; # 2h; the rotating cookies live in the single-hour range
      ProcessType = "Background";
      StandardOutPath = "/tmp/mopidy-cookies.log";
      StandardErrorPath = "/tmp/mopidy-cookies.log";
    };
  };
}
