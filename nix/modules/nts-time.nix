{ ... }:
{
  # Time over NTS (Network Time Security) instead of timesyncd. timesyncd asked the NixOS pool
  # in plain NTP, so anyone on the path could shift the clock, and a shifted clock breaks TLS
  # certificate checks and TOTP. NTS authenticates every answer with a key from a TLS handshake.
  # Shared by the NixOS hosts; the Macs cannot speak NTS and take their time from homeserver
  # over the tailnet instead (hosts/darwin-common.nix).
  #
  # No public NTS server is in Japan. Cloudflare is anycast with a Tokyo site; Netnod and PTB
  # are national time labs (Sweden, Germany), so one provider going away leaves three others.
  services.chrony = {
    enable = true;
    enableNTS = true;
    servers = [
      "time.cloudflare.com"
      "nts.netnod.se"
      "ptbtime1.ptb.de"
      "ptbtime2.ptb.de"
    ];
    # The RTC is left to the kernel's 11-minute sync, as under timesyncd. chrony's own RTC
    # trimming would write the RTC by its own model, and nixos-laptop shares that RTC with
    # Windows.
    enableRTCTrimming = false;
    extraConfig = ''
      rtcsync
      # NTS checks the server's TLS certificate against the system clock. A clock that is far
      # off (dead RTC battery, first boot) would reject every certificate and never get fixed,
      # so skip the time check for the first update only.
      nocerttimecheck 1
    '';
  };
}
