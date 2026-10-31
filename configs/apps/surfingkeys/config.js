// Surfingkeys settings for Firefox Developer Edition. Loaded by the extension from this
// file's raw.githubusercontent.com URL ("Load settings from" in advanced mode), so edits
// here reach the browser on its next start; nothing is set in the extension's own UI.
// Path: configs/apps/surfingkeys/config.js. Declared next to the browser in nix/modules/home/darwin-firefox.nix.

const { mapkey, Front } = api;

// Video playback speed. Replaces the Global Speed extension (non-FOSS).
const rate = (delta) => {
  const v = document.querySelector("video");
  if (!v) { Front.showBanner("no <video> here"); return; }
  v.playbackRate = Math.max(0.25, Math.round((v.playbackRate + delta) * 4) / 4);
  Front.showBanner(`speed ${v.playbackRate}x`);
};
mapkey(">", "Video: speed up", () => rate(0.25));
mapkey("<", "Video: slow down", () => rate(-0.25));
mapkey("=", "Video: reset speed", () => rate(1 - document.querySelector("video")?.playbackRate));

// Theme (2026-10-11): the Rosé Pine pair the rest of the desktop uses (configs/theme/palettes.json
// is the source of truth; this file is fetched over HTTP by the extension, so the values are
// copied here rather than read). Dawn when the page prefers light, Main when it prefers dark:
// the UI lives in Surfingkeys' own iframe, so `prefers-color-scheme` there follows the browser's
// content color scheme (System theme in the Firefox module, flipped by darkman on the laptop).
// The look is a floating command palette: one rounded sheet, hairline borders, frosted glass,
// soft layered shadow, generous padding, no hard dividers. Fonts follow the rice (JetBrainsMono
// Nerd Font) and fall back to the platform UI face.
// Surfingkeys 1.17.11 pins its UI shadow host to color-scheme: light. That also
// forces prefers-color-scheme inside its iframe to light, regardless of Firefox.
// Opt this host into both schemes when it is lazily attached (or reattached).
// Only touch Surfingkeys' extension iframe; leave the page's colour scheme alone.
// The frame's own document must then opt in too (`color-scheme: light dark` at the top of
// settings.theme): Firefox paints an iframe opaque when the scheme of its document differs
// from the scheme of the <iframe> element. With only the host opted in, a dark browser gave a
// dark element over a light document, and the full-viewport UI frame turned the whole page
// white whenever it showed (the "Copied" banner after yy, the omnibar, ...).
if (window === window.top && !window.__surfingkeysColorSchemeObserver) {
  const followSystemScheme = (element) => {
    if (!(element instanceof Element)) return;
    const frame = element.shadowRoot?.querySelector("iframe.sk_ui");
    if (frame?.src.startsWith("moz-extension://") && frame.src.endsWith("/pages/frontend.html")) {
      element.style.colorScheme = "light dark";
    }
  };
  document.querySelectorAll("div").forEach(followSystemScheme);
  const observer = new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        followSystemScheme(node);
      }
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.__surfingkeysColorSchemeObserver = observer;
}

settings.omnibarPosition = "middle"; // float the omnibar in the upper third instead of pinning it to the top edge
settings.omnibarMaxResults = 8;
settings.hintAlign = "left";
settings.theme = `
:root { color-scheme: light dark; }
:root {
  --sk-bg: rgba(250, 244, 237, 0.86); --sk-panel: #fffaf3; --sk-raised: #f2e9e1;
  --sk-line: rgba(87, 82, 121, 0.14); --sk-fg: #575279; --sk-dim: #797593; --sk-muted: #9893a5;
  --sk-accent: #907aa9; --sk-accent2: #286983; --sk-foam: #56949f; --sk-gold: #ea9d34;
  --sk-love: #b4637a; --sk-focus: rgba(144, 122, 169, 0.14);
  --sk-shadow: 0 1px 0 rgba(255, 255, 255, 0.6) inset, 0 20px 50px rgba(87, 82, 121, 0.22), 0 2px 8px rgba(87, 82, 121, 0.12);
}
@media (prefers-color-scheme: dark) {
  :root {
    --sk-bg: rgba(31, 29, 46, 0.84); --sk-panel: #1f1d2e; --sk-raised: #26233a;
    --sk-line: rgba(224, 222, 244, 0.1); --sk-fg: #e0def4; --sk-dim: #908caa; --sk-muted: #6e6a86;
    --sk-accent: #c4a7e7; --sk-accent2: #9ccfd8; --sk-foam: #9ccfd8; --sk-gold: #f6c177;
    --sk-love: #eb6f92; --sk-focus: rgba(196, 167, 231, 0.14);
    --sk-shadow: 0 1px 0 rgba(255, 255, 255, 0.06) inset, 0 24px 60px rgba(0, 0, 0, 0.55), 0 2px 10px rgba(0, 0, 0, 0.35);
  }
}
.sk_theme {
  font-family: "JetBrainsMono Nerd Font", -apple-system, "SF Pro Text", system-ui, sans-serif;
  font-size: 13px; letter-spacing: 0.01em;
  background: var(--sk-bg); color: var(--sk-fg);
  -webkit-backdrop-filter: blur(28px) saturate(170%); backdrop-filter: blur(28px) saturate(170%);
}
.sk_theme input, .sk_theme textarea { font-family: inherit; color: var(--sk-fg); caret-color: var(--sk-accent); }
.sk_theme kbd, #sk_keystroke, #sk_usage .kbd-span, .sk_theme .url {
  font-family: "JetBrainsMono Nerd Font", ui-monospace, "SF Mono", Menlo, monospace;
}
.sk_theme ::selection { background: var(--sk-focus); }

/* omnibar: a floating sheet, no dividers, the focused row lit from inside */
#sk_omnibar {
  width: min(760px, 92vw); left: calc(50% - min(760px, 92vw) / 2); top: 14%;
  border: 1px solid var(--sk-line); border-radius: 20px; overflow: hidden;
  box-shadow: var(--sk-shadow);
}
.sk_omnibar_middle #sk_omnibarSearchArea { margin: 0; }
#sk_omnibarSearchArea { border-bottom: 1px solid var(--sk-line); padding: 14px 18px; }
#sk_omnibarSearchArea input { font-size: 17px; font-weight: 500; background: transparent; }
#sk_omnibarSearchArea input::placeholder { color: var(--sk-muted); }
#sk_omnibarSearchArea .prompt {
  font-size: 11px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase;
  color: var(--sk-accent); background: var(--sk-focus); border-radius: 999px; padding: 3px 9px; margin-right: 8px;
}
#sk_omnibarSearchArea .resultPage { font-size: 11px; color: var(--sk-muted); }
#sk_omnibarSearchResult { max-height: 56vh; margin: 6px 8px 8px; }
/* the selectors carry .sk_theme + child combinators to outweigh the extension's own striped rows */
.sk_theme #sk_omnibarSearchResult > ul > li { padding: 9px 12px; gap: 10px; border: 0; border-radius: 12px; margin: 2px 0; background: transparent; }
.sk_theme #sk_omnibarSearchResult > ul > li:nth-child(odd) { background: transparent; }
.sk_theme #sk_omnibarSearchResult > ul > li.focused { background: var(--sk-focus); box-shadow: inset 0 0 0 1px var(--sk-line); }
#sk_omnibarSearchResult li div.url { font-weight: 500; min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.sk_theme .title { color: var(--sk-fg); font-weight: 500; }
.sk_theme .url { color: var(--sk-accent2); font-size: 11px; opacity: 0.9; }
.sk_theme .annotation { color: var(--sk-dim); }
.sk_theme .omnibar_highlight { color: var(--sk-accent); font-weight: 600; text-decoration: none; }
.sk_theme .omnibar_timestamp, .sk_theme .omnibar_visitcount { color: var(--sk-gold); font-size: 11px; }
.sk_theme .omnibar_folder { color: var(--sk-foam); }
.sk_theme .separator { color: var(--sk-muted); }

/* status line, find bar, keystroke echo: small pills floating off the edges */
#sk_status, #sk_find {
  right: 16px; bottom: 16px; padding: 6px 12px;
  border: 1px solid var(--sk-line); border-radius: 999px; box-shadow: var(--sk-shadow);
}
#sk_find input { background: transparent; }
#sk_keystroke {
  background: var(--sk-bg); color: var(--sk-fg); /* the extension pins #sk_keystroke to black by id */
  right: 16px; bottom: 16px; padding: 10px 12px;
  border: 1px solid var(--sk-line); border-radius: 14px; box-shadow: var(--sk-shadow);
}
#sk_keystroke kbd, #sk_usage .kbd-span {
  background: var(--sk-raised); border: 1px solid var(--sk-line); border-radius: 6px; padding: 1px 6px;
  color: var(--sk-accent); box-shadow: 0 1px 0 var(--sk-line);
}
#sk_keystroke .candidates { color: var(--sk-dim); }

/* help, banner, bubble, popup, tab switcher */
#sk_usage { border-radius: 20px; border: 1px solid var(--sk-line); box-shadow: var(--sk-shadow); padding: 12px; }
#sk_usage .feature_name > span { color: var(--sk-accent2); font-weight: 600; letter-spacing: 0.04em; }
#sk_banner {
  left: calc(50% - 200px); width: 400px; text-align: center;
  border: 1px solid var(--sk-line); border-radius: 0 0 16px 16px; padding: 8px 16px;
  background: var(--sk-bg); color: var(--sk-fg); box-shadow: var(--sk-shadow);
}
#sk_bubble { border: 1px solid var(--sk-line); border-radius: 12px; box-shadow: var(--sk-shadow); }
#sk_popup { border: 1px solid var(--sk-line); border-radius: 16px; box-shadow: var(--sk-shadow); }
#sk_tabs { background: var(--sk-bg); padding: 10px; }
div.sk_tab { border-radius: 14px; border: 1px solid var(--sk-line); background: var(--sk-panel); margin: 4px; padding: 8px 10px; box-shadow: var(--sk-shadow); }
div.sk_tab_title { color: var(--sk-fg); font-weight: 500; }
div.sk_tab_url { color: var(--sk-accent2); }
div.sk_tab_hint { background: var(--sk-accent); color: var(--sk-panel); border: 0; border-radius: 999px; font-weight: 700; padding: 1px 7px; }

/* editor (vim mode) */
#sk_editor { background: var(--sk-panel) !important; border-radius: 16px; }
.ace_editor { background: var(--sk-panel) !important; color: var(--sk-fg) !important; }
`;

// Hints live in the page, not the iframe, and take one static style, so they use colours that
// read on both light and dark pages: iris on near-black for links, foam for text hints.
const hintFont = `font-family: "JetBrainsMono Nerd Font", ui-monospace, "SF Mono", Menlo, monospace; font-size: 11px; font-weight: 700; letter-spacing: 0.04em;`;
api.Hints.style(`
  ${hintFont}
  padding: 2px 7px; border: 0; border-radius: 999px;
  background: #c4a7e7; color: #191724;
  box-shadow: 0 1px 0 rgba(255, 255, 255, 0.35) inset, 0 3px 10px rgba(25, 23, 36, 0.4);
`);
api.Hints.style(`
  ${hintFont}
  padding: 2px 7px; border: 0; border-radius: 999px;
  background: #9ccfd8; color: #191724;
  box-shadow: 0 1px 0 rgba(255, 255, 255, 0.35) inset, 0 3px 10px rgba(25, 23, 36, 0.4);
`, "text");
