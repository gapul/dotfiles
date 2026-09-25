# The Minecraft server jar, fetched by content hash instead of being dropped into the world
# directory by hand. Pinning it here is what keeps a restart from silently changing the game
# version under the players; following the newest STABLE build is
# scripts/update-custom-packages.sh's job, so "always current" and "never surprising" both hold.
{
  lib,
  fetchurl,
}:
let
  version = "26.2";
  build = "129";
  # Paper's download URL embeds the object's sha256, so URL and hash cannot drift apart.
  sha256 = "b1d8f6bfa1b6101fa8e947b53041cb3bdf5540e7b83b6547ca19ba7edefeb083";
in
fetchurl {
  pname = "paper-server";
  inherit version sha256;
  url = "https://fill-data.papermc.io/v1/objects/${sha256}/paper-${version}-${build}.jar";
  meta = {
    description = "PaperMC server jar ${version} build ${build}";
    homepage = "https://papermc.io/";
    license = lib.licenses.gpl3Only;
  };
}
