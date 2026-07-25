{
  pkgs,
  preservation,
  user,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "dotfiles-preservation-smoke";

  nodes.machine =
    { lib, ... }:
    {
      imports = [ preservation.nixosModules.default ];

      # preservation は systemd initrd を必須とする（module.nix の assertion）。
      boot.initrd.systemd.enable = true;

      preservation.enable = true;
      preservation.preserveAt."/persistent" = {
        directories = [
          "/etc/NetworkManager/system-connections"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/lib/sbctl"
          "/var/lib/tailscale"
        ];
        # SSH ホスト鍵は「/etc/ssh ディレクトリごと bind mount」ではなく、
        # 個々の鍵ファイルを symlink + configureParent で永続化する。
        # /etc/ssh をまるごと空ボリュームで覆うと NixOS 生成の sshd_config 等が
        # 隠れて sshd が起動できなくなるため（upstream 推奨の作法）。
        files = [
          {
            file = "/etc/ssh/ssh_host_rsa_key";
            how = "symlink";
            configureParent = true;
          }
          {
            file = "/etc/ssh/ssh_host_ed25519_key";
            how = "symlink";
            configureParent = true;
          }
        ];
        users.${user.username}.directories = [
          ".config/sops/age"
          ".local/share/atuin"
          ".local/share/zoxide"
        ];
      };

      networking.networkmanager.enable = true;
      services.openssh.enable = true;
      users.users.${user.username} = {
        isNormalUser = true;
        createHome = true;
      };

      # VMではmachine-id commitの永続ディスク検証を行わない。
      systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

      # 永続ストレージは実ブロックデバイス上の実ファイルシステムにする（upstream の
      # tests/basic.nix と同じ方式）。tmpfs は揮発性で「永続」ボリュームの裏付けとして
      # 不適切なうえ、neededForBoot + initrd systemd での mount 移送が不安定になりがち。
      # 実 fs なら /persistent が確実に mountpoint になる。
      virtualisation = {
        memorySize = 2048;
        emptyDiskImages = [ 512 ];
        fileSystems."/persistent" = {
          device = "/dev/vdb";
          fsType = "ext4";
          autoFormat = true;
          neededForBoot = true;
        };
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # 永続ストレージがマウントされている。
    machine.succeed("mountpoint /persistent")

    # 永続対象のシステムディレクトリが実際に bind mount になっている。
    machine.succeed("mountpoint /var/lib/nixos")

    # sshd が起動し、ホスト鍵が preservation 経由で永続ボリュームに載っている。
    machine.wait_for_unit("sshd.service")
    machine.succeed("test -L /etc/ssh/ssh_host_ed25519_key")
    machine.succeed("test -s /persistent/etc/ssh/ssh_host_ed25519_key")

    # ユーザー固有の永続ディレクトリが永続ボリューム上に作られている。
    machine.succeed("test -d /persistent/home/${user.username}/.config/sops/age")

    # 永続対象ディレクトリへの書き込みが永続ボリュームに反映される。
    machine.succeed("touch /var/lib/nixos/preservation-smoke")
    machine.succeed("test -e /persistent/var/lib/nixos/preservation-smoke")
  '';
}
