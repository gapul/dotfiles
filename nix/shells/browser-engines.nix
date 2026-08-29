# Build environments for the two independent browser engines that can be built
# on this Mac: Ladybird (CMake + vcpkg) and Servo (mach + cargo).
#
# Neither project is packaged; these shells only assemble the toolchain their
# own build systems shell out to, so that nothing has to be installed through
# Homebrew. That matters here because darwin.nix runs Homebrew with
# `cleanup = "uninstall"`, which would remove anything a project's bootstrap
# script installed behind nix's back on the next rebuild.
#
# Both are darwin-only: they compile with Xcode's clang and reference the
# macOS SDK by absolute path.
{ pkgs }:

let
  inherit (pkgs) lib;

  # Both projects pin an exact Rust version in rust-toolchain.toml (Ladybird
  # 1.96.1, Servo 1.97.1), and only rustup reads that file. Shipping nixpkgs'
  # rustc would silently build with whatever version nixpkgs happens to carry.
  rust = pkgs.rustup;

  # GNU libtool and Apple's /usr/bin/libtool are unrelated programs that share a
  # name. nixpkgs installs GNU's as plain `libtool`, which shadows Apple's, and
  # skia's build then fails on `libtool -static -o libwuffs.a ...` -- an
  # invocation only Apple's archiver understands. Homebrew avoids the collision
  # by exposing GNU libtool as `glibtool`, and both projects' macOS instructions
  # assume that layout, so reproduce it: `libtool` stays Apple's, while GNU's
  # tools keep the names autotools actually searches for.
  libtoolShim = pkgs.runCommand "libtool-macos-layout" { } ''
    mkdir -p $out/bin
    ln -s /usr/bin/libtool $out/bin/libtool
    ln -s ${pkgs.libtool}/bin/libtool $out/bin/glibtool
    ln -s ${pkgs.libtool}/bin/libtoolize $out/bin/glibtoolize
    ln -s ${pkgs.libtool}/bin/libtoolize $out/bin/libtoolize
  '';

  # autoreconf still needs GNU libtool's m4 macros, which the shim does not carry.
  aclocalPath = lib.concatStringsSep ":" [
    "${pkgs.libtool}/share/aclocal"
    "${pkgs.autoconf-archive}/share/aclocal"
    "${pkgs.automake}/share/aclocal"
  ];

  commonTools = [
    pkgs.ninja
    pkgs.nasm
    pkgs.autoconf
    pkgs.autoconf-archive
    pkgs.automake
    libtoolShim
    pkgs.pkg-config
    pkgs.ccache
    pkgs.cmake
    rust
  ];

  # Shared by both shells: keep every nix compiler out of PATH and build with
  # Xcode's clang. See the per-shell notes for why each project needs this.
  appleToolchainHook = ''
    export CC=/usr/bin/clang
    export CXX=/usr/bin/clang++
    export ACLOCAL_PATH="${aclocalPath}''${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
    export PATH="${libtoolShim}/bin:$PATH"
  '';
in
{
  # Ladybird: ./Meta/ladybird.py build
  #
  # mkShellNoCC is deliberate. Ladybird's Meta/Utils/find_compiler.py explicitly
  # rejects clang 21 on macOS -- it links against LLVM's libc++ and then fails on
  # std::__1::__hash_memory -- and prefers Xcode clang when it finds one. Putting
  # a nix clang in PATH would offer it a compiler it refuses to use.
  ladybird = pkgs.mkShellNoCC {
    packages = commonTools ++ [
      pkgs.python3
      # vcpkg's bootstrap shells out to these three.
      pkgs.zip
      pkgs.unzip
      pkgs.curl
    ];

    shellHook = appleToolchainHook + ''
      echo "ladybird shell: cc=$(clang --version | head -1)"
      echo "                libtool=$(readlink -f "$(command -v libtool)")"
    '';
  };

  # Servo: ./mach build --release --media-stack dummy
  #
  # The repo ships its own shell.nix, but it cannot evaluate on darwin -- udev
  # and the X11 stack sit in its unconditional buildInputs -- so this shell
  # replaces it.
  #
  # Do NOT set MACH_USE_NIX: it makes ./mach re-exec itself into
  # `nix-shell shell.nix`, which is exactly the file that cannot evaluate.
  # Homebrew is only ever reached through `mach bootstrap`, so the rule is
  # simply never to run that; its Brewfile asks for cmake and pkg-config, both
  # of which this shell already provides.
  #
  # `--media-stack dummy` is the workable default on macOS: Servo accepts only
  # the official GStreamer .pkg there, which is a sudo install into
  # /Library/Frameworks and therefore outside declarative management. Without it
  # the build fails at link time rather than falling back.
  servo = pkgs.mkShellNoCC {
    packages = commonTools ++ [
      pkgs.uv
      # .python-version pins 3.11, so uv symlinks this interpreter instead of
      # downloading a build of its own.
      pkgs.python311
      pkgs.gnumake # mozjs needs GNU make; Apple ships make 3.81
      pkgs.m4
      pkgs.perl
      pkgs.yasm
      pkgs.openssl
    ];

    shellHook = appleToolchainHook + ''
      # mozangle and mozjs run their headers through bindgen, which drives
      # libclang directly instead of the clang driver. Nothing supplies the
      # macOS SDK sysroot that way, and the parse dies on `#include <array>`.
      # Point bindgen at Xcode's own libclang, matching CC/CXX, and hand it the
      # sysroot explicitly.
      export SDKROOT="''${SDKROOT:-$(xcrun --show-sdk-path)}"
      export LIBCLANG_PATH="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib"
      export BINDGEN_EXTRA_CLANG_ARGS="-isysroot $SDKROOT"
      echo "servo shell: rust via rustup -- never run ./mach bootstrap (it calls brew)"
    '';
  };
}
