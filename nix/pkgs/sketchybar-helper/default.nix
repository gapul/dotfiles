# sketchybar's event helper: a 31-line C program that holds the CPU sampler and answers
# sketchybar's events over a mach port, which is much cheaper than re-running a shell script
# every second.
#
# It used to be compiled by `sketchybarrc` itself — `(cd $CONFIG_DIR/helper && make)` on every bar
# start, from sources sitting in the config directory. So the config directory held a C program
# and a makefile, and starting the bar meant running a compiler. The sources live here now, next
# to the thing that builds them, and the bar just runs the binary.
{ stdenv }:
stdenv.mkDerivation {
  pname = "sketchybar-helper";
  version = "1.0";

  src = ./.;

  buildPhase = ''
    runHook preBuild
    clang -std=c99 -O3 helper.c -o sketchybar-helper
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 sketchybar-helper $out/bin/sketchybar-helper
    runHook postInstall
  '';

  meta = {
    description = "Event helper process for sketchybar (CPU sampler over a mach port)";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "sketchybar-helper";
  };
}
