// ==UserScript==
// @name        g-embed: YouTube and Google Maps embeds without Google
// @namespace   https://github.com/gapul/dotfiles
// @version     0.1.0
// @description Replaces embedded YouTube players and Google Maps with cards drawn from noembed.com and OpenStreetMap; opening one is a click away.
// @match       *://*/*
// @exclude     *://*.youtube.com/*
// @exclude     *://youtube.com/*
// @exclude     *://www.google.com/maps*
// @exclude     *://maps.google.com/*
// @grant       GM_xmlhttpRequest
// @connect     noembed.com
// @connect     i.ytimg.com
// @connect     tile.openstreetmap.org
// @run-at      document-start
// @noframes
// @downloadURL https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/g-embed.user.js
// @updateURL   https://raw.githubusercontent.com/gapul/dotfiles/main/configs/apps/violentmonkey/g-embed.user.js
// ==/UserScript==

// Firefox's strict tracking protection (arkenfox) blocks youtube.com, youtube-nocookie.com and
// google.com/maps iframes outright, leaving blank boxes. This puts a card in their place, the way
// fx-embed does for tweets:
//   YouTube: title and channel from noembed.com (a third-party oEmbed proxy, so Google is not
//     asked), thumbnail from i.ytimg.com without cookies or Referer; a click opens the video on
//     youtube.com. Playing in place is not possible: the player itself is what gets blocked.
//   Google Maps: coordinates and place name read from the embed URL, map drawn from
//     OpenStreetMap tiles; Google is never contacted. Buttons open the place in Apple Maps,
//     Google Maps or OpenStreetMap.
// The iframes are swapped out as soon as the parser inserts them, so the blocked request is
// never made.

(() => {
  'use strict';

  const STATE = 'data-g-embed';
  const YT = /^https?:\/\/(?:www\.)?youtube(?:-nocookie)?\.com\/embed\/([A-Za-z0-9_-]{11})(?:[?#]|$)/;
  const MAPS = /^https?:\/\/(?:www\.|maps\.)?google\.[a-z.]+\/maps(?:\/embed)?\b/;

  // GM_xmlhttpRequest runs outside the page: no page Referer, no page CSP, and `anonymous`
  // drops cookies.
  const request = (url, responseType) =>
    new Promise((resolve, reject) => {
      GM_xmlhttpRequest({
        url,
        method: 'GET',
        anonymous: true,
        responseType,
        timeout: 15000,
        onload: (r) => (r.status >= 200 && r.status < 300 ? resolve(r.response) : reject(new Error(`HTTP ${r.status}`))),
        onerror: () => reject(new Error('network error')),
        ontimeout: () => reject(new Error('timeout')),
      });
    });

  const parseUrl = (url) => {
    try {
      return new URL(url, location.href);
    } catch {
      return null;
    }
  };

  const el = (tag, props = {}, ...children) => {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === 'class') node.className = v;
      else if (k === 'text') node.textContent = v;
      else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v);
    }
    node.append(...children.filter(Boolean));
    return node;
  };

  const link = (href, props = {}, ...children) =>
    el('a', { href, target: '_blank', rel: 'noopener noreferrer', referrerpolicy: 'no-referrer', ...props }, ...children);

  const open = (url) => window.open(url, '_blank', 'noopener,noreferrer');

  // Fetched images go through GM_xmlhttpRequest into blob: URLs: i.ytimg.com is on the tracking
  // list strict mode blocks, and OSM tiles should not carry the page's address either.
  // Tries each URL in turn until one loads; drops the image if none does.
  const blobImage = (urls, cls) => {
    const img = el('img', { alt: '', class: cls ?? '', decoding: 'async' });
    const next = ([url, ...rest]) =>
      url ? request(url, 'blob').then((blob) => (img.src = URL.createObjectURL(blob)), () => next(rest)) : img.remove();
    next([].concat(urls));
    return img;
  };

  const STRINGS = {
    ja: {
      watch: 'YouTube で見る',
      video: 'YouTube 動画',
      play: '再生（YouTube で開く）',
      map: '地図',
      apple: 'Apple マップ',
      google: 'Google マップ',
      osm: 'OpenStreetMap',
    },
    en: {
      watch: 'Watch on YouTube',
      video: 'YouTube video',
      play: 'Play (opens YouTube)',
      map: 'Map',
      apple: 'Apple Maps',
      google: 'Google Maps',
      osm: 'OpenStreetMap',
    },
  };
  const S = () => STRINGS[/^ja\b/i.test(navigator.language) ? 'ja' : 'en'];

  const PATHS = {
    play: 'M8 5v14l11-7z',
    pin: 'M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5A2.5 2.5 0 1 1 12 6a2.5 2.5 0 0 1 0 5.5z',
  };
  const icon = (name, cls) => {
    const span = el('span', { class: `icon ${cls ?? name}` });
    span.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${PATHS[name]}"/></svg>`;
    return span;
  };

  const STYLE = `
    :host { all: initial; display: block; margin: 0 auto; max-width: 100%; }
    * { box-sizing: border-box; }
    .icon { display: inline-flex; }
    .icon svg { width: 100%; height: 100%; fill: currentColor; }
    .yt { position: relative; width: 100%; overflow: hidden; border-radius: 12px; background: #000; cursor: pointer;
      font: 14px/1.4 "YouTube Sans", Roboto, -apple-system, "Segoe UI", "Hiragino Sans", "Noto Sans CJK JP", sans-serif; color: #fff; }
    .yt img.thumb { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
    .yt .top { position: absolute; inset: 0 0 auto; padding: 12px 16px 32px;
      background: linear-gradient(rgba(0, 0, 0, 0.7), transparent); }
    .yt .title { font-size: 18px; font-weight: 500; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical;
      overflow: hidden; text-shadow: 0 0 2px rgba(0, 0, 0, 0.5); }
    .yt .channel { font-size: 13px; opacity: 0.85; margin-top: 2px; }
    .yt .play { position: absolute; left: 50%; top: 50%; width: 68px; height: 48px; transform: translate(-50%, -50%);
      display: grid; place-items: center; border: 0; border-radius: 14px; background: rgba(33, 33, 33, 0.8); cursor: pointer; }
    .yt:hover .play, .yt .play:focus-visible { background: #f00; }
    .yt .play .tri { width: 30px; height: 30px; color: #fff; }
    .yt .bottom { position: absolute; left: 12px; bottom: 12px; display: inline-flex; align-items: center; gap: 6px;
      padding: 6px 12px; border-radius: 999px; background: rgba(0, 0, 0, 0.75); font-weight: 500; }
    .yt .logo { width: 22px; height: 16px; border-radius: 4px; background: #f00; display: grid; place-items: center; }
    .yt .logo .tri { width: 12px; height: 12px; color: #fff; }
    .map { position: relative; width: 100%; overflow: hidden; border-radius: 12px; border: 1px solid var(--border);
      background: var(--tile); font: 14px/1.4 Roboto, -apple-system, "Segoe UI", "Hiragino Sans", "Noto Sans CJK JP", sans-serif;
      color: var(--fg); --fg: #202124; --muted: #5f6368; --border: #dadce0; --panel: #fff; --tile: #e8eaed; }
    :host([data-theme="dark"]) .map { --fg: #e8eaed; --muted: #9aa0a6; --border: #3c4043; --panel: #202124; --tile: #2b2c2f; }
    .tiles { position: absolute; inset: 0; }
    .tiles img { position: absolute; width: 256px; height: 256px; }
    .pin { position: absolute; left: 50%; top: 50%; width: 36px; height: 36px; transform: translate(-50%, -100%); color: #ea4335;
      filter: drop-shadow(0 1px 1px rgba(0, 0, 0, 0.4)); }
    .panel { position: absolute; left: 10px; top: 10px; max-width: calc(100% - 20px); padding: 10px 12px; border-radius: 8px;
      background: var(--panel); box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3); }
    .place { font-weight: 500; font-size: 15px; }
    .coords { color: var(--muted); font-size: 12px; margin-top: 2px; }
    .buttons { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
    .buttons a { font-size: 13px; color: #1a73e8; text-decoration: none; border: 1px solid var(--border); border-radius: 999px;
      padding: 3px 10px; background: var(--panel); }
    .buttons a:hover { background: rgba(26, 115, 232, 0.08); }
    .attrib { position: absolute; right: 0; bottom: 0; padding: 1px 6px; font-size: 11px; color: #333;
      background: rgba(255, 255, 255, 0.8); }
    .attrib a { color: inherit; }
  `;

  // One parsed stylesheet shared by every shadow root; a <style> where that is refused.
  let sheet = null;
  const styleShadow = (root) => {
    try {
      if (!sheet) {
        sheet = new CSSStyleSheet();
        sheet.replaceSync(STYLE);
      }
      root.adoptedStyleSheets = [sheet];
    } catch {
      root.append(el('style', { text: STYLE }));
    }
  };

  // The map panel follows the page's light/dark look (first opaque background behind it).
  const pageIsDark = (node) => {
    for (let n = node.parentElement; n; n = n.parentElement) {
      const m = getComputedStyle(n).backgroundColor.match(/[\d.]+/g);
      if (!m || (m.length > 3 && Number(m[3]) < 0.5)) continue;
      const [r, g, b] = m.slice(0, 3).map((c) => (Number(c) / 255) ** 2.2);
      return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.18;
    }
    return matchMedia('(prefers-color-scheme: dark)').matches;
  };

  // Keeps the iframe's own size: width/height attributes, else 560×315 (YouTube's default).
  const size = (frame, fallbackW, fallbackH) => {
    const w = Number(frame.getAttribute('width')) || fallbackW;
    const h = Number(frame.getAttribute('height')) || fallbackH;
    return { w, h };
  };

  // ---- YouTube --------------------------------------------------------------------------

  const youtubeCard = (id, start, { w, h }) => {
    const watch = `https://www.youtube.com/watch?v=${id}${start ? `&t=${start}s` : ''}`;
    // maxresdefault exists only for HD uploads (404 otherwise); hqdefault always does.
    const thumb = blobImage([`https://i.ytimg.com/vi/${id}/maxresdefault.jpg`, `https://i.ytimg.com/vi/${id}/hqdefault.jpg`], 'thumb');
    const title = el('div', { class: 'title', text: S().video });
    const channel = el('div', { class: 'channel' });
    const card = el(
      'div',
      { class: 'yt', style: `aspect-ratio:${w} / ${h}`, onclick: () => open(watch) },
      thumb,
      el('div', { class: 'top' }, title, channel),
      el('button', { type: 'button', class: 'play', title: S().play, 'aria-label': S().play }, icon('play', 'tri')),
      el('div', { class: 'bottom' }, el('span', { class: 'logo' }, icon('play', 'tri')), S().watch),
    );
    request(`https://noembed.com/embed?url=${encodeURIComponent(`https://www.youtube.com/watch?v=${id}`)}`, 'json')
      .then((d) => {
        if (typeof d?.title === 'string') title.textContent = d.title;
        if (typeof d?.author_name === 'string') channel.textContent = d.author_name;
      })
      .catch(() => {});
    return card;
  };

  // ---- Google Maps ----------------------------------------------------------------------

  // Reads what the embed shows from its URL. The /maps/embed?pb= form packs the viewport into
  // "!" fields: !2d longitude, !3d latitude, !1d the viewport width in metres, and for a place
  // "!1s0x…:0x…!2s<name>". The legacy ?q=…&output=embed form carries a query instead.
  const readMap = (url) => {
    const u = parseUrl(url);
    if (!u) return null;
    const pb = u.searchParams.get('pb') ?? '';
    const num = (re) => {
      const m = pb.match(re);
      return m ? Number(m[1]) : NaN;
    };
    let lat = num(/!3d(-?\d+(?:\.\d+)?)/);
    let lon = num(/!2d(-?\d+(?:\.\d+)?)/);
    const metres = num(/!1d(\d+(?:\.\d+)?)/);
    // The place name follows the place id as !2s (URL-encoded) or !2z (base64 of UTF-8).
    const field = pb.match(/!1s0x[0-9a-f]+(?::|%3A)0x[0-9a-f]+!2([sz])([^!]+)/i);
    let name = null;
    try {
      if (field?.[1] === 's') name = decodeURIComponent(field[2].replace(/\+/g, ' '));
      if (field?.[1] === 'z') name = new TextDecoder().decode(Uint8Array.from(atob(field[2].replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0)));
    } catch {
      name = null;
    }
    const q = u.searchParams.get('q');
    if (q) {
      const ll = q.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
      if (ll) [lat, lon] = [Number(ll[1]), Number(ll[2])];
      else name ??= q;
    }
    const ok = Math.abs(lat) <= 85 && Math.abs(lon) <= 180;
    return { lat: ok ? lat : null, lon: ok ? lon : null, metres: metres > 0 ? metres : null, name };
  };

  const zoomFor = (lat, metres, widthPx) => {
    if (!metres) return 15;
    const z = Math.log2((156543.03 * Math.cos((lat * Math.PI) / 180) * widthPx) / metres);
    return Math.min(18, Math.max(3, Math.round(z)));
  };

  // OSM tiles around the point, positioned so the point sits in the middle of the card.
  const tiles = (lat, lon, z, w, h) => {
    const n = 2 ** z;
    const rad = (lat * Math.PI) / 180;
    const cx = ((lon + 180) / 360) * n * 256;
    const cy = ((1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2) * n * 256;
    const left = cx - w / 2;
    const top = cy - h / 2;
    const box = el('div', { class: 'tiles' });
    for (let ty = Math.floor(top / 256); ty <= Math.floor((top + h) / 256); ty++) {
      if (ty < 0 || ty >= n) continue;
      for (let tx = Math.floor(left / 256); tx <= Math.floor((left + w) / 256); tx++) {
        const x = ((tx % n) + n) % n;
        const img = blobImage(`https://tile.openstreetmap.org/${z}/${x}/${ty}.png`);
        img.style.left = `${Math.round(tx * 256 - left)}px`;
        img.style.top = `${Math.round(ty * 256 - top)}px`;
        box.append(img);
      }
    }
    return box;
  };

  const mapCard = (info, { w, h }) => {
    const { lat, lon, name } = info;
    const has = lat !== null && lon !== null;
    const label = name || (has ? `${lat.toFixed(5)}, ${lon.toFixed(5)}` : S().map);
    const query = encodeURIComponent(name || `${lat},${lon}`);
    const apple = has
      ? `https://maps.apple.com/?ll=${lat},${lon}${name ? `&q=${encodeURIComponent(name)}` : ''}`
      : `https://maps.apple.com/?q=${query}`;
    const google = has ? `https://www.google.com/maps/search/?api=1&query=${lat},${lon}` : `https://www.google.com/maps/search/?api=1&query=${query}`;
    const osm = has ? `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=${zoomFor(lat, info.metres, w)}/${lat}/${lon}` : `https://www.openstreetmap.org/search?query=${query}`;
    return el(
      'div',
      { class: 'map', style: `aspect-ratio:${w} / ${h}` },
      has ? tiles(lat, lon, zoomFor(lat, info.metres, w), w, h) : null,
      has ? icon('pin') : null,
      el(
        'div',
        { class: 'panel' },
        el('div', { class: 'place', text: label }),
        has && name ? el('div', { class: 'coords', text: `${lat.toFixed(5)}, ${lon.toFixed(5)}` }) : null,
        el(
          'div',
          { class: 'buttons' },
          link(apple, { text: S().apple }),
          link(google, { text: S().google }),
          link(osm, { text: S().osm }),
        ),
      ),
      has ? el('div', { class: 'attrib' }, '© ', link('https://www.openstreetmap.org/copyright', { text: 'OpenStreetMap' })) : null,
    );
  };

  // ---- Replacing the iframes ------------------------------------------------------------

  const visible = new WeakMap();
  const observer = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        observer.unobserve(e.target);
        visible.get(e.target)?.();
      }
    },
    { rootMargin: '400px' },
  );

  const frameSrc = (frame) => frame.getAttribute('src') || frame.getAttribute('data-src') || frame.getAttribute('data-lazy-src') || '';

  const replace = (frame) => {
    if (frame.hasAttribute(STATE)) return;
    const src = parseUrl(frameSrc(frame))?.href ?? '';
    const yt = src.match(YT);
    const isMap = !yt && MAPS.test(src) && /[?&](?:pb=|output=embed)/.test(src);
    if (!yt && !isMap) return;
    frame.setAttribute(STATE, 'done');
    const dims = yt ? size(frame, 560, 315) : size(frame, 600, 450);
    const host = el('div', { style: `width:${dims.w}px` });
    const root = host.attachShadow({ mode: 'closed' });
    styleShadow(root);
    frame.replaceWith(host);
    // Network requests (noembed, thumbnail, tiles) wait until the card nears the viewport.
    visible.set(host, () => {
      host.setAttribute('data-theme', pageIsDark(host) ? 'dark' : 'light');
      if (yt) {
        const start = Number(parseUrl(src)?.searchParams.get('start')) || 0;
        root.append(youtubeCard(yt[1], start, dims));
      } else {
        root.append(mapCard(readMap(src), dims));
      }
    });
    observer.observe(host);
  };

  const scan = (root) => {
    if (root.nodeType !== Node.ELEMENT_NODE) return;
    if (root.tagName === 'IFRAME') replace(root);
    else if (root.firstElementChild) root.querySelectorAll('iframe').forEach(replace);
  };

  // At document-start even <html> may not exist yet, so watch the document itself. Iframes are
  // replaced the moment they are inserted, before their blocked request goes out; lazy loaders
  // that set src later are caught by the attribute watch.
  if (document.documentElement) scan(document.documentElement);
  new MutationObserver((records) => {
    for (const r of records) {
      if (r.type === 'attributes') r.target.tagName === 'IFRAME' && replace(r.target);
      else r.addedNodes.forEach(scan);
    }
  }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'data-src'] });
})();
