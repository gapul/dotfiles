# Darwin Tinycast component (ECS: profile). Tinycast (cask abue-ammar/tinycast, hosts/darwin.nix)
# is the launcher on cmd+space since 2026-10-01; the login item is in darwin-apps.nix. Not
# sandboxed (no ~/Library/Containers/com.tinycast.app), so targets.darwin.defaults reaches the
# plist the app reads. `defaults import` merges top-level keys, so settings changed in the UI
# survive a switch, except that a declared array (boundQuicklinkIDs) replaces the whole array.
#
# Format facts, read back from settings recorded in the UI:
# - Shortcuts are JSON strings {"combo":{"_0":{"carbonKeyCode":K,"carbonModifiers":M}}} with
#   Carbon modifiers cmd=256, option=2048, control=4096 (shift=512).
# - Item ids are lowercase UUIDs: Tinycast lowercases boundQuicklinkIDs on launch, so the sqlite
#   row, the hotkey.quicklink.<id> key and the array entry must all be lowercase to match.
# - Each feature has a *Enabled flag that defaults to off; with quicklinksEnabled unset the row
#   and its shortcut below silently do nothing.
# Tinycast reads all of this at launch; activation does not restart it, so quit and reopen it
# to pick up a change.
{ lib, pkgs, ... }:
let
  # "Add Log": a line of text into the Obsidian QuickAdd "Add Log" choice, which replaced the
  # retired Ghostty launcher's Cmd+Ctrl+Opt+O quick-add (dotfiles #910).
  addLogId = "d83ec003-c20b-49ab-befd-a451074ea8c7";
  addLogLink = ''obsidian://quickadd?vault=notes&choice=Add%20Log&value-text={argument name="Log"}'';
in
{
  targets.darwin.defaults."com.tinycast.app" = {
    "hotkey.togglePalette" = ''{"combo":{"_0":{"carbonKeyCode":49,"carbonModifiers":256}}}''; # cmd+space
    quicklinksEnabled = true;
    "hotkey.quicklink.${addLogId}" = ''{"combo":{"_0":{"carbonKeyCode":31,"carbonModifiers":6400}}}''; # cmd+ctrl+opt+o
    boundQuicklinkIDs = [ addLogId ];
  };

  # The quicklink itself lives in Tinycast's own sqlite store, created on first launch. INSERT
  # OR IGNORE keys on the fixed id, so it never touches rows made in the UI or an edited copy of
  # this one; a row added while the app runs is read on its next launch.
  home.activation.tinycastQuicklinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    db="$HOME/Library/Application Support/com.tinycast.app/quicklinks.sqlite3"
    if [ -f "$db" ]; then
      run ${lib.getExe pkgs.sqlite} "$db" ${lib.escapeShellArg ''
        INSERT OR IGNORE INTO quicklinks
          (id, name, link, open_with, icon, in_root_search, pinned_at, created_at, is_enabled)
        VALUES ('${addLogId}', 'Add Log', '${addLogLink}', NULL, NULL, 1, NULL, 812541600.0, 1);
      ''}
    fi
  '';
}
