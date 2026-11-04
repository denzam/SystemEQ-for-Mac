const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const script = fs.readFileSync(path.join(__dirname, 'download-stats.js'), 'utf8');
const markup = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const ids = ['appDownloads', 'appDownloadCount', 'appDownloadsUpdated', 'appDownloadBreakdown', 'appDownloadDefinition', 'appDownloadStatus', 'appDownloadGrowth', 'appDownloadFiles', 'appDownloadFilesLabel', 'appDownloadFileHeading', 'appDownloadVersionHeading', 'appDownloadCountHeading', 'appDownloadAssets'];
const clone = value => JSON.parse(JSON.stringify(value));
const now = Date.now();
const updated = new Date(now - 3600000).toISOString();
const today = updated.slice(0, 10);
const previous = new Date(Date.parse(today) - 86400000).toISOString().slice(0, 10);
const sample = {
  schema_version: 2, total: 18, dmg: 10, zip: 5, homebrew: 3, other: 2, total_all_assets: 20,
  package_assets: 3, releases: 2, homebrew_available: true, updated_at: updated,
  history_since: previous, source: 'https://github.com/denzam/SystemEQ-for-Mac/releases',
  daily_change: { total: 6, dmg: 2, zip: 3, homebrew: 1, other: 1, total_all_assets: 7 },
  assets: [
    { id: 1, release_id: 10, version: 'v1.2.3', name: 'SystemEQ-v1.2.3.dmg', category: 'dmg', downloads: 10, size: 1 },
    { id: 2, release_id: 10, version: 'v1.2.3', name: 'SystemEQ-v1.2.3.zip', category: 'zip', downloads: 5, size: 1 },
    { id: 3, release_id: 10, version: 'v1.2.3', name: 'SystemEQ-v1.2.3-homebrew.dmg', category: 'homebrew', downloads: 3, size: 1 },
    { id: 4, release_id: 10, version: 'v1.2.3', name: '<img src=x onerror=alert(1)>', category: 'other', downloads: 2, size: 1 },
  ],
};
class Element {
  constructor() { this.textContent = ''; this.children = []; this.hidden = false; }
  replaceChildren(...items) { this.children = items; }
  append(...items) { this.children.push(...items); }
  set innerHTML(value) { throw new Error(`Unsafe HTML write: ${value}`); }
}
const flush = () => new Promise(resolve => setImmediate(resolve));
async function boot(initial, language = 'en') {
  const elements = Object.fromEntries(ids.map(id => [id, new Element()]));
  const documentEvents = {};
  const windowEvents = {};
  const responses = [initial];
  const document = {
    documentElement: { lang: language },
    getElementById: id => elements[id], createElement: () => new Element(),
    addEventListener: (event, handler) => { documentEvents[event] = handler; },
  };
  vm.runInNewContext(script, {
    document, window: { addEventListener: (event, handler) => { windowEvents[event] = handler; } },
    fetch: async () => {
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return { ok: !response?.httpError, status: response?.httpError || 200, json: async () => response };
    },
    Intl, Date, AbortController, setTimeout, clearTimeout, console: { warn() {} },
  });
  await flush();
  return {
    elements,
    async refresh(response) { responses.push(response); await windowEvents.focus(); },
    language(value) { document.documentElement.lang = value; documentEvents['seq-language-changed'](); },
  };
}
(async () => {
  for (const id of ids) assert(markup.includes(`id="${id}"`), `Missing markup ${id}`);
  const healthy = await boot(clone(sample));
  assert.equal(healthy.elements.appDownloadCount.textContent, '18');
  assert.equal(healthy.elements.appDownloadAssets.children.length, 4);
  assert.equal(healthy.elements.appDownloadAssets.children[3].children[0].textContent, sample.assets[3].name);
  assert.match(healthy.elements.appDownloadFilesLabel.textContent, /All files: 20/);
  assert.match(healthy.elements.appDownloadGrowth.textContent, /\+6/);
  assert.equal(healthy.elements.appDownloadsUpdated.dateTime, updated);
  assert.match(healthy.elements.appDownloadsUpdated.textContent, /UTC$/);
  healthy.language('uk');
  assert.match(healthy.elements.appDownloadDefinition.textContent, /Давні завантаження/);
  healthy.language('it');
  assert.match(healthy.elements.appDownloadGrowth.textContent, /Raccolta giornaliera/);
  healthy.language('en');
  await healthy.refresh(new Error('offline'));
  assert.equal(healthy.elements.appDownloadCount.textContent, '18');
  assert.equal(healthy.elements.appDownloadAssets.children.length, 4);
  assert.match(healthy.elements.appDownloadStatus.textContent, /last successful snapshot/);
  await healthy.refresh(clone(sample));
  assert.equal(healthy.elements.appDownloadStatus.textContent, '');
  const malformed = [
    data => { data.total += 1; },
    data => { data.assets[0].downloads += 1; },
    data => { data.assets[0].category = 'other'; },
    data => { data.assets[1].id = data.assets[0].id; },
    data => { data.assets[1].name = data.assets[0].name; data.assets[1].category = 'dmg'; },
    data => { data.assets[1].version = 'v2.0.0'; },
    data => { data.assets[0].size = 0; },
    data => { data.homebrew_available = false; },
    data => { data.daily_change.dmg = -1; },
    data => { data.daily_change.total_all_assets = 100; },
    data => { data.history_since = '2026-02-30'; },
    data => { data.updated_at = new Date(now + 86400000).toISOString(); },
    data => { data.updated_at = '2026-02-30T12:00:00Z'; },
    data => { data.updated_at = '2026-01-01T24:00:00Z'; },
    data => { data.source = 'https://example.com'; },
    data => { data.schema_version = 3; },
    data => { delete data.daily_change; },
  ];
  for (const mutate of malformed) {
    const data = clone(sample);
    mutate(data);
    const result = await boot(data);
    assert.equal(result.elements.appDownloadCount.textContent, '');
    assert.match(result.elements.appDownloadStatus.textContent, /unavailable/);
    assert.equal(result.elements.appDownloadAssets.children.length, 0);
  }
  for (const response of [null, new Error('offline'), { httpError: 503 }]) {
    const result = await boot(response);
    assert.match(result.elements.appDownloadStatus.textContent, /unavailable/);
  }
  const legacy = clone(sample);
  legacy.schema_version = 1;
  legacy.total = 15;
  delete legacy.assets;
  const old = await boot(legacy);
  assert.equal(old.elements.appDownloadCount.textContent, '15');
  assert(old.elements.appDownloadFiles.hidden);
  assert.match(old.elements.appDownloadBreakdown.children[2].textContent, /unavailable/);
  assert.match(old.elements.appDownloadDefinition.textContent, /only DMG and ZIP/);
  const stale = clone(sample);
  stale.updated_at = new Date(now - 3 * 86400000).toISOString();
  stale.history_since = stale.updated_at.slice(0, 10);
  stale.daily_change = null;
  const staleResult = await boot(stale);
  assert.equal(staleResult.elements.appDownloadCount.textContent, '18');
  assert.match(staleResult.elements.appDownloadStatus.textContent, /48 hours/);
  assert.match(staleResult.elements.appDownloadGrowth.textContent, /consecutive UTC/);
  await healthy.refresh(stale);
  assert.equal(healthy.elements.appDownloadsUpdated.dateTime, updated);
  assert.match(healthy.elements.appDownloadStatus.textContent, /last successful snapshot/);
  const noHomebrew = clone(sample);
  noHomebrew.homebrew_available = false;
  noHomebrew.assets.splice(2, 1);
  noHomebrew.package_assets = 2;
  noHomebrew.homebrew = 0;
  noHomebrew.total = 15;
  noHomebrew.total_all_assets = 17;
  noHomebrew.daily_change = null;
  const noHomebrewResult = await boot(noHomebrew);
  assert.equal(noHomebrewResult.elements.appDownloadCount.textContent, '15');
  assert.match(noHomebrewResult.elements.appDownloadDefinition.textContent, /not available yet/);
  assert.equal(noHomebrewResult.elements.appDownloadBreakdown.children[2].textContent, 'Homebrew file: unavailable');
  const zeroHomebrew = clone(sample);
  zeroHomebrew.assets[2].downloads = 0;
  zeroHomebrew.homebrew = 0;
  zeroHomebrew.total = 15;
  zeroHomebrew.total_all_assets = 17;
  zeroHomebrew.daily_change = null;
  const zeroHomebrewResult = await boot(zeroHomebrew);
  assert.equal(zeroHomebrewResult.elements.appDownloadCount.textContent, '15');
  assert.equal(zeroHomebrewResult.elements.appDownloadBreakdown.children[2].textContent, 'Homebrew file: 0');
  const nextTimestamp = new Date(now - 1800000).toISOString();
  const futureSnapshot = () => ({ ...clone(sample), updated_at: nextTimestamp, daily_change: null });
  const recount = data => {
    for (const category of ['dmg', 'zip', 'homebrew', 'other']) data[category] = data.assets.filter(asset => asset.category === category).reduce((total, asset) => total + asset.downloads, 0);
    data.total = data.dmg + data.zip + data.homebrew;
    data.total_all_assets = data.total + data.other;
    data.package_assets = data.assets.filter(asset => asset.category !== 'other').length;
    data.homebrew_available = data.assets.some(asset => asset.category === 'homebrew');
    return data;
  };
  const regressions = [
    ...[0, 1, 2, 3].map(index => data => { data.assets[index].downloads -= 1; recount(data); }),
    data => { data.releases = 1; },
    data => { data.schema_version = 1; data.dmg = 15; data.total = data.dmg + data.zip; delete data.assets; },
    data => { data.assets[0].id = 100; },
    data => { data.assets[0].size += 1; },
    data => { data.assets[3].name = 'renamed.txt'; },
    data => { for (const asset of data.assets) asset.release_id = 11; },
    data => { for (const asset of data.assets) { asset.version = 'v2.0.0'; asset.name = asset.name.replaceAll('v1.2.3', 'v2.0.0'); } },
    data => { data.assets.splice(3, 1, { ...data.assets[3], id: 100 }); },
    data => { data.assets[3].category = 'dmg'; data.assets[3].name = 'SystemEQ-v1.2.3.dmg'; data.assets[0].name = 'changed.dmg'; data.assets[0].category = 'other'; recount(data); },
    data => { data.assets[0].downloads -= 1; data.assets.push({ id: 100, release_id: 20, version: 'v2.0.0', name: 'SystemEQ-v2.0.0.dmg', category: 'dmg', downloads: 1, size: 1 }); recount(data); },
    data => { data.assets.splice(3, 1); data.assets.push({ id: 100, release_id: 10, version: 'v1.2.3', name: 'new.txt', category: 'other', downloads: 2, size: 1 }); recount(data); },
    data => { data.source = 'https://example.com'; },
  ];
  for (const mutate of regressions) {
    const data = futureSnapshot();
    mutate(data);
    const result = await boot(clone(sample));
    const before = JSON.stringify(result.elements.appDownloadAssets.children);
    await result.refresh(data);
    assert.equal(result.elements.appDownloadCount.textContent, '18');
    assert.equal(result.elements.appDownloadsUpdated.dateTime, updated);
    assert.equal(JSON.stringify(result.elements.appDownloadAssets.children), before);
    assert.match(result.elements.appDownloadStatus.textContent, /last successful snapshot/);
  }
  const noFile = clone(zeroHomebrew);
  noFile.updated_at = nextTimestamp;
  noFile.assets.splice(2, 1);
  recount(noFile);
  await zeroHomebrewResult.refresh(noFile);
  assert.equal(zeroHomebrewResult.elements.appDownloadsUpdated.dateTime, updated);
  assert.equal(zeroHomebrewResult.elements.appDownloadBreakdown.children[2].textContent, 'Homebrew file: 0');
  assert.match(zeroHomebrewResult.elements.appDownloadStatus.textContent, /last successful snapshot/);
  const growing = futureSnapshot();
  growing.assets[0].downloads += 3;
  growing.assets.push({ id: 100, release_id: 20, version: 'v2.0.0', name: 'SystemEQ-v2.0.0.dmg', category: 'dmg', downloads: 2, size: 1 });
  growing.releases += 1;
  recount(growing);
  const growthResult = await boot(clone(sample));
  await growthResult.refresh(growing);
  assert.equal(growthResult.elements.appDownloadCount.textContent, '23');
  assert.equal(growthResult.elements.appDownloadAssets.children.length, 5);
  assert.equal(growthResult.elements.appDownloadsUpdated.dateTime, nextTimestamp);
  assert.equal(growthResult.elements.appDownloadStatus.textContent, '');
  const migration = await boot(legacy);
  const current = futureSnapshot();
  await migration.refresh(current);
  assert.equal(migration.elements.appDownloadCount.textContent, '18');
  assert.equal(migration.elements.appDownloadAssets.children.length, 4);
  assert.equal(migration.elements.appDownloadStatus.textContent, '');
  assert.equal(migration.elements.appDownloadFiles.hidden, false);
  const legacyDecrease = clone(legacy);
  legacyDecrease.updated_at = nextTimestamp;
  legacyDecrease.dmg -= 1;
  legacyDecrease.total -= 1;
  const legacyResult = await boot(legacy);
  await legacyResult.refresh(legacyDecrease);
  assert.equal(legacyResult.elements.appDownloadCount.textContent, '15');
  assert.equal(legacyResult.elements.appDownloadsUpdated.dateTime, updated);
  assert.match(legacyResult.elements.appDownloadStatus.textContent, /last successful snapshot/);
  console.log('PASS: current and legacy data, three languages, safe filenames, sums/categories/IDs/dates/deltas, HTTP/offline, stale snapshots, refresh retention and recovery, monotonic counters, immutable file identities, schema migration, healthy growth and new files.');
})().catch(error => { console.error(error); process.exitCode = 1; });
