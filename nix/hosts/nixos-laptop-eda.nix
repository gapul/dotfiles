{ pkgs, ... }:
# Open-source chip design tools, after the RISC-V Day 2026 inverter workshop (GF180MCU).
# Analog: xschem -> ngspice -> klayout/magic -> netgen. Digital: Verilog -> yosys/openroad via
# librelane. PDKs are not in the store: `ciel` fetches them into ~/.ciel, e.g.
#   ciel enable --pdk-family gf180mcu <version>
# and librelane and ciel both default to that directory.
{
  environment.systemPackages = with pkgs; [
    # analog / full custom
    xschem
    ngspice
    gaw
    klayout
    magic-vlsi
    netgen-vlsi
    # digital
    iverilog
    verilator
    gtkwave
    yosys
    openroad
    librelane
    # PDK manager
    ciel
    # boards (kicad-small: without the multi-GB 3D model library)
    kicad-small
  ];

  # The PDKs' xschemrc and klayout tech files locate themselves through these.
  environment.sessionVariables = {
    PDK_ROOT = "$HOME/.ciel";
    PDK = "gf180mcuD";
  };
}
