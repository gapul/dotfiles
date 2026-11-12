{
  config,
  pkgs,
  lib,
  user,
  ...
}:
# AirPlay is announced and reachable only while UxPlay runs. Starting the user's uxplay service
# (home/ios-integration.nix) starts airplay-publish below, which switches Avahi to a config that
# publishes and opens UxPlay's ports on the Wi-Fi interface; stopping uxplay stops it again.
# Otherwise Avahi still resolves .local names (printers and the like) but publishes nothing, not
# even this machine's name, which DHCP is already kept from sending (dhcp-send-hostname).
let
  wifi = "wlp0s20f3";
  avahi = config.services.avahi;
  flag = "/run/airplay/on";
  # Set while airplay-publish restarts Avahi itself, so the restart hook below leaves uxplay be.
  toggling = "/run/airplay/toggling";

  # The same INI rendering as nixos/modules/services/networking/avahi-daemon.nix.
  ini = pkgs.formats.ini {
    mkKeyValue = lib.generators.mkKeyValueDefault {
      mkValueString =
        v: if lib.isBool v then lib.boolToYesNo v else lib.generators.mkValueStringDefault { } v;
    } "=";
    listToValue = lib.concatMapStringsSep ", " (lib.generators.mkValueStringDefault { });
  };
  avahiConf =
    publishing:
    ini.generate "avahi-daemon-${if publishing then "airplay" else "quiet"}.conf" (
      lib.recursiveUpdate (lib.filterAttrsRecursive (_: v: v != null) avahi.settings) {
        publish = {
          disable-publishing = !publishing;
          disable-user-service-publishing = !publishing;
          publish-addresses = publishing;
        };
      }
    );

  # Inserted at the top of the NixOS firewall's input chain; the deletes mirror the inserts.
  rules = action: ''
    for ipt in iptables ip6tables; do
      $ipt -w ${action} nixos-fw -i ${wifi} -p tcp --dport 7000:7002 -j nixos-fw-accept
      $ipt -w ${action} nixos-fw -i ${wifi} -p udp --dport 7000:7002 -j nixos-fw-accept
    done
  '';
in
{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    # The baseline (and /etc/avahi/avahi-daemon.conf) is the quiet one; the daemon itself reads
    # whichever config pick-conf links below.
    settings.publish.disable-publishing = true;
    settings.server.allow-interfaces = [ wifi ]; # Do not advertise the USB tethering address.
  };

  systemd.services.avahi-daemon = {
    serviceConfig = {
      ExecStartPre = [
        "+${pkgs.writeShellScript "avahi-pick-conf" ''
          ${pkgs.coreutils}/bin/mkdir -p /run/airplay
          if [ -e ${flag} ]; then conf=${avahiConf true}; else conf=${avahiConf false}; fi
          ${pkgs.coreutils}/bin/ln -sfn "$conf" /run/airplay/avahi-daemon.conf
        ''}"
      ];
      ExecStart = lib.mkForce "${avahi.package}/sbin/avahi-daemon --syslog -f /run/airplay/avahi-daemon.conf";
    };
    # A system switch that restarts Avahi drops UxPlay's registration; restart UxPlay to register
    # again, unless airplay-publish is the one restarting Avahi (uxplay is starting or stopping).
    postStart = ''
      if [ -e ${flag} ] && [ ! -e ${toggling} ]; then
        ${pkgs.systemd}/bin/systemctl --user --machine=${user.username}@.host --no-block try-restart uxplay.service || true
      fi
    '';
  };

  systemd.services.airplay-publish = {
    description = "Announce AirPlay over mDNS and open its ports while UxPlay runs";
    path = [
      config.networking.firewall.package
      pkgs.coreutils
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /run/airplay
      touch ${toggling} ${flag}
      ${rules "-I"}
      systemctl restart avahi-daemon.service
      rm -f ${toggling}
    '';
    preStop = ''
      touch ${toggling}
      rm -f ${flag}
      ${rules "-D"} 2>/dev/null || true
      systemctl restart avahi-daemon.service
      rm -f ${toggling}
    '';
  };

  # A firewall reload (every switch) flushes nixos-fw; put the rules back while AirPlay is on.
  networking.firewall.extraCommands = ''
    if [ -e ${flag} ]; then
      ${rules "-I"}
    fi
  '';

  # The uxplay user service starts and stops airplay-publish itself.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "airplay-publish.service" &&
          subject.user == "${user.username}") {
        var verb = action.lookup("verb");
        if (verb == "start" || verb == "stop") return polkit.Result.YES;
      }
    });
  '';
}
