{ config, pkgs, ... }:
# A general-purpose Ubuntu 24.04 distrobox (nixos-laptop only), for software that assumes
# apt and an FHS layout. It comes with ROS 2 Jazzy, which is what it was made for: Ubuntu
# rather than nix-ros-overlay because the official tutorials assume apt, and following them
# verbatim matters more than reproducibility while learning.
#
# Nothing is built at rebuild or login: the first install pulls ~1 GB and takes half an
# hour, so it is started by hand.
#   distrobox assemble create --file ~/.config/distrobox/containers.ini
#   distrobox enter ubuntu   # the first entry runs the apt install below and takes a while
# Changing the container below takes `distrobox assemble create --replace --file ...`,
# which recreates the container; the container's home survives it.
#
# The container gets its own home so tutorials can edit ~/.bashrc without touching the
# home-manager one. Its root filesystem is not declarative: apt changes made inside persist
# until the container is replaced, so anything worth keeping belongs in the list below.
let
  # The container's home holds only the shell rc files the init hook keeps writing, so it is
  # app data, not work: under XDG_DATA_HOME rather than loose in ~ (it was ~/distrobox/ubuntu
  # until 2026-10-18). The host home is mounted as well, so workspaces belong in ~/Developer.
  boxHome = "${config.xdg.dataHome}/distrobox/ubuntu";

  # The hooks run as root inside the container, which sees the host's /nix and home. The
  # container keeps the hook command it was created with, so it calls them through fixed
  # paths in ~/.config rather than store paths: editing a hook then only needs a rebuild,
  # not a recreated container, and a garbage-collected store path cannot break its start.
  # They are plain sh using only the container's own tools. Writing them as files also keeps
  # them clear of distrobox-assemble, which strips ` #` comments from hook lines and
  # expands `$` on the host.
  hookDir = "${config.xdg.configHome}/distrobox/ubuntu";

  # Every start, before distrobox installs its packages: add the ROS apt source once.
  # The source package then updates itself through apt, so the pinned version only
  # matters for the first install.
  preInit = pkgs.writeText "ubuntu-box-pre-init.sh" ''
    set -eu
    [ -e /etc/apt/sources.list.d/ros2.sources ] && exit 0
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl
    curl -fsSL -o /tmp/ros2-apt-source.deb \
      https://github.com/ros-infrastructure/ros-apt-source/releases/download/1.3.0/ros2-apt-source_1.3.0.noble_all.deb
    apt-get install -y /tmp/ros2-apt-source.deb
    rm -f /tmp/ros2-apt-source.deb
  '';

  # Every start, after the packages: make the home's shell rc files load ROS. Appends the
  # line when it is absent rather than writing whole files, because distrobox has already
  # copied Ubuntu's /etc/skel/.bashrc in by then. distrobox installs the host's login shell
  # (zsh) in the container, and a .zshrc also stops zsh's first-run wizard.
  # The host's ZDOTDIR (~/.config/zsh) is passed through and the host home is mounted, so
  # zsh would load the home-manager config instead; /etc/zsh/zshenv is read before ZDOTDIR
  # is consulted, so pointing it back at the container's home there takes effect.
  init = pkgs.writeText "ubuntu-box-init.sh" ''
    set -eu
    grep -qxF 'ZDOTDIR=$HOME' /etc/zsh/zshenv || echo 'ZDOTDIR=$HOME' >> /etc/zsh/zshenv
    owner=$(stat -c %u:%g ${boxHome})
    for shell in bash zsh; do
      rc=${boxHome}/.''${shell}rc
      line="source /opt/ros/jazzy/setup.$shell"
      grep -qxF "$line" "$rc" 2>/dev/null && continue
      printf '%s\n' "$line" >> "$rc"
      chown "$owner" "$rc"
    done
  '';
in
{
  xdg.configFile."distrobox/ubuntu/pre-init.sh".source = preInit;
  xdg.configFile."distrobox/ubuntu/init.sh".source = init;

  programs.distrobox = {
    enable = true;
    # hosts/nixos-laptop.nix already installs distrobox system-wide. With no package the
    # module also skips its login-time assemble unit, which would start the ~1 GB pull
    # unannounced.
    package = null;
    containers.ubuntu = {
      image = "docker.io/library/ubuntu:24.04";
      home = boxHome;
      pre_init_hooks = "sh ${hookDir}/pre-init.sh";
      # desktop: rviz2, rqt and the tutorial demos. ros-gz: Gazebo Harmonic and its bridge.
      additional_packages = "ros-jazzy-desktop ros-dev-tools ros-jazzy-ros-gz";
      init_hooks = "sh ${hookDir}/init.sh";
    };
  };
}
