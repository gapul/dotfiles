# 上流 nixpkgs の一時的な破損を吸収する overlay (SSO)。
# flake.nix の mkPkgs/mkWslPkgs (standalone home) と、nix-darwin システムの
# nixpkgs.overlays (hosts/darwin-common.nix。埋め込み home-manager が使う pkgs)
# の両方がこれを import する。片方だけだと darwin システム側の pre-commit が
# 素のまま残り、om ci (aarch64-darwin) で isatty テスト破損が再発する。
#
# pre-commit 4.5.1 の tests/repository_test.py::test_output_isatty が GitHub の
# macos-14 ランナーで sandbox の isatty 挙動依存に落ちる。pytestCheckHook の
# disabledTests でその1テストだけ deselect する (他テストと build は温存。
# doCheck=false は pytestCheckPhase を止められず別環境で exit 127 を招くため不可)。
_final: prev: {
  pre-commit = prev.pre-commit.overridePythonAttrs (o: {
    disabledTests = (o.disabledTests or [ ]) ++ [ "test_output_isatty" ];
  });
}
