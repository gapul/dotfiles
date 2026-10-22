# Geyser standalone: the Bedrock-to-Java protocol translator that lets phones, consoles and
# Windows 10 Edition players join the Java server. It runs as its own daemon in front of lazymc
# (nix/hosts/macmini.nix), so a Bedrock connection wakes the sleeping server like a Java one.
# The download API publishes a sha256 per build, so scripts/update-custom-packages.sh can move
# this pin to the newest build without downloading anything.
{ fetchurl }:
let
  version = "2.12.0";
  build = "1269";
in
fetchurl {
  name = "geyser-standalone-${version}-${build}.jar";
  url = "https://download.geysermc.org/v2/projects/geyser/versions/${version}/builds/${build}/downloads/standalone";
  sha256 = "9f12a792b680bddf4f15d7947118cc18b9fbefa8e36281c43a4e5eacc8e2461b";
}
