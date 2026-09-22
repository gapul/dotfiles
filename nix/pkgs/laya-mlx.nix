# laya-mlx: MLX runtime for the Laya typed-decision models (choice / score / noul
# answered in one encoder pass; ~8-20 ms per question on this M3). Not on nixpkgs,
# so it is taken as the pure-Python wheel from PyPI.
#
# mlx is NOT taken from nixpkgs: that build is CPU-only, because the Metal shader
# compiler is closed source and unavailable in the sandbox (see the note in
# pkgs/development/python-modules/mlx). Measured here that made laya-mlx ~3.5x
# slower. Apple's own PyPI wheels ship the precompiled Metal kernels (mlx-metal),
# so they are carried as binaries, the same rule as any other signed upstream
# release. The macosx_26_0 wheels need macOS 26+; python must stay on 3.13 for
# the cp313 wheel to match.
#
# Weights are downloaded on first use into ~/.cache/huggingface (not in the store).
{
  lib,
  python3Packages,
}:
let
  mlxVersion = "0.32.2";
  mlx-metal = python3Packages.buildPythonPackage rec {
    pname = "mlx-metal";
    version = mlxVersion;
    format = "wheel";
    src = python3Packages.fetchPypi {
      pname = "mlx_metal";
      inherit version format;
      dist = "py3";
      python = "py3";
      abi = "none";
      platform = "macosx_26_0_arm64";
      hash = "sha256-5qvqyaxSZYMMnBVBtvlum+N6hcJEZ2OkatRmxjo4N6s=";
    };
    meta.platforms = [ "aarch64-darwin" ];
  };
  mlx = python3Packages.buildPythonPackage rec {
    pname = "mlx";
    version = mlxVersion;
    format = "wheel";
    src = python3Packages.fetchPypi {
      inherit pname version format;
      dist = "cp313";
      python = "cp313";
      abi = "cp313";
      platform = "macosx_26_0_arm64";
      hash = "sha256-34x15Qneho/KFI3+s42SzpVu7Thlach8rrcr0W0taWI=";
    };
    dependencies = [ mlx-metal ];
    # core.*.so looks for libmlx.dylib at @rpath = mlx/lib next to itself; pip
    # merges both wheels into one site-packages, nix keeps them apart.
    postInstall = ''
      ln -s ${mlx-metal}/${python3Packages.python.sitePackages}/mlx/lib \
        $out/${python3Packages.python.sitePackages}/mlx/lib
    '';
    pythonImportsCheck = [ "mlx.core" ];
    meta.platforms = [ "aarch64-darwin" ];
  };
in
python3Packages.buildPythonApplication rec {
  pname = "laya-mlx";
  version = "0.2.0";
  format = "wheel";

  src = python3Packages.fetchPypi {
    pname = "laya_mlx";
    inherit version format;
    dist = "py3";
    python = "py3";
    hash = "sha256-GoCgzHnFW+gI3gsSCKFyVmIJtXgNeWuY2GI16c8zUYc=";
  };

  dependencies = with python3Packages; [
    huggingface-hub
    mlx
    numpy
    tokenizers
  ];

  pythonImportsCheck = [ "laya_mlx" ];

  meta = {
    description = "Native MLX runtime for Laya typed decision models";
    homepage = "https://github.com/mizorewww/laya-mlx";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "laya-mlx";
  };
}
