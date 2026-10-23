# configs/homelab/freebie-collector/test_collector.py: ingest into a throwaway git-annex repo with
# the same git-annex and Python the service unit uses (homelab/freebie-collector.nix).
{ pkgs }:
pkgs.runCommand "dotfiles-freebie-collector-tests"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.git
      pkgs.git-annex
    ];
  }
  ''
    export HOME=$TMPDIR
    cp ${../../configs/homelab/freebie-collector/collector.py} collector.py
    cp ${../../configs/homelab/freebie-collector/test_collector.py} test_collector.py
    python3 test_collector.py
    touch $out
  ''
