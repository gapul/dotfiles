# carla (git master ≈2.6-dev) を aarch64-darwin 向けに backend のみビルドする試み。
# zrythm は carla-host-plugin(>=2.6) と carla-discovery-native を必要とする。
{ pkgs }:
let
  lib = pkgs.lib;
  # Linux 専用の音声バックエンドを buildInputs から除去
  dropNames = [
    "alsa-lib"
    "libpulseaudio"
    "jack2"
    "libjack2"
  ];
  keep = drv: !(lib.any (n: lib.hasInfix n (drv.pname or drv.name or "")) dropNames);
in
(pkgs.carla.override {
  withFrontend = false; # Qt フロントエンド不要（zrythm は backend のみ利用）
  withQt = false;
  withGtk3 = false;
}).overrideAttrs
  (o: {
    # zrythm が要求する >=2.6.0 を満たす git master 版に差し替え（zrythm 側 pin と同一 rev）
    version = "unstable-2024-04-26";
    src = pkgs.fetchFromGitHub {
      owner = "falkTX";
      repo = "carla";
      rev = "948991d7b5104280c03960925908e589c77b169a";
      hash = "sha256-uGAuKheoMfP9hZXsw29ec+58dJM8wMuowe95QutzKBY=";
    };
    buildInputs = builtins.filter keep o.buildInputs;
    # nixpkgs の postFixup は withFrontend=true 前提（wrapPythonPrograms /
    # carla_settings.py の patch / wrapQtApp)。backend-only ビルドではこれらの
    # ファイルが一切生成されないため丸ごと無効化する。
    # （patchShebangs/strip 等の標準 fixupPhase 処理は postFixup とは別に走るので維持される）
    # 代わりに、carla の macOS Makefile は各 dylib の install name を
    # "../../bin/foo.dylib" のような相対パス（本来の Carla.app 的な同居レイアウト前提）
    # に固定してしまうため、nix store 内では解決できない。dylib 自身の
    # install_name_tool -id をフルパスに上書きする（依存関係は他の buildInput の絶対パスの
    # ままなので触らなくてよい）。
    postFixup = ''
      for f in $(find "$out" -name '*.dylib'); do
        install_name_tool -id "$f" "$f"
      done
    '';
    meta = o.meta // {
      broken = false;
      platforms = o.meta.platforms ++ lib.platforms.darwin;
    };
  })
