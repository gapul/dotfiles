# Build the KernelSU modules declared for a rooted Android device into flashable zips.
#
# mobile/android/devices/<codename>/root/ holds the declaration: sources.json pins the upstream
# zips by URL and hash (scripts/update-custom-packages.ts moves the pins), modules/ holds the
# modules written here, and *.patch adjusts an upstream one. This file only assembles them.
# Installing is mobile/android/root.sh (`just android-root`), which pushes each zip to the device
# and runs `ksud module install`, in the order of manifest.tsv.
#
# The output is a directory of NN-<id>.zip plus manifest.tsv (<id> <versionCode> <version>
# <file>, tab-separated). root.sh compares the versionCode with what the device reports, so the
# id and versionCode are read out of each zip's own module.prop rather than restated here.
{
  pkgs,
  lib,
  device,
  root,
}:
let
  sources = lib.importJSON (root + "/sources.json");

  fetch =
    name:
    pkgs.fetchurl {
      inherit (sources.${name}) url hash;
      # The upstream file names carry versions and build hashes; a stable store name keeps the
      # derivations below from depending on them.
      name = "${name}-src";
    };

  # Zip a directory. Store paths carry the 1970 epoch, which zip cannot represent and clamps to
  # 1980, so the result is the same on every machine. -X drops the uid/gid extra fields.
  zipDir =
    name: dir:
    pkgs.runCommand "${name}.zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
      cd ${dir}
      zip -qrX "$out" .
    '';

  # Order is install order. The metamodule goes first, since a module installed before it is
  # never mounted; Vector loads through Zygisk Next, so that comes before it.
  modules = [
    {
      id = "meta-mm";
      zip = fetch "meta-mm";
    }
    {
      id = "zygisksu";
      zip = fetch "zygisksu";
    }
    {
      id = "zygisk_vector";
      zip = fetch "zygisk_vector";
    }
    {
      id = "charge_limit";
      zip = zipDir "charge_limit" (root + "/modules/charge_limit");
    }
    {
      id = "systemless-hosts-KernelSU-module";
      zip = zipDir "systemless-hosts" (root + "/modules/systemless-hosts");
    }
    {
      id = "ainur_jamesdsp";
      # The module repository itself is the flashable tree. The patch answers the two
      # volume-key prompts its installer asks, and the ThePBone UI slot gets the root-full
      # JamesDSP build, which the module installs on boot when the app is missing.
      zip =
        pkgs.runCommand "ainur_jamesdsp.zip"
          {
            nativeBuildInputs = [ pkgs.zip ];
            src = fetch "ainur_jamesdsp";
            apk = fetch "jamesdsp-rootfull-apk";
          }
          ''
            tar xzf "$src"
            cd ainur_jamesdsp-*
            patch -p1 <${root + "/ainur_jamesdsp.patch"}
            install -m 644 "$apk" common/files/JamesDSPManagerThePBone.apk
            # patch and install stamp the build time on what they touch; pin every entry.
            find . -exec touch -h -d @315532800 {} +
            # A stale copy of the whole module that the installer never reads.
            rm -f install.zip
            zip -qrX "$out" . -x '.git*'
          '';
    }
  ];
in
pkgs.runCommand "android-root-${device}" { nativeBuildInputs = [ pkgs.unzip ]; } ''
  mkdir "$out"
  n=0
  ${lib.concatMapStrings (m: ''
    n=$((n + 1))
    file=$(printf '%02d-%s.zip' "$n" ${lib.escapeShellArg m.id})
    cp ${m.zip} "$out/$file"
    prop=$(unzip -p ${m.zip} module.prop | tr -d '\r')
    id=$(sed -n 's/^id=//p' <<<"$prop")
    if [ "$id" != ${lib.escapeShellArg m.id} ]; then
      echo "module.prop says id=$id, declared as ${m.id}" >&2
      exit 1
    fi
    # root.sh compares versionCode arithmetically.
    if ! sed -n 's/^versionCode=//p' <<<"$prop" | grep -qxE '[0-9]+'; then
      echo "module.prop of ${m.id} has no numeric versionCode" >&2
      exit 1
    fi
    printf '%s\t%s\t%s\t%s\n' "$id" "$(sed -n 's/^versionCode=//p' <<<"$prop")" \
      "$(sed -n 's/^version=//p' <<<"$prop")" "$file" >>"$out/manifest.tsv"
  '') modules}
''
