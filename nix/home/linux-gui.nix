{ pkgs, zen, ... }:
# GUI apps for the NixOS laptop. Imported only on nixos-laptop.
#
# The mac declares the same set as Homebrew casks (hosts/darwin.nix): on darwin nixpkgs GUI
# builds are unbundled and miss Spotlight / TCC / Launch Services, so casks win there. On
# Linux there is no such split, so the packages go straight into the closure and stay
# declarative.
#
# Zen is the exception: it has no nixpkgs derivation, so it comes in as a flake input
# (see nix/flake.nix `zen-browser`) and is wired to the same list from there.
{
  home.packages = with pkgs; [
    # ─── Browsers ───
    zen # daily driver. Comes from the zen-browser flake input, not nixpkgs.
    google-chrome # for sites that only test against Chrome, and for the automation profile
    tor-browser

    # ─── Passwords / 2FA ───
    bitwarden-desktop # the vault the SSH agent policy is built around
    keepassxc # offline vault (the same kdbx the iOS KeePassium build reads)
    ente-auth # TOTP

    # ─── Notes / Documents ───
    obsidian # vault syncs over the self-hosted CouchDB LiveSync
    thunderbird

    # ─── Messaging ───
    beeper
    simplex-chat-desktop

    # ─── Devices / Remote ───
    localsend # AirDrop-shaped transfer to the phone
    kdePackages.kdeconnect-kde
    rustdesk
    deskflow # share one keyboard/mouse across machines

    # ─── Network ───
    mullvad-vpn

    # ─── Creative / CAD / DTM ───
    blender
    freecad
    bitwig-studio # the one DAW, per the "Bitwig only" decision
    orca-slicer # Bambu A1 mini, same profile set as the mac

    # ─── Utilities ───
    imhex # hex editor
    espanso # text expansion (Wayland support is partial; see note below)

    # ─── Wayland extras that have no macOS counterpart ───
    swappy # annotate what hyprshot captured
    wl-mirror # mirror a region into a window (for screen sharing a slice)

    # ─── Non-Steam game launchers ───
    # Steam itself is system-side (programs.steam in hosts/nixos-laptop.nix) because it
    # needs the 32-bit graphics stack. These two only manage their own prefixes.
    lutris # GOG / standalone installers / emulators
    heroic # Epic / GOG / Amazon — the libraries the homelab free-games claimer fills up
  ];

  # espanso on Wayland needs the wayland variant and does not work under every compositor.
  # Left as a plain package rather than a service for now: enabling it as a systemd user
  # service before confirming it can inject into Hyprland windows would just add a failing
  # unit to `systemctl --user --failed`.
}
