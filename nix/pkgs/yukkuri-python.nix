# Python for the yukkuri VOICEVOX engine (~/Developer/github.com/gapul/yukkuri).
#
# That engine needs Open JTalk for its reading and accent analysis, which is
# the one dependency it cannot get from the standard library. Declaring it here
# means the checkout needs no `nix build` out-link of its own.
#
# Exposed under its own name rather than as `python3`: this environment exists
# for one program and should not decide which python everything else gets.
{
  lib,
  runCommand,
  python313,
}:
let
  env = python313.withPackages (ps: [ ps.pyopenjtalk ]);
in
runCommand "yukkuri-python"
  {
    meta = {
      description = "Python with pyopenjtalk, for the yukkuri VOICEVOX engine";
      platforms = lib.platforms.darwin;
      mainProgram = "yukkuri-python";
    };
  }
  ''
    mkdir -p $out/bin
    ln -s ${env}/bin/python3 $out/bin/yukkuri-python
  ''
