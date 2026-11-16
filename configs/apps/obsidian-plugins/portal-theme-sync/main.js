'use strict';
const { Plugin, Platform } = require('obsidian');

// Electron/Chromium on Linux derives light/dark from GTK colors at startup and
// ignores later org.freedesktop.appearance color-scheme changes, so Obsidian's
// "Adapt to system" theme gets stuck. Watch the portal ourselves and flip the
// body theme class while the vault theme is set to "system".
const DEST = ['--session', '--dest', 'org.freedesktop.portal.Desktop',
  '--object-path', '/org/freedesktop/portal/desktop'];

module.exports = class PortalThemeSync extends Plugin {
  onload() {
    if (!Platform.isDesktopApp || !Platform.isLinux) return;
    this.cp = require('child_process');
    this.dark = null;
    this.stopped = false;
    this.app.workspace.onLayoutReady(() => {
      this.readCurrent();
      this.watch();
    });
    // Obsidian may re-apply its own (stale) system theme, e.g. after settings changes.
    this.registerEvent(this.app.workspace.on('css-change', () => this.apply()));
  }

  onunload() {
    this.stopped = true;
    clearTimeout(this.retry);
    if (this.proc) this.proc.kill();
  }

  setScheme(v) {
    // 1 = prefer dark, 2 = prefer light, 0 = no preference (leave Obsidian alone)
    if (v === 1) this.dark = true;
    else if (v === 2) this.dark = false;
    else return;
    this.apply();
  }

  apply() {
    if (this.dark === null || this.app.vault.getConfig('theme') !== 'system') return;
    const want = this.dark ? 'theme-dark' : 'theme-light';
    const body = document.body;
    if (body.classList.contains(want) && !body.classList.contains(this.dark ? 'theme-light' : 'theme-dark')) return;
    body.classList.remove('theme-dark', 'theme-light');
    body.classList.add(want);
    this.app.workspace.trigger('css-change');
  }

  readCurrent() {
    this.cp.execFile('gdbus', ['call', ...DEST, '--method',
      'org.freedesktop.portal.Settings.ReadOne', 'org.freedesktop.appearance', 'color-scheme'],
    (err, out) => {
      if (err) return console.warn('portal-theme-sync: read failed', err.message);
      const m = /uint32 (\d+)/.exec(out);
      if (m) this.setScheme(Number(m[1]));
    });
  }

  watch() {
    if (this.stopped) return;
    const proc = this.cp.spawn('gdbus', ['monitor', ...DEST], { stdio: ['ignore', 'pipe', 'ignore'] });
    this.proc = proc;
    let buf = '';
    proc.stdout.on('data', (chunk) => {
      buf += chunk;
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const line of lines) {
        const m = /'org\.freedesktop\.appearance', 'color-scheme', <uint32 (\d+)>/.exec(line);
        if (m) this.setScheme(Number(m[1]));
      }
    });
    const restart = () => {
      if (this.proc !== proc || this.stopped) return;
      this.proc = null;
      this.retry = setTimeout(() => { this.readCurrent(); this.watch(); }, 5000);
    };
    proc.on('exit', restart);
    proc.on('error', (e) => { console.warn('portal-theme-sync: monitor failed', e.message); restart(); });
  }
};
