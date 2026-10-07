# The Blocky configuration itself. Read by both homeserver and macmini.
#
# Keeping the same config on both is about correctness, not tidiness. A client can pick
# either of the 2 resolvers handed out by DHCP, so if only one had different ad lists or
# upstreams, the same query from the same device would get different answers on different
# days. That can't be tracked down, so the only difference is the listen addresses.
{ listen }:
{
  ports = {
    dns = listen;
    http = 4000; # metrics + API. dns2.gapul.net points at this on the homeserver side.
  };

  # Two providers so one provider dropping us doesn't take the tailnet's DNS down. Quad9
  # answered 429 and then nothing to the home IP for ~20 min after a burst of ~6000 queries
  # (2026-10-06), and both blocky failed every query. Both upstreams are unfiltered; blocking
  # stays in the lists below.
  upstreams.groups.default = [
    "https://dns10.quad9.net/dns-query"
    "https://cloudflare-dns.com/dns-query"
  ];
  # IPv4 only for outgoing connections (upstream and list downloads). macmini has no IPv6
  # route, and the downloader dials the AAAA answer first and does not fall back inside an
  # attempt, so raw.githubusercontent.com failed 3/3 and two of three lists were missing
  # (2026-09-26). homeserver was fine only by luck of the answer order.
  connectIPVersion = "v4";
  # DoH can't resolve its own hostname, so addresses are used here.
  bootstrapDns = [
    { upstream = "9.9.9.10"; }
    { upstream = "149.112.112.10"; }
    { upstream = "1.1.1.1"; }
    { upstream = "1.0.0.1"; }
  ];

  blocking = {
    # Format first, source second. blocky only reads hosts format, plain domains, wildcards
    # (*.example.com), and regexes. AdGuard's `||domain^` syntax (oisd's default format,
    # AdGuard DNS filter) is silently read as 0 entries; blocking reports enabled and nothing
    # is blocked. That's why both oisd and hagezi point at the wildcard URLs.
    #
    # On 2026-09-26 the NextDNS (profile 43b9d5) settings were carried over here. NextDNS had
    # oisd + AdGuard DNS filter + nextdns-recommended, Security with threat intelligence,
    # cryptojacking, typosquatting, and DGA, plus 2 allowlist entries. nextdns-recommended is
    # private, so there is no equivalent. AdGuard DNS filter is among oisd big's sources.
    denylists = {
      # oisd big (what NextDNS used) combined with hagezi Multi PRO++. Measured on 2026-09-26,
      # the two are complementary, each with about 60% of domains the other lacks. oisd follows a
      # "don't break things" policy and doesn't block apexes (doubleclick.net itself, etc.);
      # PRO++ fills that gap. PRO++ also already includes Native Tracker (Apple / Windows·Office
      # / Samsung / Xiaomi and other OS-built-in telemetry) at the PRO++ level. StevenBlack used to
      # be here, but what it had beyond the other two was old counters and leftover throwaway TLDs,
      # and its side effects, such as blocking the amazon-adsystem.com apex, stood out, so it was removed.
      ads = [
        "https://big.oisd.nl/domainswild"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.plus.txt"
      ];
      # hagezi Threat Intelligence Feeds (medium): replaces the NextDNS Security tab.
      # medium (18MB) rather than the full version (45MB). Fewer false positives, and easier on macmini's memory.
      threats = [
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif.medium.txt"
      ];
    };
    # The NextDNS allowlist as is. Inline definition (treated like a YAML literal block).
    allowlists.ads = [
      ''
        # carried over from the NextDNS allowlist
        1088045785.rsc.cdn77.org
        cdn.kde.org
        # Media edges that hagezi PRO++ lists as trackers but that serve the actual
        # images: profile pictures, attachments and link previews (2026-10-01, the
        # Matrix bridges for Instagram / Messenger / LinkedIn failed every avatar and
        # attachment with NXDOMAIN; the Tokyo edge is the one this house resolves to).
        # The sonar / crash / metrics hosts next to them in the list stay blocked.
        *.scontent-nrt1-1.xx.fbcdn.net
        *.instagram.felp1-1.fna.fbcdn.net
        *.media-akam.licdn.com
      ''
    ];
    clientGroupsBlock.default = [
      "ads"
      "threats"
    ];
    # The lists are 5-18MB each; the 5s default timeout is for small ones. Retry with a real
    # pause so a flaky first fetch does not leave a group empty until the 4h refresh.
    loading.downloads = {
      timeout = "60s";
      attempts = 5;
      cooldown = "5s";
    };
    # NXDOMAIN rather than 0.0.0.0. Clients stop retrying, and
    # sockets aren't left hanging on a black hole.
    blockType = "nxDomain";
  };

  caching = {
    minTime = "5m";
    maxTime = "30m";
    prefetching = true;
  };

  prometheus.enable = true;
  # Queries are not kept on disk. If a searchable log is needed,
  # put queryLog.type = "csv" and a path here.
  queryLog.type = "none";
  log.level = "info";
}
