{ pkgs, ... }:
let
  # UTNET (AS2501) as announced: the campus network. Only these go through the
  # tunnel; everything else this box does keeps the house's default route.
  # [address, netmask, prefix length] — vpnc-script wants all three.
  utnet = [
    [
      "130.69.0.0"
      "255.255.0.0"
      "16"
    ]
    [
      "133.11.0.0"
      "255.255.0.0"
      "16"
    ]
    [
      "157.82.0.0"
      "255.255.0.0"
      "16"
    ]
    [
      "192.51.208.0"
      "255.255.240.0"
      "20"
    ]
  ];

  python = pkgs.python3.withPackages (ps: [ ps.playwright ]);

  # openconnect's --external-browser takes a bare program and passes the URL as $1.
  browser = pkgs.writeShellScript "utokyo-vpn-browser" ''
    exec ${python}/bin/python3 ${../../configs/homelab/utokyo-vpn/sso-login.py} "$1"
  '';

  # The gateway pushes a full tunnel (default route, its own DNS, IPv6). On the
  # machine that is the house's DNS server and subnet router that would take
  # everything down, so replace the server's split list with UTNET and drop the
  # rest before handing over to the stock vpnc-script.
  routeScript = pkgs.writeShellScript "utokyo-vpn-script" ''
    unset CISCO_SPLIT_EXC INTERNAL_IP4_DNS INTERNAL_IP6_DNS CISCO_DEF_DOMAIN CISCO_SPLIT_DNS
    unset INTERNAL_IP6_ADDRESS INTERNAL_IP6_NETMASK CISCO_IPV6_SPLIT_INC
    export CISCO_SPLIT_INC=${toString (builtins.length utnet)}
    ${builtins.concatStringsSep "\n" (
      pkgs.lib.imap0 (i: r: ''
        export CISCO_SPLIT_INC_${toString i}_ADDR=${builtins.elemAt r 0}
        export CISCO_SPLIT_INC_${toString i}_MASK=${builtins.elemAt r 1}
        export CISCO_SPLIT_INC_${toString i}_MASKLEN=${builtins.elemAt r 2}
      '') utnet
    )}
    exec ${pkgs.vpnc-scripts}/bin/vpnc-script
  '';
in
{
  # UTokyo VPN, so the tailnet reaches UTNET the way vpn-relay.nix makes it reach
  # the office. The gateway is a Cisco ASA behind UTokyo Account (Entra ID) SAML
  # with mandatory MFA; sso-login.py does that sign-in in a headless browser with
  # the account's TOTP seed, so reconnecting needs nobody.
  #
  # The service is for the account holder's own coursework and research (UTokyo
  # VPN terms, art. 2). The tailnet is one person's devices; do not share the
  # route with anyone else.
  #
  # Credentials are in /var/lib/secrets/utokyo-vpn/ (see README.md).
  systemd.services.utokyo-vpn = {
    description = "UTokyo VPN (UTNET only, for the tailnet)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    };
    # Every start is a real sign-in. If it keeps failing (password changed, seed
    # wrong) stop after three tries an hour instead of locking the account; the
    # unit then shows up as failed.
    startLimitIntervalSec = 3600;
    startLimitBurst = 3;
    serviceConfig = {
      ExecStart = builtins.concatStringsSep " " [
        "${pkgs.openconnect}/bin/openconnect"
        "--protocol=anyconnect"
        "--non-inter"
        "--interface=utvpn"
        "--external-browser=${browser}"
        "--script=${routeScript}"
        "vpn1.adm.u-tokyo.ac.jp"
      ];
      LoadCredential = [
        "username:/var/lib/secrets/utokyo-vpn/username"
        "password:/var/lib/secrets/utokyo-vpn/password"
        "totp-secret:/var/lib/secrets/utokyo-vpn/totp-secret"
      ];
      # sso-login.py leaves last-failure.png here when a sign-in goes wrong.
      StateDirectory = "utokyo-vpn";
      # The ASA ends sessions on its own schedule; sign in again after a pause
      # long enough for a fresh TOTP window.
      Restart = "always";
      RestartSec = "2min";
    };
  };
}
