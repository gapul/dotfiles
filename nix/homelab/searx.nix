# Metasearch (SearXNG). tailnet only.
#
# This one is a native module rather than a container. That looks like it breaks the
# default.nix policy but is actually the opposite: that policy says "existing stacks stay
# containers because moving them isn't worth the cost". This is new and has no data to
# move. And the core of this service's config is which engines to keep; as a container,
# settings.yml would have to be placed in /var/lib by hand. That is exactly the state the
# README describes as "config stops living in the web UI or on the command line".
# With services.searx, the settings below go straight into git.
#
# Merged into upstream settings.yml (use_default_settings). Engines are matched by
# name, so one line is enough to enable something that is disabled by default.
#
# No limiter. It is bot protection for public instances and needs valkey when enabled.
# This is a single user inside the tailnet, so there is no one to protect against.
#
# --- About blocking (findings) ---
# "It gets blocked unless you run it on a VPS" is closer to the reverse. Google kills
# AWS/GCP/Azure and big VPS ranges first; residential IPs live longer. A residential IP
# is not safe either, though.
#
# Default suspension times (searx/settings.yml):
#   429 / Access Denied ......... 180 seconds
#   Regular CAPTCHA ............. 1 hour
#   Denial via Cloudflare ....... 1 day
#   reCAPTCHA ................... 7 days
#   CAPTCHA via Cloudflare ...... 15 days
# So the ones hit day to day are light, 3 minutes to 1 hour. The bottom two hurt, and
# they come when Google really objects. At personal-use volume they should rarely
# trigger, and when they do only that engine drops out while the others still answer.
# That's why google and startpage stay enabled on a best-effort basis rather than cut.
# If they break, they drop out on their own.
#
# Instead, mojeek and qwant, disabled by default, are enabled. mojeek is an independent
# index with its own crawler, so it doesn't get caught in Google's anti-bot net. It is
# the one that stays standing.
_: {
  # This used to be escaped to unstable here. searxng in the 26.05 series was stuck at
  # the 2026-05-16 release and couldn't keep up with search engine changes, so brave /
  # duckduckgo / qwant / mojeek / startpage all returned CAPTCHA or access denied at once
  # (search actually went completely dead).
  #
  # On 2026-08-31 all of nixpkgs-nixos moved to nixos-unstable, so the escape is no longer
  # needed. This incident is the main basis for the judgment that "the stable branch
  # doesn't fit this setup".

  services.searx = {
    enable = true;

    # Only secret_key. envsubst puts it into $SEARXNG_SECRET below.
    # Placed by hand like the rest of homelab (see README.md).
    environmentFile = "/var/lib/secrets/searx.env";

    settings = {
      server = {
        # Caddy calls it from the same box, so loopback is enough.
        bind_address = "127.0.0.1";
        port = 8088;
        base_url = "https://search.gapul.net/";
        secret_key = "$SEARXNG_SECRET";
        # Not public, so neither is needed (limiter = true would need valkey).
        limiter = false;
        public_instance = false;
      };

      # Also return JSON. The default is html only, and format=json gives 403. It's inside
      # the tailnet behind Authelia, so exposure isn't a concern, and agents and CLIs can
      # call it.
      search.formats = [
        "html"
        "json"
      ];

      # When adding an engine, always confirm that **the engine name appears** in results.
      # SearXNG treats unknown shortcuts as search terms, so `!foo` returning results
      # is no proof that foo works. Two nonexistent engines got added this way
      # (luxxle / rawweb). Check existence by whether it is listed in `/config`, and
      # check that it works by the engine name appearing in results.
      #
      # duckduckgo / startpage / brave stay enabled as by default. As of 2026-08 all
      # of them are sunk by CAPTCHA or rate limits, but the endpoints themselves are
      # alive (returning 202 / 302 / 200); they just can't get past the anti-bot
      # challenge. They sometimes come back depending on the other side's mood, so
      # leave it to SearXNG's automatic suspend.
      #
      # To make them work permanently, there is the route of moving to official APIs.
      # A braveapi engine is bundled and becomes stable once api_key is set (free tier
      # available). marginalia is the same. Both need a key, so do it when needed.
      engines = [
        # mojeek was enabled as "the one that survives when Google-family engines sink",
        # but as of 2026-08-29 scraping itself is blocked. All 3 paths (homeserver /
        # main Mac / external) get 403 (same even with a different UA), so it's not an IP
        # problem but a change on their side. Off until the implementation catches up.
        {
          name = "mojeek";
          disabled = true;
        }
        # qwant returned 10 results for Japanese queries in 2026-08, but measured on
        # 2026-09-26 it fails 100% with CAPTCHA for both English and Japanese
        # (/stats/errors). It only makes every search wait and shows an error, so off.
        {
          name = "qwant";
          disabled = true;
        }
        # Also its own crawler. Needs no key and returned 53 results when measured (same
        # role as mojeek: thickens the side that survives when Google-family engines die).
        {
          name = "mwmbl";
          disabled = false;
        }
        # An alternate duckduckgo implementation. The default duckduckgo is sunk by
        # CAPTCHA, but this one gets through. Results come back for Japanese queries too,
        # and the engine name was confirmed to appear in results.
        {
          name = "duckduckgo web";
          disabled = false;
        }
        # Enabled as ones not caught in the anti-bot net, but measured on 2026-09-26
        # both return HTTP 403 100% of the time (/stats/errors). It's a change on their
        # side, so off until the implementation catches up.
        {
          name = "privacywall";
          disabled = true;
        }
        {
          name = "searchmysite";
          disabled = true;
        }
        # No bing. What duckduckgo web returns is Bing's index itself, so results
        # duplicate, while calling it directly hands every query to Microsoft.
        # It only adds one more party watching for the same results. It would only be
        # wanted when ddg is down, but SearXNG has no conditionals, and "use it when the
        # other is down" can only be written as "always call it".
        #
        # yandex is a large index that is neither Google nor Bing, and there is currently
        # no alternative (mojeek is blocked, brave is waiting on a key). Every query goes
        # to Yandex, but the call is to use what has no alternative.
        {
          name = "yandex";
          disabled = false;
        }
        # Take startpage out of the defaults. Isolating it on the real machine on
        # 2026-08-30 found two walls. curl gets a JS challenge, and getting past that with
        # headless Chromium runs into an IP-based suspension behind it.
        #
        #   Access Temporarily Suspended
        #   Our anti-abuse systems are activated when we receive a large
        #   number of search requests from a particular internet connection
        #
        # It's cut off by the number of searches from that IP, not by whether it's a
        # browser. As long as it's used routinely from the home IP it structurally can't
        # work. Calling it every time only fails and makes you wait, so only call it when
        # `!sp` is written.
        {
          name = "startpage";
          disabled = true;
        }
        # Forums only. A different character, so it adds breadth.
        {
          name = "boardreader";
          disabled = false;
        }
        # Old, plain pages only. Picks up what falls out of the big indexes.
        {
          name = "wiby";
          disabled = false;
        }
        # The IT category is thin (44 registered, 11 enabled, 17 results). Only add ones
        # that worked when measured. nixos wiki / crates.io / hex / codeberg / alpine
        # returned 0 results, so they're not added.
        {
          name = "hackernews";
          disabled = false;
        }
        {
          name = "gitlab";
          disabled = false;
        }
        # Papers. A separate index from arxiv and pubmed; also measured.
        {
          name = "crossref";
          disabled = false;
        }
        {
          name = "openalex";
          disabled = false;
        }
        # Cut ones that are enabled by default but failed 100% when measured on 2026-09-26.
        # They contribute no results and only produce timeout waits and error displays.
        #   vimeo ...... The search page is a Cloudflare challenge (403). Same from the main Mac.
        #                searxng/searxng#3849 is still open with the CAPTCHA label.
        #   reuters .... 401
        #   unsplash ... Response isn't JSON, so parsing fails
        {
          name = "vimeo";
          disabled = true;
        }
        {
          name = "reuters";
          disabled = true;
        }
        {
          name = "unsplash";
          disabled = true;
        }
      ];
    };
  };
}
