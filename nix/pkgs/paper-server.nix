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
  build = "112";
  # Paper's download URL embeds the object's sha256, so URL and hash cannot drift apart.
  sha256 = "bd3a58cf96874e5ea6643f5f6fe9b4f5bf9e34b795fa078c2f0ee8b98b2f907e";
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
