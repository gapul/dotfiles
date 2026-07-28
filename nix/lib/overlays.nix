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
  # tailscale 1.98.9: 上流 nixpkgs (nixos-26.05) の vendorHash が誤っており
  # go-modules FOD が hash mismatch でビルド不能:
  #   specified sha256-mbxLXR2… / got sha256-Sd2iLJ7…
  # 正しい値に上書き (go-modules は platform 非依存)。上流修正後は削除可。
  # nixos-laptop でのみ tailscale を使う (macOS は Tailscale.app)。
  tailscale = prev.tailscale.overrideAttrs (_: {
    vendorHash = "sha256-Sd2iLJ7eDfDYdIRuW4xuiKgzhQWJWGAnz97FJWrVRlE=";
  });

  pre-commit = prev.pre-commit.overridePythonAttrs (o: {
    disabledTests = (o.disabledTests or [ ]) ++ [
      "test_output_isatty"
      # git clone の pack ファイルコピーが nix sandbox で稀に race し
      # "failed to copy file ... No such file or directory" で落ちる。
      # macos-14 の om ci(darwin) を断続的に赤にするため deselect。
      "test_pre_push_integration"
    ];
  });
}
