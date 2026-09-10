import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

process.env.EG_MOBILE_COUNTRY = 'JP';
const source = await readFile(new URL('./epic-games-mobile.js', import.meta.url), 'utf8');
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
const { getMobileGames } = await import(moduleUrl);

const navigated = [];
let currentPlatform;
const page = {
  async goto(url) {
    navigated.push(url);
    currentPlatform = new URL(url).searchParams.get('platform');
  },
  async innerText() {
    return JSON.stringify({
      data: [{
        type: 'freeGame',
        offers: [
          {
            content: {
              title: `Free ${currentPlatform}`,
              mapping: { slug: `free-${currentPlatform}` },
              purchase: [{ purchaseType: 'Claim', price: { decimalPrice: 0 } }],
            },
          },
          {
            content: {
              title: `Paid ${currentPlatform}`,
              mapping: { slug: `paid-${currentPlatform}` },
              purchase: [{ purchaseType: 'Purchase', price: { decimalPrice: 9.99 } }],
            },
          },
        ],
      }],
    });
  },
  async close() {},
};

const games = await getMobileGames({ async newPage() { return page; } });
assert.deepEqual(games.map(game => game.platform), ['android', 'ios']);
assert.ok(games.every(game => game.url.includes('/free-')));
assert.equal(navigated.length, 2);
assert.ok(navigated.every(url => new URL(url).searchParams.get('country') === 'JP'));
console.log('Epic mobile JP discovery test: ok');
