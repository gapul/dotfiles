{ pkgs, ... }:
let
  uxplay = pkgs.uxplay.overrideAttrs (old: {
    # PIN pairing uses SRP_SHA1 (20 bytes), not the 64-byte buffer capacity.
    # Keep the exact-length check and bound both client and server proof copies.
    postPatch = (old.postPatch or "") + ''
      substituteInPlace lib/raop_handlers.h \
        --replace-fail 'unsigned char proof[64]' 'unsigned char proof[20]'
    '';
  });

  # SyncClipboard reads the clipboard through xwayland-satellite and drops Wayland-native text
  # offers that include COMPOUND_TEXT ("content type is not supported"), e.g. Bitwarden in
  # Firefox. Push text straight from Wayland to the same server; SyncClipboard still handles
  # images, files and the download direction.
  syncclipboardWaylandPush = pkgs.writeShellApplication {
    name = "syncclipboard-wayland-push";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnugrep
      jq
      wl-clipboard
    ];
    text = ''
      # Invoked by `wl-paste --watch` on every selection change; stdin is ignored.
      cat >/dev/null

      types=$(wl-paste --list-types 2>/dev/null || true)
      # Leave images and file copies to SyncClipboard.
      if ! grep -qx 'text/plain.*\|UTF8_STRING\|STRING\|TEXT' <<<"$types" \
        || grep -q '^image/\|^text/uri-list$' <<<"$types"; then
        exit 0
      fi

      text=$(wl-paste --no-newline --type text 2>/dev/null) || exit 0
      [ -n "$text" ] || exit 0
      [ "''${#text}" -le 1000000 ] || exit 0

      # Skip what we just sent, including SyncClipboard writing a download back to the clipboard.
      state="''${XDG_RUNTIME_DIR:-/tmp}/syncclipboard-wayland-push.last"
      hash=$(printf %s "$text" | sha256sum | cut -d' ' -f1)
      if [ "$(cat "$state" 2>/dev/null)" = "$hash" ]; then exit 0; fi

      config="$HOME/.config/SyncClipboard/SyncClipboard.json"
      account=$(jq -c '.Account.AccountId as $id | .SavedAccounts.SyncClipboard[$id]' "$config")
      url=$(jq -r '.RemoteURL' <<<"$account")
      auth=$(jq -r '"\(.UserName):\(.Password)"' <<<"$account")

      if jq -n --arg t "$text" '{type: "Text", text: $t, hasData: false}' \
        | curl -fsS -m 10 -X PUT -H 'Content-Type: application/json' \
            -K <(printf 'user = "%s"\n' "$auth") --data-binary @- "$url/SyncClipboard.json" \
            >/dev/null; then
        printf %s "$hash" >"$state"
      fi
    '';
  };

  # SyncClipboard writes downloads to the X11 selection, and xwayland-satellite only hands that
  # to Wayland while an X11 window has focus, so text from the iPhone often never reached Wayland
  # apps (2026-10-26). Poll the same server and set the Wayland selection directly.
  syncclipboardWaylandPull = pkgs.writeShellApplication {
    name = "syncclipboard-wayland-pull";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      wl-clipboard
    ];
    text = ''
      config="$HOME/.config/SyncClipboard/SyncClipboard.json"
      account=$(jq -c '.Account.AccountId as $id | .SavedAccounts.SyncClipboard[$id]' "$config")
      url=$(jq -r '.RemoteURL' <<<"$account")
      auth=$(jq -r '"\(.UserName):\(.Password)"' <<<"$account")
      # Shared with syncclipboard-wayland-push so neither side echoes the other.
      state="''${XDG_RUNTIME_DIR:-/tmp}/syncclipboard-wayland-push.last"

      last=""
      first=1
      while sleep 1; do
        json=$(curl -fsS -m 10 -K <(printf 'user = "%s"\n' "$auth") "$url/SyncClipboard.json" 2>/dev/null) \
          || continue
        # The whole response, including syncedAt, so sending the same text again still counts.
        sum=$(printf %s "$json" | sha256sum | cut -d' ' -f1)
        [ "$sum" != "$last" ] || continue
        last=$sum
        # Do not overwrite the clipboard with whatever was on the server at startup.
        if [ "$first" = 1 ]; then
          first=0
          continue
        fi

        [ "$(jq -r '.type' <<<"$json")" = Text ] || continue
        text=$(jq -j '.text // ""' <<<"$json")
        [ -n "$text" ] || continue
        [ "$(wl-paste --no-newline --type text 2>/dev/null || true)" != "$text" ] || continue

        printf %s "$text" | sha256sum | cut -d' ' -f1 >"$state"
        printf %s "$text" | wl-copy
      done
    '';
  };
in
{
  # AirPlay requires Avahi publishing and Wi-Fi ports 7000..7002 on the host.
  # Started by hand (`systemctl --user start uxplay`, `stop` when done), not with the session:
  # while it runs the receiver is announced to everyone on whatever Wi-Fi the laptop is on.
  systemd.user.services.uxplay = {
    Unit = {
      Description = "iPhone AirPlay receiver";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStartPre = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "wait-for-avahi";
          bashOptions = [ ];
          text = ''
            for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
              state=$(${pkgs.systemd}/bin/busctl --system call org.freedesktop.Avahi / org.freedesktop.Avahi.Server GetState 2>/dev/null || true)
              if [ "$state" = "i 2" ]; then exit 0; fi
              ${pkgs.coreutils}/bin/sleep 1
            done
            echo "Avahi did not reach running state" >&2
            exit 1
          '';
        }
      );
      # -pin asks a new iPhone for an on-screen PIN. -key keeps the server key in ~/.uxplay.pem and
      # -reg remembers paired clients in ~/.uxplay.register, so the PIN is entered once rather
      # than after every restart (a fresh key each start made the iPhone pair again).
      ExecStart = "${pkgs.coreutils}/bin/stdbuf -oL -eL ${uxplay}/bin/uxplay -n nixlaptop -p 7000 -pin -key -reg";
      Restart = "always";
      RestartSec = 5;
    };
  };
  systemd.user.services.syncclipboard = {
    Unit = {
      Description = "SyncClipboard desktop synchronization";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.callPackage ../pkgs/syncclipboard.nix { }}/bin/syncclipboard";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  systemd.user.services.syncclipboard-wayland-push = {
    Unit = {
      Description = "Push Wayland clipboard text to the SyncClipboard server";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${syncclipboardWaylandPush}/bin/syncclipboard-wayland-push";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  systemd.user.services.syncclipboard-wayland-pull = {
    Unit = {
      Description = "Copy SyncClipboard server text to the Wayland clipboard";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${syncclipboardWaylandPull}/bin/syncclipboard-wayland-pull";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
