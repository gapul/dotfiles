# HackiOS (https://github.com/oosexgang/hackios-xnu-kernel): Apple's XNU built from its public
# source with its own loader and drivers, booting the stock iOS 16.5 user space under QEMU on
# x86-64 Linux. Used here as an iOS Simulator stand-in for apps built with xtool (pkgs/xtool.nix).
#
# Only the repository's scripts (with local.patch and rc.jobs.dev) go into the store. `hackios
# setup` copies them to ~/.local/share/hackios and builds the images there from Apple's IPSW, so
# no iOS file ever reaches the store or a binary cache.
#
# local.patch: `chmod u+w` on the UEFI variables copied out of the read-only store, a host port
# (QEMU_SSH_PORT, default 2222) forwarded to the guest's sshd, and EXTRA_APPS for build.sh.
# The shebangs are #!/bin/bash, which NixOS lacks.
{
  lib,
  applyPatches,
  fetchFromGitHub,
  runCommand,
  writeShellApplication,
  _7zz,
  binutils,
  coreutils,
  curl,
  findutils,
  gawk,
  gcc,
  gnused,
  gnutar,
  ldid,
  lz4,
  openssh,
  python3,
  qemu,
  rsync,
  zstd,
}:
let
  src = applyPatches {
    name = "hackios-src";
    src = fetchFromGitHub {
      owner = "oosexgang";
      repo = "hackios-xnu-kernel";
      rev = "88513176b1e96ecf0b764cd62c6f4e6ac71345e3";
      hash = "sha256-3Mg9Ea3ENt/VYdgifobzsK58L4CikuLD9P8G6J0M7Wk=";
    };
    patches = [ ./local.patch ];
    postPatch = ''
      cp ${./rc.jobs.dev} userland/rc.jobs.dev
      grep -rlI '^#!/bin/bash' --exclude-dir=.git . | xargs sed -i '1s|^#!/bin/bash|#!/usr/bin/env bash|'
    '';
  };

  # the scripts call 7-Zip as `7z`; it has to be 23 or newer to read APFS
  sevenZip = runCommand "7z-as-7zz" { } ''
    mkdir -p $out/bin
    ln -s ${_7zz}/bin/7zz $out/bin/7z
  '';
in
writeShellApplication {
  name = "hackios";
  runtimeInputs = [
    sevenZip
    binutils
    coreutils
    curl
    findutils
    gawk
    gcc
    gnused
    gnutar
    ldid
    lz4
    openssh
    python3
    qemu
    rsync
    zstd
  ];
  text =
    builtins.replaceStrings
      [ "@src@" "@efi@" "@vars@" ]
      [
        "${src}"
        "${qemu}/share/qemu/edk2-aarch64-code.fd"
        "${qemu}/share/qemu/edk2-arm-vars.fd"
      ]
      (builtins.readFile ./hackios.sh);
  meta = {
    description = "iOS 16.5 under QEMU through HackiOS, with app push over ssh";
    homepage = "https://github.com/oosexgang/hackios-xnu-kernel";
    license = with lib.licenses; [
      mit
      apsl20
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "hackios";
  };
}
