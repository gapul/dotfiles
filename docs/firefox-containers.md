# Firefox containers

`nix/modules/home/firefox.nix` owns the fixed containers and Temporary Containers
policy, shared by macOS and NixOS. Apply the host configuration normally; no profile
database editing is needed.

- New ordinary tabs use temporary containers.
- Temporary containers are removed after their last tab closes (`removal = 0`).
- Personal, Work, Banking, Shopping and Univ remain permanent login containers.
- Temporary Containers reads managed preferences when the extension starts. UI
  changes revert at that point. Its first installation skips managed preferences;
  restart Firefox once after installing it. Unspecified preferences use upstream
  defaults, so additional customizations belong in the Nix policy too.

## Container shortcuts (once per profile)

Multi-Account Containers 8.3.8 reads its shortcut-to-container assignments from
`browser.storage.local`; it does not support managed settings for these assignments.
Deploying a Firefox `3rdparty` policy alone cannot configure them. Home Manager
installs the repeatable setup script at
`~/.local/share/firefox/container-shortcuts.js`.

1. Open `about:debugging#/runtime/this-firefox` and find Firefox Multi-Account
   Containers. Copy its Internal UUID (different for each profile).
2. Open `moz-extension://<Internal UUID>/options.html` in a tab.
3. Open that tab's Web Console (`Ctrl+Shift+K` on Linux, `Cmd+Option+K` on macOS),
   then execute the contents of `container-shortcuts.js`. The script checks the
   extension identity, resolves containers by name, saves the previous bindings
   under `dotfilesContainerShortcutsBackup` in the extension's local storage, and
   verifies the saved values. It can be run again safely.
4. Test `Ctrl+Shift+1` (Personal) and `Ctrl+Shift+2` (Work) on Linux. WebExtension
   `Ctrl` shortcuts use Command on macOS. Check Firefox's extension-shortcut settings
   if another extension or the window manager intercepts a key.

These open blank tabs in permanent containers. `Ctrl+T` continues to open temporary
tabs. For two Google accounts, sign in separately in Personal and Work and leave
Google's "Always open in this container" assignment unset.

## Site assignments (once per profile)

"Always open in this container" assignments live in the same storage, so they are
set the same way: run `~/.local/share/firefox/container-sites.js` in the options
page's Web Console (steps 1–3 above). The list is at the top of the script:
university sites to Univ, Amazon to Shopping, and the banks and SBI Securities
to Banking. Each assignment matches one exact hostname and is saved with "never
ask", because every new tab starts in a temporary container and would otherwise stop
at the confirmation page on each visit. Previous values are kept
under `dotfilesContainerSitesBackup`; the script can be run again safely.

This is what puts bookmarks in the right container: floccus syncs only URLs, and a
bookmark opens in a temporary container like any new tab. Google, Slack and Notion
stay unassigned because one hostname serves more than one account.

Sources: [Temporary Containers storage initialization](https://github.com/stoically/temporary-containers/blob/master/src/background/storage.ts),
[Multi-Account Containers shortcut storage](https://github.com/mozilla/multi-account-containers/blob/main/src/js/background/identityState.js),
[Multi-Account Containers site assignments](https://github.com/mozilla/multi-account-containers/blob/main/src/js/background/assignManager.js).
