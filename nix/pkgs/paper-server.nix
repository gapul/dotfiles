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
  build = "123";
  # Paper's download URL embeds the object's sha256, so URL and hash cannot drift apart.
  sha256 = "7b7b3b43c009103e1971a0576c26f655a7dd9b56a0a2a4438e352c03a7fecd08";
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
