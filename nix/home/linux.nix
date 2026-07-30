{
  user,
  ...
}:
{
  # Linux common (applies to NixOS desktop / server / WSL alike)
  # WSL-specific interop is split into home/wsl.nix

  home.homeDirectory = "/home/${user.username}";

  # Recognize fonts via fontconfig (equivalent to macOS Font Book)
  fonts.fontconfig.enable = true;

  # No GUI-oriented home.file running on Linux for now
  # Intended to be added when launching X11/Wayland on NixOS / WSLg
}
