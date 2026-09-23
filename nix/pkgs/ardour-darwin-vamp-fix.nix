# Ardour on aarch64-darwin, with its Vamp SDK references repaired.
#
# nixpkgs' ardour bundle links libvamp-sdk / libvamp-hostsdk by the bare names
# `libvamp-sdk.so` / `libvamp-hostsdk.so` (no directory), so dyld only looks in the
# working directory and every binary in the bundle - Ardour9.app itself and the headless
# ardour9-lua / ardour9-export / ardour9-new_session CLIs - dies at load with
# "Library not loaded: libvamp-sdk.so". vamp-plugin-sdk does ship those files (as .so,
# oddly, but they are Mach-O), so the fix is to point the load commands at them.
# Rewriting a load command invalidates the ad-hoc signature, hence the re-sign.
#
# Wraps the built package instead of overriding its build so the cached ardour is reused;
# a source rebuild of ardour is an hour, this is a copy plus a few install_name_tool calls.
{
  lib,
  runCommand,
  ardour,
  vamp-plugin-sdk,
  cctools,
  darwin,
}:
runCommand "${ardour.pname}-${ardour.version}-vamp-fix"
  {
    inherit (ardour) meta;
    passthru = ardour.passthru or { };
    nativeBuildInputs = [
      cctools # otool, install_name_tool
      darwin.sigtool # codesign
    ];
  }
  ''
    cp -R ${ardour} $out
    chmod -R u+w $out
    vamp=${lib.getLib vamp-plugin-sdk}/lib
    n=0
    for f in $out/Applications/Ardour9.app/Contents/lib/* $out/bin/*; do
      [ -f "$f" ] || continue
      otool -L "$f" 2>/dev/null | grep -q 'libvamp-.*\.so' || continue
      install_name_tool \
        -change libvamp-sdk.so "$vamp/libvamp-sdk.so" \
        -change libvamp-hostsdk.so "$vamp/libvamp-hostsdk.so" "$f"
      codesign -f -s - "$f"
      n=$((n + 1))
    done
    # Eight files carried the bare names in 9.7/9.8; zero means the upstream package changed
    # and this wrapper is either obsolete or looking in the wrong place.
    [ "$n" -gt 0 ] || { echo "no binary referenced libvamp-*.so; drop this fix?" >&2; exit 1; }
  ''
