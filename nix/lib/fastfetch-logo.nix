{ pkgs }:
# programs.fastfetch.settings.logo for a terminal with the kitty graphics protocol (Ghostty).
# The picture: the dark wallpaper (the one hyprlock shows), cropped to the
# wave's crest and Fuji. The crop is framed for subject = "wave" in wallpaper.nix; switching
# the subject needs a new one. 3:2 matches the logo box (44x14 cells at roughly 1:2 per cell),
# since kitty-direct stretches the image to fill the box.
let
  wallpaper = import ./wallpaper.nix {
    inherit pkgs;
    p = (builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json)).palettes.rose-pine;
    name = "rose-pine";
  };
in
{
  source = pkgs.runCommand "fastfetch-logo.png" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    magick ${wallpaper} -crop 2400x1600+330+250 +repage -resize 880x -quality 92 PNG24:$out
  '';
  type = "kitty-direct";
  width = 44;
  height = 14;
  padding = {
    top = 1;
    right = 3;
  };
}
