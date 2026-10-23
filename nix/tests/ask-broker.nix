# configs/ask/test_broker.py against ask_broker.py, on the same Python packages the launchd agent
# runs it with (askPython in modules/home/darwin-services.nix, minus uvicorn, which the tests
# never import). The tests redirect the audit log themselves; HOME only keeps anything else away
# from a real one.
{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [
    ps.mcp
    ps.websockets
  ]);
in
# perl: one test forks a setsid'd grandchild with it (macOS has /usr/bin/perl; the sandbox has not).
pkgs.runCommand "dotfiles-ask-broker-tests" { nativeBuildInputs = [ pkgs.perl ]; } ''
  export HOME=$TMPDIR
  cp ${../../configs/ask/ask_broker.py} ask_broker.py
  cp ${../../configs/ask/test_broker.py} test_broker.py
  ${python}/bin/python3 test_broker.py
  touch $out
''
