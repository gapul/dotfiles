# The Fabric server launcher jar, fetched by content hash. Fabric's meta service assembles this jar
# from (game version, loader, installer), so the URL is the whole pin. Following the newest game
# version that every declared mod supports is scripts/update-custom-packages.sh's job; it rewrites
# the four values below together with nix/pkgs/fabric-mods.nix.
{ fetchurl }:
let
  mcVersion = "26.3";
  loader = "0.19.5";
  installer = "1.1.2";
in
fetchurl {
  name = "fabric-server-${mcVersion}-loader-${loader}.jar";
  url = "https://meta.fabricmc.net/v2/versions/loader/${mcVersion}/${loader}/${installer}/server/jar";
  hash = "sha256-C1atVNdiFy6Lh0jkZ/WE8HHk3t7Nk9wzbPLGiDfnkL4=";
  passthru = { inherit mcVersion loader installer; };
}
