# Helper to convert a hex string "rrggbb" → "r g b" (0-1 float, space-separated).
# Used to feed theme.nix's hex, kept as a single source, into tools that "hold colors
# as 0-1 floats" like sioyek (maintaining the no-magic-numbers policy).
#
# Usage:  rgb = import ./hex-rgb.nix { inherit lib; };  rgb "e0def4" => "0.878431 0.870588 0.956863"
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
  # 2-digit hex ("e0") → integer 0-255
  byte = pair: (hexDigit (builtins.substring 0 1 pair)) * 16 + hexDigit (builtins.substring 1 1 pair);
  # 0-255 → 0-1 float string (255.0 is a float so the result is float too)
  norm = n: builtins.toString (n / 255.0);
in
hex:
"${norm (byte (builtins.substring 0 2 hex))} ${norm (byte (builtins.substring 2 2 hex))} ${
  norm (byte (builtins.substring 4 2 hex))
}"
