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
  palettes,
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

  # The boot animation, drawn from the active palette in configs/theme/palettes.json: three dots
  # in rose, iris and foam pulsing on the base colour. Same 450x450 at 30 fps as crDroid's own,
  # and the same three parts: fade in once, loop until boot completes, fade out. bootanimation
  # reads the archive uncompressed (zip -0). The versionCode is taken from the content, so a
  # palette change reinstalls it on the next root.sh run.
  bootanimation =
    pkgs.runCommand "rosepine-bootanimation.zip"
      {
        nativeBuildInputs = [
          pkgs.imagemagick
          pkgs.jq
          pkgs.zip
        ];
      }
      ''
        pal() { jq -r --arg k "$1" '.palettes[.active][$k]' ${palettes}; }
        base=$(pal base)
        colors=("$(pal rose)" "$(pal iris)" "$(pal foam)")
        mkdir -p anim/part0 anim/part1 anim/part2
        printf '450 450 30\nc 1 0 part0 #%s\nc 0 0 part1 #%s\nc 1 0 part2 #%s\n' "$base" "$base" "$base" \
          >anim/desc.txt

        # frame <file> <level0> <level1> <level2>: each level 0..1 mixes a dot from the base
        # colour to its own and grows it a little.
        frame() {
          local file=$1 args=() i
          shift
          for i in 0 1 2; do
            read -r color radius < <(awk -v b="$base" -v c="''${colors[$i]}" -v a="$1" 'BEGIN {
              out = "#"
              for (k = 1; k <= 5; k += 2) {
                x = strtonum("0x" substr(b, k, 2)); y = strtonum("0x" substr(c, k, 2))
                out = out sprintf("%02x", x + (y - x) * a)
              }
              print out, 18 + 8 * a
            }')
            local cx=$((135 + 90 * i))
            args+=(-fill "$color" -draw "circle $cx,225 $cx,$(awk -v r="$radius" 'BEGIN { printf "%.1f", 225 - r }')")
            shift
          done
          # bootanimation draws nothing from a 16-bit PNG, which is what ImageMagick writes by
          # default here; PNG24 keeps it at 8 bits per channel.
          magick -size 450x450 "xc:#$base" "''${args[@]}" -depth 8 -strip \
            -define png:exclude-chunks=date,time "PNG24:$file"
        }

        # Loop: 45 frames, each dot peaking a third of a cycle after the previous one.
        level() { awk -v t="$1" -v i="$2" -v lo="$3" 'BEGIN {
          s = sin(2 * 3.14159265 * (t / 45 - i / 3)); if (s < 0) s = 0
          printf "%.3f", lo + (1 - lo) * s
        }'; }
        for t in $(seq 0 44); do
          frame "$(printf 'anim/part1/%03d.png' "$t")" "$(level "$t" 0 0.3)" "$(level "$t" 1 0.3)" "$(level "$t" 2 0.3)"
        done
        # In and out: 15 frames between nothing and the loop's resting level.
        for t in $(seq 0 14); do
          a=$(awk -v t="$t" 'BEGIN { printf "%.3f", 0.3 * t / 14 }')
          frame "$(printf 'anim/part0/%03d.png' "$t")" "$a" "$a" "$a"
          a=$(awk -v t="$t" 'BEGIN { printf "%.3f", 0.3 * (14 - t) / 14 }')
          frame "$(printf 'anim/part2/%03d.png' "$t")" "$a" "$a" "$a"
        done

        find anim -exec touch -h -d @315532800 {} +
        (cd anim && zip -0 -qrX ../bootanimation.zip desc.txt part0 part1 part2)

        mkdir -p module/system/product/media
        cp bootanimation.zip module/system/product/media/bootanimation.zip
        code=$((16#$(sha256sum bootanimation.zip | cut -c1-7)))
        printf '%s\n' "id=rosepine-bootanimation" "name=Rose Pine boot animation" \
          "version=$(sha256sum bootanimation.zip | cut -c1-7)" "versionCode=$code" "author=gapul" \
          "description=Boot animation drawn from the dotfiles palette (configs/theme/palettes.json)." \
          >module/module.prop
        find module -exec touch -h -d @315532800 {} +
        (cd module && zip -qrX "$out" .)
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
      id = "rosepine-bootanimation";
      zip = bootanimation;
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
