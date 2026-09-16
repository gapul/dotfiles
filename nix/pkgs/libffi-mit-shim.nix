# Upstream (MIT) libffi under the file name of nixpkgs' Apple libffi, for DYLD_LIBRARY_PATH.
#
# nixpkgs builds darwin's `libffi` from Apple's fork, whose closures dlopen a separate
# libffi-trampolines.dylib. On macOS 27 that dlopen fails and every closure allocation
# aborts with "Assertion failed: (trampoline_handle) ... closures.c:258". Python callbacks
# (ctypes/cffi/pyobjc) all go through it: VOICEVOX's /frame_synthesis and generic-airtag's
# fetch.py were the two things found dead (2026-09-17).
#
# Swapping `libffi` for `libffiReal` in nixpkgs would rebuild python and everything above
# it, so instead the affected program is started with DYLD_LIBRARY_PATH pointing here: dyld
# resolves libffi.7.dylib by leaf name and finds upstream libffi (which keeps its trampoline
# page inside its own text segment) under that name. Compatibility checks pass (3.8.0's
# current version 14 > the 9 the consumers were linked against). The environment must reach
# the process directly: /usr/bin/nohup, /usr/bin/env and other SIP-restricted binaries strip
# DYLD_* before exec.
{ runCommand, libffiReal }:
runCommand "libffi-mit-shim" { } ''
  mkdir -p $out/lib
  ln -s ${libffiReal}/lib/libffi.8.dylib $out/lib/libffi.7.dylib
''
