{ pkgs, user, ... }:
# The CPU-experiment board (Digilent Nexys A7-100T) lives on this box so it can be programmed and
# run from anywhere over the tailnet: Vivado builds the bitstream elsewhere (the laptop), this side
# only writes it over JTAG with openFPGALoader and runs the course's server.py on the UART.
#
# Access goes through a group, not uaccess: uaccess grants the user sitting at a seat, and nobody
# sits at this one. The FT2232's UART half is already dialout (root:dialout 0660 by default); the
# JTAG half is the raw USB device, which udev would otherwise leave root-only.
{
  environment.systemPackages = [ pkgs.openfpgaloader ];

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{manufacturer}=="Digilent", GROUP="dialout", MODE="0660"
  '';

  users.users.${user.username}.extraGroups = [ "dialout" ];
}
