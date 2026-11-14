// Run in the Multi-Account Containers options page's Web Console, once per profile.
// Assigns sites to "Always open in" containers through the extension's own messages, so a
// bookmark (floccus syncs no container) or a temporary-container tab lands in the right one.
// Assignments match the exact hostname. Google, Slack and Notion stay unassigned: one hostname
// serves more than one account there.
(async () => {
  if (browser.runtime.id !== "@testpilot-containers") {
    throw new Error("Run this in Firefox Multi-Account Containers' options page.");
  }

  const sites = {
    Univ: [
      "utol.ecc.u-tokyo.ac.jp",
      "utas.adm.u-tokyo.ac.jp",
      "classroom.google.com",
    ],
    Shopping: [
      "www.amazon.co.jp",
    ],
    Banking: [
      "www.smbc.co.jp",
      "direct.smbc.co.jp",
      "www.aozorabank.co.jp",
      "www.sbishinseibank.co.jp",
      "bk.web.sbishinseibank.co.jp",
      "gmo-aozora.com",
      "bank.gmo-aozora.com",
      "sso.gmo-aozora.com",
      "www.rakuten-bank.co.jp",
      "fes.rakuten-bank.co.jp",
      "www.sbisec.co.jp",
      "site1.sbisec.co.jp",
    ],
  };

  const identities = await browser.contextualIdentities.query({});
  const targets = Object.entries(sites).flatMap(([container, hosts]) => {
    const matches = identities.filter(identity => identity.name === container);
    if (matches.length !== 1) {
      throw new Error(`Expected one ${container} container, found ${matches.length}.`);
    }
    const { cookieStoreId } = matches[0];
    return hosts.map(host => ({
      container,
      host,
      cookieStoreId,
      userContextId: cookieStoreId.replace("firefox-container-", ""),
      key: `siteContainerMap@@_${host}`,
    }));
  });

  const backupKey = "dotfilesContainerSitesBackup";
  if (!(await browser.storage.local.get(backupKey))[backupKey]) {
    const previous = await browser.storage.local.get(targets.map(target => target.key));
    await browser.storage.local.set({ [backupKey]: previous });
  }

  for (const target of targets) {
    const url = `https://${target.host}/`;
    await browser.runtime.sendMessage({
      method: "setOrRemoveAssignment",
      url,
      userContextId: target.userContextId,
      value: false,
    });
    // Without neverAsk every visit from another container stops at the confirm page, which is
    // every visit: new tabs open in temporary containers.
    await browser.runtime.sendMessage({
      method: "neverAsk",
      neverAsk: true,
      pageUrl: url,
      cookieStoreId: target.cookieStoreId,
    });
  }

  // neverAsk is applied without being awaited by the extension; give it a moment.
  await new Promise(resolve => setTimeout(resolve, 1000));
  const saved = await browser.storage.local.get(targets.map(target => target.key));
  for (const target of targets) {
    const entry = saved[target.key];
    if (entry?.userContextId !== target.userContextId || entry?.neverAsk !== true) {
      throw new Error(`Could not verify ${target.host} -> ${target.container}.`);
    }
  }
  console.table(targets.map(({ container, host }) => ({ container, host })));
  return targets.length;
})();
