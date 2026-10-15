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
}
