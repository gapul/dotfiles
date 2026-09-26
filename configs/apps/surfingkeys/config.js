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

// Theme: Catppuccin palette (Mocha in dark mode, Latte in light), frosted panels, system
// fonts. The UI lives in Surfingkeys' own iframe, so `prefers-color-scheme` there follows the
// browser's content color scheme (the System theme in the Firefox module).
settings.theme = `
:root {
  --sk-bg: rgba(239, 241, 245, 0.92); --sk-panel: #e6e9ef; --sk-line: #ccd0da;
  --sk-fg: #4c4f69; --sk-dim: #8c8fa1; --sk-accent: #8839ef; --sk-accent2: #04a5e5;
  --sk-green: #40a02b; --sk-yellow: #df8e1d; --sk-red: #d20f39; --sk-focus: #dce0e8;
}
@media (prefers-color-scheme: dark) {
  :root {
    --sk-bg: rgba(30, 30, 46, 0.92); --sk-panel: #181825; --sk-line: #313244;
    --sk-fg: #cdd6f4; --sk-dim: #6c7086; --sk-accent: #cba6f7; --sk-accent2: #89b4fa;
    --sk-green: #a6e3a1; --sk-yellow: #f9e2af; --sk-red: #f38ba8; --sk-focus: #313244;
  }
}
.sk_theme {
  font-family: -apple-system, "SF Pro Text", system-ui, sans-serif; font-size: 13px;
  background: var(--sk-bg); color: var(--sk-fg);
  -webkit-backdrop-filter: blur(24px) saturate(160%); backdrop-filter: blur(24px) saturate(160%);
}
.sk_theme input, .sk_theme textarea { font-family: inherit; color: var(--sk-fg); }
.sk_theme kbd, #sk_keystroke, #sk_usage .kbd-span, .sk_theme .url {
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
}
/* omnibar */
#sk_omnibar {
  border: 1px solid var(--sk-line); border-radius: 14px; overflow: hidden;
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
}
#sk_omnibarSearchArea { border-bottom: 1px solid var(--sk-line); padding: 10px 14px; }
#sk_omnibarSearchArea input { font-size: 15px; background: transparent; }
#sk_omnibarSearchArea .prompt { color: var(--sk-accent); font-weight: 600; }
#sk_omnibarSearchArea .resultPage { color: var(--sk-dim); }
#sk_omnibarSearchResult { max-height: 60vh; }
#sk_omnibarSearchResult > ul > li { padding: 7px 14px; border-bottom: 1px solid var(--sk-line); }
#sk_omnibarSearchResult > ul > li:last-child { border-bottom: 0; }
#sk_omnibarSearchResult ul li.focused { background: var(--sk-focus); box-shadow: inset 3px 0 0 var(--sk-accent); }
.sk_theme .title { color: var(--sk-fg); }
.sk_theme .url { color: var(--sk-accent2); font-size: 11px; }
.sk_theme .annotation { color: var(--sk-dim); }
.sk_theme .omnibar_highlight { color: var(--sk-accent); font-weight: 600; text-decoration: none; }
.sk_theme .omnibar_timestamp, .sk_theme .omnibar_visitcount { color: var(--sk-yellow); }
.sk_theme .omnibar_folder { color: var(--sk-green); }
.sk_theme .separator { color: var(--sk-dim); }
/* status line, find bar, keystroke echo */
#sk_status, #sk_find { border: 1px solid var(--sk-line); border-radius: 10px 0 0 0; padding: 4px 10px; }
#sk_find input { background: transparent; }
#sk_keystroke { border: 1px solid var(--sk-line); border-radius: 10px 0 0 0; padding: 6px 10px; }
#sk_keystroke kbd, #sk_usage .kbd-span {
  background: var(--sk-panel); border: 1px solid var(--sk-line); border-radius: 5px; padding: 1px 5px;
  color: var(--sk-accent); box-shadow: 0 1px 0 var(--sk-line);
}
#sk_keystroke .candidates { color: var(--sk-dim); }
/* help, banner, bubble, popup, tab switcher */
#sk_usage { border-radius: 14px; border: 1px solid var(--sk-line); }
#sk_usage .feature_name > span { color: var(--sk-accent2); }
#sk_banner {
  border: 1px solid var(--sk-line); border-radius: 0 0 12px 12px; padding: 6px 14px;
  background: var(--sk-bg); color: var(--sk-fg);
}
#sk_bubble { border: 1px solid var(--sk-line); border-radius: 10px; }
#sk_popup { border: 1px solid var(--sk-line); border-radius: 12px; }
#sk_tabs { background: var(--sk-bg); border-radius: 14px; }
div.sk_tab { border-radius: 10px; border: 1px solid var(--sk-line); background: var(--sk-panel); }
div.sk_tab_title { color: var(--sk-fg); }
div.sk_tab_url { color: var(--sk-accent2); }
div.sk_tab_hint { background: var(--sk-accent); color: var(--sk-panel); border-radius: 5px; font-weight: 700; }
/* editor (vim mode) */
#sk_editor { background: var(--sk-panel) !important; }
.ace_editor { background: var(--sk-panel) !important; color: var(--sk-fg) !important; }
`;

// Link hints: same accent, readable at a glance.
api.Hints.style(`
  font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 11px; font-weight: 700;
  padding: 2px 5px; border: 0; border-radius: 5px;
  background: #cba6f7; color: #1e1e2e; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35);
`);
api.Hints.style(`
  font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 11px; font-weight: 700;
  padding: 2px 5px; border: 0; border-radius: 5px;
  background: #89b4fa; color: #1e1e2e; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35);
`, "text");
