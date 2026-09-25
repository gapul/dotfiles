# Overlay (SSO) that absorbs temporary breakage in upstream nixpkgs.
# Both flake.nix's mkPkgs/mkWslPkgs (standalone home) and the nix-darwin system's
# nixpkgs.overlays (hosts/darwin-common.nix; the pkgs used by the embedded home-manager)
# import this. With only one, the darwin system's pre-commit stays vanilla
# and the isatty test breakage recurs in om ci (aarch64-darwin).
#
# pre-commit 4.5.1's tests/repository_test.py::test_output_isatty fails on GitHub's
# macos-14 runner due to a dependency on the sandbox's isatty behavior. deselect just that one
# test via pytestCheckHook's disabledTests (other tests and the build are preserved.
# doCheck=false can't stop pytestCheckPhase and causes exit 127 in other environments, so it's not viable).
_final: prev: {
  # (tailscale 1.98.9's vendorHash override was removed 2026-08-07: nixpkgs bumped
  # tailscale to 1.98.10 with a corrected hash, and the stale override itself became
  # the mismatch — "specified" in the CI error was our pinned value.)

  # git-annex 10.20260421's test suite calls `bup init -r <path>`, and the bup that
  # nixpkgs 2026-09-23 ships rejects a remote without host:path ("has no colon"), so
  # "bup remote" fails 3/3 and homeserver cannot build (2026-09-25). Nothing here uses
  # the bup remote; the annex speaks ssh. Building without the test suite also saves
  # ~15 minutes on the N150, which has to compile git-annex itself because the
  # nixos-unstable revision is not on cache.nixos.org.
  # ponytail: drop once nixpkgs carries a git-annex that passes with the new bup.
  git-annex = prev.haskell.lib.dontCheck prev.git-annex;

  pre-commit = prev.pre-commit.overridePythonAttrs (o: {
    disabledTests = (o.disabledTests or [ ]) ++ [
      "test_output_isatty"
      # git clone's pack-file copy occasionally races in the nix sandbox and
      # fails with "failed to copy file ... No such file or directory".
      # It intermittently reds om ci(darwin) on macos-14, so deselect it.
      "test_pre_push_integration"
    ];
  });
}
