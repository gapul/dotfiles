# Generate iOS configuration profiles (.mobileconfig) declaratively.
#
# A .mobileconfig is just an XML plist, so writing the payload as a nix attrset and feeding
# it to pkgs.formats.plist is enough. Delivering the output to the iPhone is
# mobile/ios/profiles/serve.sh.
#
# nix can only go as far as generating. Installing is manual on the device (iOS has no API
# for pushing profiles from outside unless the device is supervised or an MDM is set up).
{
  pkgs,
  lib,
  user,
}:
let
  plist = pkgs.formats.plist { };

  # Derive a UUID deterministically from a string. iOS identifies profiles by PayloadUUID, so
  # if this changed every time, each update would pile up on the device as a separate profile.
  # Deriving it from a hash keeps "same name, same UUID".
  uuidOf =
    s:
    let
      h = builtins.hashString "sha256" s;
      part = offset: len: lib.substring offset len h;
    in
    lib.toUpper "${part 0 8}-${part 8 4}-${part 12 4}-${part 16 4}-${part 20 12}";

  # Fill in the payload boilerplate (version / identifier / UUID) and wrap it in a Configuration.
  mkProfile =
    name:
    {
      displayName,
      description,
      payloads,
    }:
    {
      PayloadType = "Configuration";
      PayloadVersion = 1;
      PayloadIdentifier = "net.gapul.${name}";
      PayloadUUID = uuidOf name;
      PayloadDisplayName = displayName;
      PayloadDescription = description;
      PayloadRemovalDisallowed = false;
      PayloadContent = lib.imap0 (
        i: payload:
        payload
        // {
          PayloadVersion = 1;
          PayloadIdentifier = "net.gapul.${name}.${toString i}";
          PayloadUUID = uuidOf "${name}.${toString i}";
        }
      ) payloads;
    };

  # Don't put profiles here that the vendor distributes signed (NextDNS's DNS profile and
  # Tailscale's VPN profile are both distributed by upstream). Only ones with no distributor.
  profiles = {
    homelab-dav = {
      displayName = "Homelab CalDAV/CardDAV";
      description = "自宅 Radicale のカレンダーと連絡先。パスワードは初回に端末が訊く。";
      payloads = [
        # The target is not radicale's 5232 directly but the dav vhost set up by the sites
        # table in hosts/homeserver.nix. Caddy terminates it with an ACME certificate, so
        # credentials don't travel in plaintext. The A record points at a tailnet address, so
        # without being on the tailnet the name resolves but is unreachable.
        {
          PayloadType = "com.apple.caldav.account";
          CalDAVAccountDescription = "Homelab (Radicale)";
          CalDAVHostName = "dav.gapul.net";
          CalDAVUseSSL = true;
          CalDAVUsername = user.username;
        }
        {
          PayloadType = "com.apple.carddav.account";
          CardDAVAccountDescription = "Homelab (Radicale)";
          CardDAVHostName = "dav.gapul.net";
          CardDAVUseSSL = true;
          CardDAVUsername = user.username;
        }
      ];
    };
    # The three Stalwart mailboxes (homelab/mail.nix). The same file installs on macOS
    # for Mail.app. As with CalDAV vs CardDAV, Apple has no payload type that bundles
    # accounts. Outgoing points at Stalwart too, but it has no submission listener
    # yet, so this is read-only in practice.
    homelab-mail = {
      displayName = "Homelab Mail";
      description = "自宅 Stalwart の IMAP 口座 (gmail / work / school の写し)。パスワードは初回に端末が訊く。";
      payloads =
        map
          (name: {
            PayloadType = "com.apple.mail.managed";
            EmailAccountDescription = "Homelab (${name} mirror)";
            EmailAccountType = "EmailTypeIMAP";
            EmailAddress = "${name}@mail.gapul.net";
            IncomingMailServerHostName = "mail.gapul.net";
            IncomingMailServerPortNumber = 993;
            IncomingMailServerUseSSL = true;
            IncomingMailServerAuthentication = "EmailAuthPassword";
            IncomingMailServerUsername = name;
            OutgoingMailServerHostName = "mail.gapul.net";
            OutgoingMailServerPortNumber = 465;
            OutgoingMailServerUseSSL = true;
            OutgoingMailServerAuthentication = "EmailAuthPassword";
            OutgoingMailServerUsername = name;
            OutgoingPasswordSameAsIncomingPassword = true;
          })
          [
            "gmail"
            "work"
            "school"
          ];
    };
    # Register the home blocky as iOS encrypted DNS (DoH). The dns2 vhost in hosts/homeserver.nix
    # terminates TLS in Caddy and forwards to /dns-query on blocky's HTTP port. The NextDNS
    # distributed profile used to fill this role (consolidated onto blocky on 2026-09-26).
    # dns2.gapul.net points at a tailnet address, so it's unreachable when Tailscale is down.
    # ServerAddresses are IP hints that keep it reachable even when the name can't be resolved.
    homelab-dns = {
      displayName = "Homelab DNS (blocky)";
      description = "自宅 blocky を DNS over HTTPS で使う。広告・トラッカー遮断は nix/lib/blocky-settings.nix。";
      payloads = [
        {
          PayloadType = "com.apple.dnsSettings.managed";
          DNSSettings = {
            DNSProtocol = "HTTPS";
            ServerURL = "https://dns2.gapul.net/dns-query";
            ServerAddresses = [ "100.127.129.31" ];
          };
          ProhibitDisablement = false;
        }
      ];
    };
  };
in
pkgs.linkFarm "ios-profiles" (
  lib.mapAttrsToList (name: profile: {
    name = "${name}.mobileconfig";
    path = plist.generate "${name}.mobileconfig" (mkProfile name profile);
  }) profiles
)
