{ config, pkgs, lib, user, ... }: {
  # Linux 共通 (NixOS desktop / server / WSL すべてに適用される)
  # WSL 専用 interop は home/wsl.nix に分離

  home.homeDirectory = "/home/${user.username}";

  # fontconfig 経由でフォントを認識(macOS の Font Book 等価)
  fonts.fontconfig.enable = true;

  # Linux で動く GUI 寄りの home.file は今は無し
  # NixOS / WSLg で X11/Wayland 起動するときに追加する想定
}
