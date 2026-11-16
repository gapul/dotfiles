// Run in the console of Zen Internet's popup, then Dark Reader's popup.
// Neither extension reads managed policies. Keep site exceptions and custom themes.
(async () => {
  const backupKey = "websiteGlassBackup";
  const id = browser.runtime.id;
  if (id === "{91aa3897-2634-4a8a-9092-279db23a7689}") {
    const stored = await browser.storage.local.get(["transparentZenSettings", backupKey]);
    if (!stored[backupKey]) {
      await browser.storage.local.set({ [backupKey]: stored.transparentZenSettings || {} });
    }
    await browser.storage.local.set({
      transparentZenSettings: {
        ...stored.transparentZenSettings,
        enableStyling: true,
        forceStyling: true,
        disableTransparency: false,
        disableDarkReader: false,
        // Enable glass without hiding navigation or footers.
        disableHover: true,
        disableFooter: true,
      },
    });
    console.log("Website glass: Zen Internet enabled; site exceptions preserved.");
    return;
  }
  if (id !== "addon@darkreader.org") {
    throw new Error("Open a Zen Internet or Dark Reader popup console first.");
  }
  const data = await new Promise((resolve, reject) => {
    const port = browser.runtime.connect({ name: "ui-bg-get-data" });
    const timeout = setTimeout(() => {
      port.disconnect();
      reject(new Error("Dark Reader did not return its settings."));
    }, 10000);
    port.onMessage.addListener((message) => {
      clearTimeout(timeout);
      port.disconnect();
      if (message.error || !message.data?.settings) {
        reject(new Error(message.error || "Missing Dark Reader settings."));
      } else {
        resolve(message.data);
      }
    });
  });
  const stored = await browser.storage.local.get(backupKey);
  if (!stored[backupKey]) {
    await browser.storage.local.set({ [backupKey]: data.settings });
  }
  await browser.runtime.sendMessage({
    type: "ui-bg-change-settings",
    data: {
      enabled: true,
      automation: { enabled: true, mode: "system", behavior: "Scheme" },
      // Otherwise native dark sites can be skipped even when a light theme is wanted.
      detectDarkTheme: false,
      theme: {
        ...data.settings.theme,
        engine: "dynamicTheme",
        lightSchemeBackgroundColor: "#faf4ed",
        lightSchemeTextColor: "#575279",
        darkSchemeBackgroundColor: "#191724",
        darkSchemeTextColor: "#e0def4",
      },
    },
  });
  console.log("Website glass: Dark Reader follows the system in both schemes.");
})();
