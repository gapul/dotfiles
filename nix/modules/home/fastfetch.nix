{ pkgs, ... }:
# The machine's card: the few facts worth a glance, in the palette. Every host gets the same
# lines; the picture (and greeting a new terminal with it) is set where there is a terminal
# that can show it (home/hyprland.nix, home/darwin.nix).
#
# `profile` is the same card about me instead of the machine.
let
  blank = {
    type = "custom";
    format = "";
  };
  fact = key: format: {
    type = "custom";
    inherit key format;
  };
  profileConfig = (pkgs.formats.json { }).generate "fastfetch-profile.jsonc" {
    # The GitHub avatar, kept in the repo: fetching it would break the build whenever it changes.
    # `auto` draws it with the kitty protocol in Ghostty and falls back to blocks elsewhere.
    logo = {
      source = ../../../configs/profile/avatar.png;
      type = "auto";
      width = 24;
      height = 12;
      padding = {
        top = 1;
        right = 3;
      };
    };
    display = {
      separator = "  ";
      key.width = 12;
      color.keys = "magenta";
    };
    modules = [
      {
        type = "custom";
        format = "{#1;34}gapul";
      }
      {
        type = "custom";
        format = "{#90}─────────────────────────────";
      }
      (fact "󰑴 school" "University of Tokyo")
      (fact "󰍎 based" "Tokyo")
      blank
      (fact " github" "github.com/gapul")
      (fact "󰕄 x" "@gapul1729")
      (fact " dots" "github.com/gapul/dotfiles")
      blank
      {
        type = "os";
        key = "󰍹 os";
      }
      {
        type = "shell";
        key = " shell";
      }
      {
        type = "editor";
        key = " editor";
      }
      {
        type = "terminal";
        key = "󰆍 term";
      }
      {
        type = "wm";
        key = "󰖲 wm";
      }
      blank
      (fact "󰗀 langs" "Python · Swift · TypeScript · Nix")
      (fact "󰋑 likes" "Nix · home server · AI agents")
      "break"
      "colors"
    ];
  };
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "profile" ''
      exec ${pkgs.fastfetch}/bin/fastfetch --config ${profileConfig} "$@"
    '')
  ];

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
