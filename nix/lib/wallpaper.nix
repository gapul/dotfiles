{
  pkgs,
  p,
  name,
}:
# The wallpaper for palette `p`, generated at build time in its colours (so a palette
# switch regenerates it). One picture is active at a time; the others stay as options:
#   hands  the hands of Michelangelo's Creation of Adam (wallpaper-hands.nix)
#   wave   the wave of Hokusai's Great Wave off Kanagawa (wallpaper-wave.nix)
# Everything that shows a wallpaper (hyprpaper/awww via darkman, hyprlock, ReGreet, rEFInd,
# the fastfetch logo) imports this file, so changing `subject` changes all of them.
let
  subject = "wave";
  # The wave with what is drawn and what is left bare swapped: the print's light areas
  # (sky, foam, the boats) as characters, the dark water as bare base colour.
  invert = true;
in
if subject == "wave" then
  import ./wallpaper-wave.nix { inherit pkgs p name invert; }
else
  import ./wallpaper-hands.nix { inherit pkgs p name; }
