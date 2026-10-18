{ pkgs, ... }:
# The machine's card: the few facts worth a glance, in the palette. Every host gets the same
# lines; the picture (and greeting a new terminal with it) is set where there is a terminal
# that can show it (home/hyprland.nix, home/darwin.nix).
{
  programs.fastfetch = {
    enable = true;
    settings = {
      display = {
        separator = "  ";
        color = {
          keys = "magenta";
          title = "blue";
        };
      };
      # No `packages`: counting the nix store took ~0.5s (fastfetch --stat on the Mac), and
      # this runs on every new terminal.
      modules = [
        "title"
        "separator"
        {
          type = "os";
          key = "${if pkgs.stdenv.hostPlatform.isDarwin then "" else ""} os";
        }
        {
          type = "kernel";
          key = "󰌽 kernel";
        }
        {
          type = "wm";
          key = "󰖲 wm";
        }
        {
          type = "uptime";
          key = "󰔟 up";
        }
        {
          type = "cpu";
          key = "󰻠 cpu";
        }
        {
          type = "memory";
          key = "󰍛 mem";
        }
        # One line for the root filesystem: btrfs subvolumes (the laptop) otherwise each get one.
        {
          type = "disk";
          key = "󰋊 disk";
          folders = "/";
        }
        # Prints nothing on a machine without one.
        {
          type = "battery";
          key = "󰁹 bat";
        }
        "break"
        "colors"
      ];
    };
  };
}
