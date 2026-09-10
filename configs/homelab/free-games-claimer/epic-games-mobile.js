// Narrow override for the file shipped by feldorn/free-games-claimer commit 4fc0849.
// Keep this separate from the persistent browser data so the country used for
// discovery is declarative and reviewable in the NixOS configuration.

const country = process.env.EG_MOBILE_COUNTRY || 'JP';
if (!/^[A-Z]{2}$/.test(country)) throw new Error(`Invalid EG_MOBILE_COUNTRY: ${country}`);

const get = async (page, platform = 'android') => {
  if (!['android', 'ios'].includes(platform)) throw new Error(`Invalid Epic mobile platform: ${platform}`);
  const query = new URLSearchParams({
    count: '10',
    country,
    locale: 'en',
    platform,
    start: '0',
    store: 'EGS',
  });
  await page.goto(`https://egs-platform-service.store.epicgames.com/api/v2/public/discover/home?${query}`);
  return JSON.parse(await page.innerText('body'));
};

const productUrl = slug => `https://store.epicgames.com/en-US/p/${slug}`;

export const getPlatformGames = async (page, platform) => {
  const json = await get(page, platform);
  const section = json.data?.find(entry => entry.type === 'freeGame');
  if (!section) return [];

  return (section.offers || []).flatMap(offer => {
    const content = offer.content;
    const claimableForZero = content?.purchase?.some(
      purchase => purchase.purchaseType === 'Claim' && Number(purchase.price?.decimalPrice) === 0,
    );
    const slug = content?.mapping?.slug;
    return claimableForZero && slug ? [{ title: content.title, url: productUrl(slug), platform }] : [];
  });
};

export const getMobileGames = async context => {
  const page = await context.newPage();
  try {
    const games = [
      ...await getPlatformGames(page, 'android'),
      ...await getPlatformGames(page, 'ios'),
    ];
    return games.filter((game, index) => games.findIndex(other => other.url === game.url) === index);
  } finally {
    await page.close();
  }
};
