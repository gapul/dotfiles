# hex 文字列 "rrggbb" → "r g b" (0-1 float, スペース区切り) へ変換するヘルパー。
# sioyek など「色を 0-1 float で持つ」ツールに rose-pine.nix の hex を
# 単一ソースのまま流すために使う (マジックナンバー排除の方針を維持)。
#
# 使い方:  rgb = import ./hex-rgb.nix { inherit lib; };  rgb "e0def4" => "0.878431 0.870588 0.956863"
{ lib }:
let
  hexDigit =
    ch:
    {
      "0" = 0;
      "1" = 1;
      "2" = 2;
      "3" = 3;
      "4" = 4;
      "5" = 5;
      "6" = 6;
      "7" = 7;
      "8" = 8;
      "9" = 9;
      "a" = 10;
      "b" = 11;
      "c" = 12;
      "d" = 13;
      "e" = 14;
      "f" = 15;
    }
    .${lib.toLower ch};
  # 2 桁 hex ("e0") → 0-255 の整数
  byte = pair: (hexDigit (builtins.substring 0 1 pair)) * 16 + hexDigit (builtins.substring 1 1 pair);
  # 0-255 → 0-1 float の文字列 (255.0 が float なので結果も float)
  norm = n: builtins.toString (n / 255.0);
in
hex:
"${norm (byte (builtins.substring 0 2 hex))} ${norm (byte (builtins.substring 2 2 hex))} ${
  norm (byte (builtins.substring 4 2 hex))
}"
