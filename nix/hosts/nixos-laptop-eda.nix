{ pkgs, ... }:
# Open-source chip design tools, after the RISC-V Day 2026 inverter workshop (GF180MCU): enough to
# redo its schematic -> simulation -> layout -> DRC/LVS flow, all of which klayout covers.
# Digital flows (yosys/openroad/librelane) belong in a project's own devShell, pinned to it.
# PDKs are not in the store: `ciel` fetches them into ~/.ciel, e.g.
#   ciel enable --pdk-family gf180mcu <version>
{
  environment.systemPackages = with pkgs; [
    xschem
    ngspice
    klayout
    ciel
    iverilog
    gtkwave
  ];

  # The PDKs' xschemrc and klayout tech files locate themselves through these.
  environment.sessionVariables = {
    PDK_ROOT = "$HOME/.ciel";
    PDK = "gf180mcuD";
  };
}
