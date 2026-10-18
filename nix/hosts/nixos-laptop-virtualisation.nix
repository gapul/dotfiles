{ user, ... }:
{
  programs.virt-manager.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      runAsRoot = false;
      swtpm.enable = true;
    };
  };
  # swtpm_setup runs as tss and cannot create its CA directory under /var/lib.
  systemd.tmpfiles.rules = [ "d /var/lib/swtpm-localca 0750 tss tss -" ];
  users.users.${user.username}.extraGroups = [ "libvirtd" ];

  # quickemu's VMs live in ~/.local/share/quickemu (app data, kept out of restic), in a
  # subvolume of its own so /home's hourly snapper snapshots do not pin every rewritten block
  # of the disk images, and with No_COW (+C) so new images inherit it: copy-on-write under a
  # VM's small random writes fragments the image. Each .conf runs from anywhere; quickemu
  # changes into the .conf's directory when the relative disk path does not resolve.
  home-manager.users.${user.username}.systemd.user.tmpfiles.rules = [
    "v %h/.local/share/quickemu 0755 - - -"
    "h %h/.local/share/quickemu - - - - +C"
  ];
}
