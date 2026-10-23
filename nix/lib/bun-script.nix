# Package a Bun TypeScript script as a command. The script is copied into the store with the
# directory it sits in (`src`), so relative imports between files of the same tool keep working;
# `main` is the entry point inside it. Type checking happens in CI (scripts/ci-lint.sh, tsc over
# tsconfig.json), not here: the build only needs bun, not node_modules.
{ pkgs }:
{
  name,
  src,
  main,
  runtimeInputs ? [ ],
}:
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [ pkgs.bun ] ++ runtimeInputs;
  text = ''
    exec bun ${src}/${main} "$@"
  '';
}
