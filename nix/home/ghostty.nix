{ lib, pkgs, ... }:
# Ghostty config, shared by the Mac (home/darwin.nix) and nixos-laptop (home/hyprland.nix).
# Rendered by home-manager's programs.ghostty through pkgs.formats.keyValue, i.e. pkgs.writeText:
# no build-time tools, so the darwin derivation carries none of the formats.yaml/toml risk
# noted in home/darwin.nix (x86_64-linux CI evaluating a darwin builder).
# See https://ghostty.org/docs/config for the keys.
let
  # Font SSO: configs/theme/fonts.json (mono), which Windows' theme/apply.ps1 reads too.
  inherit (lib.importJSON ../../configs/theme/fonts.json) mono;
in
{
  programs.ghostty = {
    enable = true;
    # The binary is not installed from here: the Mac takes Ghostty.app from the Homebrew cask
    # (hosts/darwin.nix) and nixos-laptop from environment.systemPackages / home/hyprland.nix.
    # With no package the module's systemd unit, bat syntax and +validate-config hook are off.
    package = null;
    systemd.enable = false;
    # Ghostty injects its own shell integration; the rc files stay as they were.
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableZshIntegration = false;

    settings = lib.mkMerge [
      {
        font-family = ''"${mono}"'';
        clipboard-read = "allow";
        clipboard-write = "allow";

        # Follows the OS appearance (light/dark). Ghostty theme names are fixed to upstream's
        # (dark=Rose Pine / light=Rose Pine Dawn); the colours themselves live in
        # configs/theme/palettes.json. Starship uses ANSI named colours, so it rides the palette.
        theme = "light:Rose Pine Dawn,dark:Rose Pine";

        # No confirmation dialog when closing a window/tab.
        confirm-close-surface = false;

        # Treat Option as Alt/Meta (both sides). Unset, Option+l types special characters (ø …)
        # and nvim's <M-l> style Meta mappings never arrive.
        macos-option-as-alt = true;

        macos-titlebar-style = "hidden";
        background-opacity = "0.5"; # a string: Nix floats print as 0.500000
        background-blur-radius = 30;

        # Don't restore the previous windows on restart.
        window-save-state = "never";

        keybind = [
          # Ghostty's default cmd+enter (toggle_fullscreen) clashes with AeroSpace tiling.
          "cmd+enter=unbind"
          # In TUIs such as tmux, the default performable:copy_to_clipboard passes Cmd+C
          # through as 'c' when nothing is selected; drop performable so the key is always consumed.
          "cmd+c=copy_to_clipboard"
        ];

        # Resolution-dependent font size: home.activation.ghosttyFontSize (home/darwin.nix) writes
        # font-size from the main display's resolution into this fragment (scripts/ghostty-fontsize.sh).
        # Ghostty loads config-file includes after the file that names them, so it overrides.
        # The leading ? makes it optional (no error while it is ungenerated); Ghostty expands ~.
        config-file = "?~/.config/ghostty.local/font-size.conf";
      }
      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        # On macOS Ghostty is a login item that stays resident with no window, waiting for
        # the hotkey: no window at launch, and closing the last one does not quit.
        initial-window = false;
        quit-after-last-window-closed = false;
      })
      (lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) {
        # On Linux that pair means `$mod+Return` spawns a process that never maps a window,
        # so the terminal looks broken while stray ghostty processes pile up.
        initial-window = true;
        quit-after-last-window-closed = true;
      })
    ];
  };
}
