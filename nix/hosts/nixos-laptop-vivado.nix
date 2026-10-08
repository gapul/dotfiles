{ pkgs, user, ... }:
# AMD/Xilinx Vivado 2020.2 for the FPGA coursework (the same version the old Windows side had,
# see docs/windows-roadmap.md P9-41). Nix only provides the surroundings: the tool itself is
# installed by hand from AMD's "All OS installer Single-File Download" into installDir, because
# the download sits behind an AMD login and an export-control form, and at ~40 GB it does not
# belong in the store anyway.
#
# Vivado is a prebuilt FHS program (it dlopens libtinfo.so.5, libcrypt.so.1, X11 and GTK from
# /usr/lib), so everything runs inside one buildFHSEnv. The installer runs in it too:
#   xilinx-shell -c '/path/to/Xilinx_Unified_2020.2_1118_1232/xsetup'
let
  installDir = "/opt/Xilinx";
  version = "2020.2";

  fhs =
    name: runScript:
    pkgs.buildFHSEnv {
      inherit name runScript;
      targetPkgs =
        p: with p; [
          bash
          coreutils
          which
          procps
          nettools # hostname/ifconfig, read by the license manager for the host ID
          lsb-release # the installer refuses to start without it
          stdenv.cc.cc.lib
          zlib
          ncurses5 # libtinfo.so.5
          libxcrypt-legacy # libcrypt.so.1, which glibc no longer ships
          libuuid
          libusb1 # hw_server, for the JTAG cables
          glib
          gtk2
          gtk3
          fontconfig
          freetype
          libx11
          libxext
          libxrender
          libxtst
          libxi
          libxft
          libxcb
          graphviz
          gnumake
          # xsim compiles the elaborated design to native code and insists on /usr/bin/gcc
          # ("XSIM 43-3388 /usr/bin/gcc not found"), so behavioral simulation needs a compiler here.
          gcc
          binutils
          unzip
        ];
      profile = ''
        # The 2020.2 Tcl/Java runtime misparses numbers under non-English locales.
        export LC_ALL=en_US.UTF-8
        # Java AWT draws an empty grey window under a non-reparenting WM such as Hyprland.
        export _JAVA_AWT_WM_NONREPARENTING=1
        # Vivado's own binaries resolve libraries through the loader's built-in search path,
        # which in the FHS env is glibc's store path, so libtinfo.so.5 under /usr/lib64 is never
        # found ("couldn't load file librdi_commontasks.so"). Its launcher prepends to this.
        export LD_LIBRARY_PATH=/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
      '';
    };
in
{
  environment.systemPackages = [
    (fhs "vivado" "${installDir}/Vivado/${version}/bin/vivado")
    (fhs "xilinx-shell" "bash") # for the installer, and for anything else under installDir
  ];

  # Owned by the user so the installer runs without root.
  systemd.tmpfiles.rules = [ "d ${installDir} 0755 ${user.username} users -" ];

  # JTAG/UART access to Digilent and Xilinx boards for the logged-in user, instead of the
  # world-writable MODE 666 that Xilinx's own install_drivers script drops into /etc/udev.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="1443", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{manufacturer}=="Digilent", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{manufacturer}=="Xilinx", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="03fd", TAG+="uaccess"
  '';
}
