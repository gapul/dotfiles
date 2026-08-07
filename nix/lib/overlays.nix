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
