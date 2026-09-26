# Geyser standalone: the Bedrock-to-Java protocol translator that lets phones, consoles and
# Windows 10 Edition players join the Java server. It runs as its own daemon in front of lazymc
# (nix/hosts/macmini.nix), so a Bedrock connection wakes the sleeping server like a Java one.
# The download API publishes a sha256 per build, so scripts/update-custom-packages.sh can move
# this pin to the newest build without downloading anything.
{ fetchurl }:
let
  version = "2.11.3";
  build = "1247";
in
fetchurl {
  name = "geyser-standalone-${version}-${build}.jar";
  url = "https://download.geysermc.org/v2/projects/geyser/versions/${version}/builds/${build}/downloads/standalone";
  sha256 = "1985465e2c88595dd6d8f180865cdb810442497486d8bd458ef07792684665aa";
}
