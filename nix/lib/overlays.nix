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
final: prev: {
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

  # git-annex 10.20260421's build-time test suite fails its "bup remote" test
  # ("remote ... has no colon" from bup init) against the bup version currently
  # in nixpkgs — a test-suite/bup incompatibility, not something homelab/git-annex.nix
  # controls, and we don't use bup remotes. Skip the checks so the package builds.
  git-annex = prev.git-annex.overrideAttrs (_: {
    doCheck = false;
  });

  # rustdesk re-tagged 1.5.0 upstream, so nixpkgs' src hash went stale ("hash mismatch in
  # fixed-output derivation"). Fixed in NixOS/nixpkgs#569507 (2026-10-03), but nixos-unstable
  # was still on 2026-10-01. Only swap the hash while nixpkgs still carries the stale one, so
  # this turns itself off once the fix lands instead of becoming the mismatch on the next bump
  # (the tailscale lesson above). Delete it once that has happened.
  rustdesk =
    if prev.rustdesk.src.outputHash == "sha256-xuIUWxicsqCJoKRvIDy0YISCHK3qolf1nWS3XMAM3PM=" then
      prev.rustdesk.overrideAttrs (o: {
        src = o.src.overrideAttrs (_: {
          outputHash = "sha256-1xa7X+swBIb8Lz3c6m8SeNZAiJWNCUpw+UbdSsMkeSk=";
        });
      })
    else
      prev.rustdesk;

  # trunk 0.21.14 vendors libdeflate-sys 1.23.1, whose C code uses the `evex512` target attribute
  # that GCC 16 removed, so it fails on x86_64-linux. Stalwart's webadmin is built with trunk, so
  # this took homeserver's mail service down with it in om ci. The patch is the one from
  # NixOS/nixpkgs#569964 (bumps libdeflate to 1.25.2, open as of 2026-10-04). Same guard as
  # rustdesk: only while nixpkgs still has the old cargoHash. Delete it once that PR has landed.
  trunk =
    if prev.trunk.cargoHash == "sha256-/5zvbSlMzZHxnAwuu0Jd6WVVjxJtIAQpRwZZHgYyPbs=" then
      # cargoDeps is computed from the original arguments, so overriding cargoHash alone doesn't
      # reach it; rebuild the vendor dir and patch the lockfile in the build itself as well.
      prev.trunk.overrideAttrs (o: {
        patches = (o.patches or [ ]) ++ [ ./trunk-libdeflate-gcc16.patch ];
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit (o) src;
          name = "${o.pname}-${o.version}";
          patches = [ ./trunk-libdeflate-gcc16.patch ];
          hash = "sha256-8HwfZ9dyplxc405rM33uNnjNt5JBFGWcmDNZJGMha9s=";
        };
      })
    else
      prev.trunk;
}
