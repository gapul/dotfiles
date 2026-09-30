{ pkgs, ... }:
# One palette for the parts of the desktop that nix cannot reach by hand.
#
# The hand-written configs (ghostty, yazi, bat, nvim …) already follow
# configs/theme/palettes.json through nix/lib/theme.nix, and they look right. What did not
# follow was everything with its own toolkit: wofi rendered a white sheet in the middle of a
# dark rice, and GTK/Qt dialogs (Bitwig's EULA, file pickers) came up stock white. Stylix
# exists here to close that gap, so `autoEnable` is off and only those targets are named.
# Anything already themed by hand is deliberately left alone rather than handed over.
#
# The scheme is built from palettes.json rather than pkgs.base16-schemes so that file stays
# the single source of truth — switching `active` to rose-pine-dawn moves GTK and wofi too.
let
  data = builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json);
  p = data.palettes.${data.active};

  # base16 mapping taken from tinted-theming's own rose-pine scheme. Two entries there use
  # highlightHigh (524f67), which palettes.json does not carry; hlMed is the nearest tone it
  # has, and unlike a hard-coded hex it follows a palette switch.
  scheme = {
    base00 = p.base; # background
    base01 = p.surface;
    base02 = p.overlay;
    base03 = p.muted; # comments
    base04 = p.subtle;
    base05 = p.text; # default foreground
    base06 = p.text;
    base07 = p.hlMed;
    base08 = p.love; # red
    base09 = p.gold; # orange
    base0A = p.rose; # yellow
    base0B = p.pine; # green
    base0C = p.foam; # cyan
    base0D = p.iris; # blue
    base0E = p.gold; # magenta (upstream reuses gold here)
    base0F = p.hlMed;
  };

  # The wallpaper is generated from the same palette instead of being a binary checked into
  # git: a tracked image would go stale the moment `active` changes, and it would be the one
  # part of the look that does not follow the theme. A near-flat vertical wash keeps windows
  # readable, and a single wide, heavily blurred iris glow stops it reading as a solid fill.
  wallpaper =
    pkgs.runCommand "rose-pine-wallpaper.png"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        magick -size 3840x2400 gradient:"#${p.overlay}-#${p.base}" \
          \( -size 3840x2400 xc:none \
             -fill "#${p.iris}" -draw "ellipse 1150,760 1250,900 0,360" \
             -blur 0x220 -alpha set -channel A -evaluate multiply 0.16 +channel \) \
          -compose Over -composite \
          \( -size 3840x2400 xc:none \
             -fill "#${p.pine}" -draw "ellipse 2900,1850 1050,760 0,360" \
             -blur 0x240 -alpha set -channel A -evaluate multiply 0.13 +channel \) \
          -compose Over -composite \
          -quality 92 PNG24:$out
      '';
in
{
  stylix = {
    enable = true;
    polarity = data.palettes.${data.active}.variant;
    base16Scheme = scheme;
    image = wallpaper;

    # Without this stylix hands the targets its own default (DejaVu Sans Mono), which is what
    # wofi came up in — correct colours in a font nothing else on the desktop uses. The
    # package is the same one hosts/nixos-laptop.nix installs system-wide, so the launcher,
    # the bar and the terminal all draw with one face.
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
    };

    # Off by default, on per target. Stylix would otherwise take over tools that already have
    # a hand-written theme here, and the two would fight on every rebuild.
    autoEnable = false;

    targets = {
      gtk.enable = true; # file pickers, Bitwig's EULA, anything GTK
      qt.enable = true;
      wofi.enable = true; # the white sheet in the middle of the screen
      hyprpaper.enable = true; # paints the generated wallpaper
    };
  };

  # Deliberately not listed above, because home/hyprland.nix already writes them by hand and
  # two writers for one option is a build error rather than a merge (`has conflicting
  # definition values`, seen for real on mako's background-color):
  #
  #   mako      — colours plus border-radius and timeout, next to its systemd unit
  #   hyprlock  — colours, the clock labels and the input field geometry
  #   waybar    — the whole stylesheet
  #   hyprland  — border gradients, and they read better beside the gaps they frame
  #
  # All of those already follow palettes.json through nix/lib/theme.nix, so nothing is
  # off-theme; stylix is here for the toolkits that had no palette at all.
}
