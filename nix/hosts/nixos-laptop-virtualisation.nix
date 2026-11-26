{ pkgs, user, ... }:
let
  # Redox OS: quickget does not know it, and upstream only keeps the latest daily image (the
  # 0.9.0 release is from 2024), so a pinned fetchurl would 404 within days. The image is
  # downloaded at run time into the quickemu subvolume, checked against upstream's SHA256SUM,
  # and kept as a writable disk. `redox-vm update [desktop|demo|server]` replaces it.
  # Flags follow upstream's mk/qemu.mk for x86_64: q35, UEFI, xhci + usb-tablet.
  redoxVm = pkgs.writeShellApplication {
    name = "redox-vm";
    runtimeInputs = [
      pkgs.curl
      pkgs.zstd
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.qemu_kvm
    ];
    text = ''
      base=https://static.redox-os.org/img/x86_64
      dir="''${XDG_DATA_HOME:-$HOME/.local/share}/quickemu/redox"
      img="$dir/harddrive.img"
      mkdir -p "$dir"

      update() {
        variant=''${1:-desktop}
        sums=$(curl -fsSL "$base/SHA256SUM")
        line=$(grep -E "\*redox_''${variant}_x86_64_.*_harddrive\.img\.zst$" <<<"$sums") || {
          echo "redox-vm: no $variant image in $base/SHA256SUM" >&2
          exit 1
        }
        file=''${line#*\*}
        echo "redox-vm: downloading $file"
        curl -fL --progress-bar -o "$dir/$file" "$base/$file"
        (cd "$dir" && sha256sum -c <<<"$line")
        zstd -d -f -o "$img.new" "$dir/$file"
        rm -f "$dir/$file"
        mv "$img.new" "$img"
        echo "$file" >"$dir/VERSION"
      }

      case "''${1:-run}" in
        update) update "''${2:-desktop}" ;;
        run)
          [ -f "$img" ] || update desktop
          echo "redox-vm: booting $(cat "$dir/VERSION" 2>/dev/null || echo "$img")"
          if [ -w /dev/kvm ]; then accel=(-enable-kvm -cpu host); else accel=(-cpu max); fi
          exec qemu-system-x86_64 -name "Redox OS" -machine q35 "''${accel[@]}" \
            -smp 4 -m 2048 \
            -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
            -drive file="$img",format=raw \
            -device qemu-xhci -device usb-tablet \
            -netdev user,id=net0 -device e1000,netdev=net0 \
            -device ich9-intel-hda -device hda-output \
            -vga std -serial stdio
          ;;
        *) echo "usage: redox-vm [run | update [desktop|demo|server]]" >&2; exit 2 ;;
      esac
    '';
  };

  # SerenityOS publishes no disk images; the only way in is building it. Upstream ships a
  # flake devShell with the whole toolchain, so this clones the tree into ~/Developer and runs
  # `Meta/serenity.sh run` inside it. The first run builds its GCC cross-toolchain and the OS
  # (hours, tens of GB under Build/ and Toolchain/); later runs are incremental.
  serenityVm = pkgs.writeShellApplication {
    name = "serenity-vm";
    runtimeInputs = [ pkgs.git ];
    text = ''
      src="$HOME/Developer/github.com/SerenityOS/serenity"
      if [ ! -d "$src/.git" ]; then
        git clone --filter=blob:none https://github.com/SerenityOS/serenity.git "$src"
      fi
      case "''${1:-run}" in
        update) git -C "$src" pull --ff-only ;;
        run) cd "$src" && exec nix develop --command Meta/serenity.sh run x86_64 ;;
        *) echo "usage: serenity-vm [run | update]" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  # quickemu runs the VMs in ~/.local/share/quickemu (windows-11, macos-sequoia, freebsd-15.1).
  # quickget writes each .conf with a shebang naming the quickemu store path it ran from, which
  # garbage collection then removed; the shebangs point at /run/current-system/sw/bin/quickemu
  # instead, which this keeps.
  environment.systemPackages = [
    pkgs.quickemu
    redoxVm
    serenityVm
  ];
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

  # quickemu's VMs live in ~/.local/share/quickemu (app data, kept out of restic), in a
  # subvolume of its own so /home's hourly snapper snapshots do not pin every rewritten block
  # of the disk images, and with No_COW (+C) so new images inherit it: copy-on-write under a
  # VM's small random writes fragments the image. Each .conf runs from anywhere; quickemu
  # changes into the .conf's directory when the relative disk path does not resolve.
  home-manager.users.${user.username}.systemd.user.tmpfiles.rules = [
    "v %h/.local/share/quickemu 0755 - - -"
    "h %h/.local/share/quickemu - - - - +C"
  ];
}
