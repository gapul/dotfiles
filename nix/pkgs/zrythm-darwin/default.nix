# zrythm 1.0.0 (DAW) を aarch64-darwin 向けに自前ビルドする。
#
# nixpkgs は zrythm を `broken = isDarwin` としており、必須依存の carla も
# `platforms = linux`。そのため素の pkgs では eval/build できない。ここでは
# 同じ nixpkgs を allowUnsupportedSystem/allowBroken 付きで再インスタンス化し、
# zrythm.nix / carla.nix の override 群(carla を backend-only で darwin 移植・
# Linux 音声backend除去・install_name 修正・GDK_BACKEND=macos 既定注入 等)を
# 適用して、起動可能な zrythm を得る。詳細は zrythm.nix / carla.nix のコメント参照。
#
# 使い方(home-manager, darwin): home.packages に
#   (import ../pkgs/zrythm-darwin { inherit pkgs; })
{ pkgs }:
let
  # carla の transitive dep に darwin 非対応(meta.platforms が狭い)ものがあり、
  # allowUnsupportedSystem 無しでは eval が落ちる。同一 nixpkgs を再構成して回避。
  pkgs' = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    overlays = pkgs.overlays or [ ];
    config = (pkgs.config or { }) // {
      allowUnsupportedSystem = true;
      allowBroken = true;
    };
  };
in
import ./zrythm.nix { pkgs = pkgs'; }
