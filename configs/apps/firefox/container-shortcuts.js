// Run in the Multi-Account Containers options page's Web Console, once per profile.
// Uses the extension's own settings API; never edit Firefox's live storage database.
(async () => {
  if (browser.runtime.id !== "@testpilot-containers") {
    throw new Error("Run this in Firefox Multi-Account Containers' options page.");
  }

  const bindings = [
    { command: "open_container_0", container: "Personal", shortcut: "Ctrl+Shift+1" },
    { command: "open_container_1", container: "Work", shortcut: "Ctrl+Shift+2" },
  ];
  const identities = await browser.contextualIdentities.query({});
  const targets = bindings.map(binding => {
    const matches = identities.filter(identity => identity.name === binding.container);
    if (matches.length !== 1) {
      throw new Error(`Expected one ${binding.container} container, found ${matches.length}.`);
    }
    return { ...binding, cookieStoreId: matches[0].cookieStoreId };
  });
  const previous = await browser.runtime.sendMessage({ method: "getShortcuts" });
  const commands = await browser.commands.getAll();
  const backupKey = "dotfilesContainerShortcutsBackup";
  if (!(await browser.storage.local.get(backupKey))[backupKey]) {
    await browser.storage.local.set({
      [backupKey]: targets.map(target => ({
        command: target.command,
        cookieStoreId: previous[target.command],
        shortcut: commands.find(command => command.name === target.command)?.shortcut,
      })),
    });
  }

  for (const target of targets) {
    await browser.commands.update({ name: target.command, shortcut: target.shortcut });
    await browser.runtime.sendMessage({
      method: "setShortcut",
      shortcut: target.command,
      cookieStoreId: target.cookieStoreId,
    });
  }

  const saved = await browser.runtime.sendMessage({ method: "getShortcuts" });
  const savedCommands = await browser.commands.getAll();
  // Firefox may report the macOS equivalent of Ctrl as Command/Cmd.
  const normalize = shortcut => shortcut?.replace(/^(Command|Cmd)\+/, "Ctrl+");
  for (const target of targets) {
    if (saved[target.command] !== target.cookieStoreId ||
        normalize(savedCommands.find(command => command.name === target.command)?.shortcut) !== target.shortcut) {
      throw new Error(`Could not verify ${target.container} shortcut.`);
    }
  }
  console.table(targets);
  return targets;
})();
