# Geyser standalone: the Bedrock-to-Java protocol translator that lets phones, consoles and
# Windows 10 Edition players join the Java server. It runs as its own daemon in front of lazymc
# (nix/hosts/macmini.nix), so a Bedrock connection wakes the sleeping server like a Java one.
# The download API publishes a sha256 per build, so scripts/update-custom-packages.ts can move
# this pin to the newest build without downloading anything.
{ fetchurl }:
let
  version = "2.12.1";
  build = "1306";
in
fetchurl {
  name = "geyser-standalone-${version}-${build}.jar";
  url = "https://download.geysermc.org/v2/projects/geyser/versions/${version}/builds/${build}/downloads/standalone";
  sha256 = "a97b7d1de5147fe3ecc606dcfc434cbd3fee64564428f3517d4f00677c2f307b";
}
