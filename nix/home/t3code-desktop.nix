{
  config,
  lib,
  pkgs,
  ...
}:
# T3 Code (nightly) on the NixOS laptop: the desktop app and the `t3` CLI, the pair the mac gets
# from the t3-code@nightly cask (hosts/darwin.nix). It is a client of the macmini's t3code host,
# and a nightly server only takes nightly clients, so nixpkgs' t3code (the stable train) cannot
# stand in. Neither is declared: nightly moves daily, so t3code-update below follows the train with
# the official installer/updater, as on the mini (home/macmini.nix), and then fetches the AppImage
# of the same version, so the app and the CLI never disagree.
let
  appDir = "${config.xdg.dataHome}/t3code";
  appImage = "${appDir}/T3-Code.AppImage";
  releases = "https://github.com/pingdotgg/t3code/releases/download";

  # Started from wofi, the app inherits the systemd user environment, which has none of the agent
  # dirs .zshenv exports (lib/shell-xdg-env.nix). Without them the claude / codex it spawns would
  # fall back to their default dirs instead of the XDG ones every shell uses.
  launcher = pkgs.writeShellScript "t3code-desktop" ''
    if [ ! -x "${appImage}" ]; then
      ${pkgs.libnotify}/bin/notify-send -a "T3 Code" "T3 Code is not installed yet" \
        "Run: systemctl --user start t3code-update"
      exit 1
    fi
    export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude"
    export CODEX_HOME="${config.xdg.dataHome}/codex"
    export CODEX_SQLITE_HOME="${config.xdg.stateHome}/codex/sqlite"
    exec ${pkgs.appimage-run}/bin/appimage-run "${appImage}" "$@"
  '';

  update = pkgs.writeShellScript "t3code-update" ''
    set -eu
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          bash
          coreutils
          curl
          findutils
          gawk
          gnugrep
          gnused
          gnutar
          gzip
          openssl
        ]
      )
    }"
    t3="$HOME/.local/bin/t3"
    if [ -x "$t3" ]; then
      "$t3" update --channel nightly --yes
    else
      curl -fsSL https://t3.codes/install.sh | T3CODE_CHANNEL=nightly sh
    fi

    # ~/.local/bin/t3 -> ~/.t3/runtime/versions/<version>/t3
    version="$(basename "$(dirname "$(readlink "$t3")")")"
    mkdir -p "${appDir}"
    [ "$(cat "${appDir}/version" 2>/dev/null || true)" = "$version" ] && exit 0

    tmp="$(mktemp -d "${appDir}/.download.XXXXXX")"
    trap 'rm -rf "$tmp"' EXIT
    name="T3-Code-$version-x86_64.AppImage"
    curl -fsSL -o "$tmp/latest.yml" "${releases}/v$version/nightly-linux.yml"
    curl -fsSL -o "$tmp/$name" "${releases}/v$version/$name"
    # SHA256SUMS covers only the CLI archives; the app's digest is in the electron-updater feed.
    want="$(awk -v url="$name" '$NF == url { getline; print $2; exit }' "$tmp/latest.yml")"
    got="$(openssl dgst -sha512 -binary "$tmp/$name" | base64 -w0)"
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
      echo "t3code-update: sha512 mismatch for $name" >&2
      exit 1
    fi
    chmod +x "$tmp/$name"
    # The type 2 runtime is static, so it extracts without appimage-run.
    # (the t3code.png at the image root is only a symlink to this one)
    icon=usr/share/icons/hicolor/512x512/apps/t3code.png
    (cd "$tmp" && "./$name" --appimage-extract "$icon" >/dev/null)
    cp "$tmp/squashfs-root/$icon" "${appDir}/t3code.png"
    # rename over the old file: a running app keeps its open inode and picks the new one up on restart.
    mv -f "$tmp/$name" "${appImage}"
    echo "$version" > "${appDir}/version"

    # appimage-run unpacks every AppImage it sees into a cache dir named after its hash, about
    # 400 MB a version, and never removes one. Drop the T3 Code ones the new version left behind,
    # keeping the last few days' in case an instance is still running from one of them.
    cache="${config.xdg.cacheHome}/appimage-run"
    if [ -d "$cache" ]; then
      find "$cache" -mindepth 1 -maxdepth 1 -type d -mtime +3 -exec test -e '{}/t3code' ';' \
        -exec rm -rf '{}' +
    fi
  '';
in
{
  xdg.desktopEntries.t3code = {
    name = "T3 Code (Nightly)";
    exec = "${launcher} %U";
    icon = "${appDir}/t3code.png";
    terminal = false;
    categories = [ "Development" ];
    mimeType = [ "x-scheme-handler/t3code" ];
    settings.StartupWMClass = "t3code";
  };
  # Pairing links (t3code://) open the app. mimeapps.list is home-manager's (home/linux-gui.nix).
  xdg.mimeApps.defaultApplications."x-scheme-handler/t3code" = "t3code.desktop";

  # Installs on the first run, then follows the nightly train every morning. Persistent catches up
  # after a morning the lid was shut; OnStartupSec covers a freshly installed machine.
  systemd.user.services.t3code-update = {
    Unit.Description = "Follow the T3 Code nightly train (CLI and desktop AppImage)";
    Service = {
      Type = "oneshot";
      ExecStart = "${update}";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.t3code-update = {
    Unit.Description = "Daily T3 Code nightly update";
    Timer = {
      OnCalendar = "*-*-* 05:00:00";
      OnStartupSec = "2min";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
