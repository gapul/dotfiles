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
{
  config,
  lib,
  pkgs,
  ...
}:
{
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

    # duckduckgo images (and videos/news, same module) send a Firefox User-Agent over a
    # non-browser TLS handshake (`impersonate = "none"`). DuckDuckGo answers about half of
    # those with a 202 "botnet" image captcha, which SearXNG reports as access denied or a
    # parsing error. The same requests with no User-Agent got 12 of 12 through, from the
    # Mullvad relay and from the home line alike (2026-10-31). The value is still set,
    # empty, because the vqd cache key reads headers["User-Agent"]. --replace-fail makes
    # an upstream rewrite of that line break the build instead of silently dropping this.
    #
    # gitlab crashed on every query ("unexpected crash", TypeError: expected string, got
    # NoneType): projects without a description come back as null, and the result container
    # needs a string. Still unfixed upstream on 2026-10-31.
    package = pkgs.searxng.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace searx/engines/duckduckgo_extra.py \
          --replace-fail 'headers["User-Agent"] = _HTTP_User_Agent' 'headers["User-Agent"] = ""'
        substituteInPlace searx/engines/gitlab.py \
          --replace-fail "'content': item.get('description')," "'content': item.get('description') or ''',"
      '';
    });

    # Without a favicons.toml next to settings.yml SearXNG logs an error on every start and keeps
    # the icon cache in /tmp, which PrivateTmp throws away on each restart. The module's
    # CacheDirectory survives restarts. Rest of the schema stays at its defaults.
    faviconsSettings.favicons = {
      cfg_schema = 1;
      cache.db_url = "/var/cache/searx/faviconcache.db";
    };

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
        # Result thumbnails and images are fetched by this server, not the browser, so the
        # sites behind them (pinterest, bing, the CDNs) do not see the client IP or a
        # search.gapul.net Referer. Costs homeserver bandwidth only.
        image_proxy = true;
      };

      # Also return JSON. The default is html only, and format=json gives 403. It's inside
      # the tailnet behind Authelia, so exposure isn't a concern, and agents and CLIs can
      # call it.
      search.formats = [
        "html"
        "json"
      ];
      # "auto" missed the Japanese Wikipedia infobox for a Japanese query (measured
      # 2026-10-30: `!wp 機械学習` gave the infobox with ja and nothing with auto), and English
      # queries still return English results under ja (nix flake: 134 results).
      # ja-JP rather than bare ja so engines that take a region (duckduckgo, yandex, bing)
      # get Japan instead of picking one themselves.
      search.default_lang = "ja-JP";
      # The site icon next to each result. The icon is fetched by this server (favicon proxy) and
      # cached, so DuckDuckGo learns the domains shown in results but not the client IP or the
      # query. DuckDuckGo already receives every query as an engine.
      search.favicon_resolver = "duckduckgo";

      # Show the query in the tab title ("query - SearXNG") so result tabs can be told apart.
      # Off upstream because browser history then records the query; that history is local
      # and already holds the query in the URL.
      ui.query_in_title = true;
      # Results in a centred column instead of hugging the left edge of a wide window.
      ui.center_alignment = true;

      # A page waits for its slowest engine up to this limit, so it bounds the worst case.
      # 3s was the default. The general engines answer well inside it (2026-10-30, P95: google
      # cse 0.8s, duckduckgo web 1.2s, yandex 1.5s, mwmbl 1.2s, wikipedia 1.0s), so a hanging
      # engine now costs 1.5s instead of 3s, at the price of yandex's slowest ~5% of answers.
      # Engines with their own `timeout` (crossref, openalex, the translators) keep it.
      outgoing.request_timeout = 1.5;

      # Unlike every other section, `plugins` is not merged into the defaults: a user
      # `plugins` replaces the whole table (settings_loader.update_settings), and a plugin
      # missing here is not loaded at all. So this lists every bundled plugin; when an
      # upgrade adds one to searx/settings.yml, add it here too or it silently stays out.
      plugins =
        lib.mapAttrs'
          (name: active: lib.nameValuePair "searx.plugins.${name}.SXNGPlugin" { inherit active; })
          {
            calculator = true;
            hash_plugin = true;
            self_info = true;
            unit_converter = true;
            ahmia_filter = true;
            hostnames = true;
            time_zone = true;
            tracker_url_remover = true;
            # Off by default upstream. DOI links go to an open-access copy when one exists
            # (pairs with crossref / openalex).
            oa_doi_rewrite = true;
            # Off by default upstream. The next page loads on scroll instead of a pager.
            infinite_scroll = true;
            # Only meaningful when the instance is reached over Tor.
            tor_check = false;
          };

      # When adding an engine, always confirm that **the engine name appears** in results.
      # SearXNG treats unknown shortcuts as search terms, so `!foo` returning results
      # is no proof that foo works. Two nonexistent engines got added this way
      # (luxxle / rawweb). Check existence by whether it is listed in `/config`, and
      # check that it works by the engine name appearing in results.
      #
      # duckduckgo and brave were kept on and left to SearXNG's automatic suspend. Neither
      # stayed: brave never came back, and duckduckgo duplicates duckduckgo web; see below.
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
        # Half weight (2026-10-31): a result only one engine returns scores weight / position,
        # so every engine's #1 ties for the top of the page. mwmbl is good on English tech
        # queries (55-98 results: discourse.nixos.org, users.rust-lang.org) but returns 0-1
        # results for Japanese ones, and that one is often junk (an ow.ly short link at #1 for
        # "引っ越し 手続き 一覧"). At 0.5 its #1 sits level with the other engines' #2.
        {
          name = "mwmbl";
          disabled = false;
          weight = 0.5;
        }
        # An alternate duckduckgo implementation. The default duckduckgo is sunk by
        # CAPTCHA, but this one gets through. Results come back for Japanese queries too,
        # and the engine name was confirmed to appear in results.
        {
          name = "duckduckgo web";
          disabled = false;
        }
        # The default duckduckgo returns the same index as duckduckgo web, so each DuckDuckGo
        # result was counted twice in the score (weight x engines that returned it), tilting
        # the merge toward Bing's index. It also hit CAPTCHA on 5-15% of queries (2026-10-30),
        # which duckduckgo web did not. `!ddg` still reaches it.
        {
          name = "duckduckgo";
          disabled = true;
        }
        # The slowest engine in the general tab (2026-10-30, alone: median 1.3s, up to 2.5s,
        # and 35% timeouts in /stats/errors). A page waits for its slowest engine, so it set
        # the time of most searches: the same queries took ~1.1s with it and ~0.6s without.
        # Infoboxes still come from wikipedia; `!wd` still reaches it.
        {
          name = "wikidata";
          disabled = true;
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
        #
        # 2026-10-31: still dead, through Mullvad too, so `!sp` answers nothing either.
        # Upstream now marks it `inactive` and solves Startpage's Anubis proof of work, but
        # only up to difficulty 4; Startpage serves 6 to every address tried (home line,
        # two Mullvad relays). In Python on this box that is ~31 s per solve, and the pass
        # is cached for 4 minutes, so it cannot fit a 1.5 s request_timeout. google cse
        # already covers the Google index Startpage resells.
        {
          name = "startpage";
          disabled = true;
        }
        # Forums only. Enabled for breadth, but under the ja-JP default language it returns
        # nothing except Yahoo! Chiebukuro Q&A pages (2026-10-31: 8-9 results per Japanese
        # query, all detail.chiebukuro.yahoo.co.jp), and they took 3-4 of the top 10. English
        # queries get nothing at all unless the language is switched to en, where the forum
        # results (github, fedora discourse, hotukdeals...) do show up. `!boa` still reaches it.
        {
          name = "boardreader";
          disabled = true;
        }
        # Old, plain pages only. Enabled to pick up what falls out of the big indexes, but
        # measured on 2026-10-31 it returned nothing for Japanese queries and off-topic pages
        # for English ones, which took the top spots of the merged list (lwn.net's front page
        # at #1 for "nix flake", a Tarzan review for "best mechanical keyboard").
        # `!wib` still reaches it.
        {
          name = "wiby";
          disabled = true;
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
        # Videos. Default-disabled; measured on 2026-10-26 and `!bil` returned 20 results
        # with the engine name present.
        {
          name = "bilibili";
          disabled = false;
        }
        # The bundled niconico engine scrapes the search page HTML, and after the site's
        # React rewrite its xpath (`//li[@data-video-item]`) matches nothing: HTTP 200,
        # 0 results, no error. Same name, so this merges into the default entry and keeps
        # the `!nico` shortcut, but swaps the engine for json_engine over the official
        # snapshot search API (no key needed).
        # The snapshot is rebuilt once a day, so videos posted today don't show up.
        {
          name = "niconico";
          engine = "json_engine";
          disabled = false;
          categories = [ "videos" ];
          paging = true;
          search_url =
            "https://snapshot.search.nicovideo.jp/api/v2/snapshot/video/contents/search"
            + "?q={query}&targets=title,description,tags"
            + "&fields=contentId,title,description,thumbnailUrl"
            + "&_sort=-viewCounter&_limit=20&_offset={pageno}";
          # {pageno} becomes (page - 1) * page_size + first_page_num, i.e. the offset.
          page_size = 20;
          first_page_num = 0;
          results_query = "data";
          url_query = "contentId";
          url_prefix = "https://www.nicovideo.jp/watch/";
          title_query = "title";
          content_query = "description";
          # description comes with <br /> and other tags left in.
          content_html_to_text = true;
          thumbnail_query = "thumbnailUrl";
        }
        # Cut ones that are enabled by default but failed 100% when measured on 2026-09-26.
        # They contribute no results and only produce timeout waits and error displays.
        #   vimeo ...... The search page is a Cloudflare challenge (403). Same from the main Mac.
        #                Still failing 2026-10-21 (timeout) though searxng#3849 was closed.
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
        # All four brave engines failed every query when measured on 2026-10-30: web 100%
        # TooManyRequests in /stats/errors, videos and news suspended for too many requests,
        # images crashing. The home IP gets a CAPTCHA page from search.brave.com, so this is
        # not going to clear on its own. The braveapi engine (needs a key) is the way back.
        {
          name = "brave";
          disabled = true;
        }
        {
          name = "brave.images";
          disabled = true;
        }
        {
          name = "brave.videos";
          disabled = true;
        }
        {
          name = "brave.news";
          disabled = true;
        }
        # Torrent indexes, enabled by default under "files". Not used here, and every files
        # search would otherwise fan out to them.
        {
          name = "kickass";
          disabled = true;
        }
        {
          name = "piratebay";
          disabled = true;
        }
        {
          name = "solidtorrents";
          disabled = true;
        }
        {
          name = "bt4g";
          disabled = true;
        }
        # Images for design reference. Default-disabled; measured on 2026-10-30 with the
        # engine name present in results: flickr 25, artic (Art Institute of Chicago
        # collection) 19, pexels 20. 1x timed out and openverse never answers from the
        # home IP, so neither is added.
        {
          name = "flickr";
          disabled = false;
        }
        {
          name = "artic";
          disabled = false;
        }
        {
          name = "pexels";
          disabled = false;
        }
        # Default engines that failed every query on 2026-10-31, from the Mullvad relays
        # and from the home line alike, so no route change brings them back:
        #   google news, google videos ... 302 to Google's bot wall
        #   semantic scholar ............. 202 challenge page instead of JSON
        #   picjumbo ..................... 403
        #   dictzone ..................... Cloudflare "Just a moment..."
        #   pypi, bandcamp ............... "Client Challenge" JS page, so 0 results
        #   lingva ....................... lingva.ml answers 503 DEPLOYMENT_PAUSED
      ]
      ++
        map
          (name: {
            inherit name;
            disabled = true;
          })
          [
            "google news"
            "google videos"
            "semantic scholar"
            "picjumbo"
            "dictzone"
            "pypi"
            "bandcamp"
            "lingva"
          ];
    };
  };

  # Caddy's access log for this vhost would otherwise hold every query in plain text
  # (/search?q=..., /autocompleter?q=..., and the Referer of every asset the results page
  # loads). Drop both; the rest of the line (time, path, status, latency) stays for debugging.
  services.caddy.virtualHosts."search.gapul.net".logFormat = ''
    output file ${config.services.caddy.logDir}/access-search.gapul.net.log
    format filter {
      request>uri query {
        delete q
      }
      request>headers>Referer delete
    }
  '';
}
