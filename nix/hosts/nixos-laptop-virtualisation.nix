{ pkgs, user, ... }:
{
  # quickemu runs the VMs in ~/vm (windows-11, macos-sequoia, freebsd-15.1). quickget writes each
  # .conf with a shebang naming the quickemu store path it ran from, which garbage collection then
  # removed; the shebangs point at /run/current-system/sw/bin/quickemu instead, which this keeps.
  environment.systemPackages = [ pkgs.quickemu ];
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
