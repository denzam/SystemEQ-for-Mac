(() => {
  const ids = ['appDownloads', 'appDownloadCount', 'appDownloadsUpdated', 'appDownloadBreakdown', 'appDownloadDefinition', 'appDownloadStatus', 'appDownloadGrowth', 'appDownloadFiles', 'appDownloadFilesLabel', 'appDownloadFileHeading', 'appDownloadVersionHeading', 'appDownloadCountHeading', 'appDownloadAssets'];
  const elements = Object.fromEntries(ids.map(id => [id, document.getElementById(id)]));
  if (Object.values(elements).some(element => !element)) return;
  const translations = {
    en: {
      loading: 'Loading download statistics…', unavailable: 'Download statistics are currently unavailable.',
      failed: 'Refresh failed; showing the last successful snapshot.', stale: 'This snapshot is over 48 hours old.',
      dmg: 'DMG', zip: 'ZIP', homebrew: 'Homebrew file', other: 'Other files', unknown: 'unavailable',
      definition: 'Across published stable releases. App total = DMG + ZIP + Homebrew file. Older Homebrew downloads are included in DMG and cannot be separated. ZIP includes Sparkle updates. The Homebrew file can also be downloaded manually. GitHub’s automatic Source code archives have no exposed download counts.',
      legacy: 'This older snapshot contains only DMG and ZIP counts. Homebrew, other files, file details and daily growth are unavailable. Older Homebrew downloads are included in DMG; ZIP includes Sparkle updates. GitHub’s automatic Source code archives have no exposed download counts.',
      noHomebrew: 'A separate Homebrew file is not available yet; its counter starts when that file is introduced.',
      files: 'All uploaded release files', file: 'File', version: 'Version', downloads: 'Downloads',
      since: 'Daily collection since {date}.', growth: 'App downloads since the previous UTC day: +{count}.',
      noGrowth: 'Daily growth is unavailable until consecutive UTC-day snapshots exist.',
      all: 'All files',
    },
    it: {
      loading: 'Caricamento delle statistiche…', unavailable: 'Le statistiche dei download non sono al momento disponibili.',
      failed: 'Aggiornamento non riuscito; viene mostrata l’ultima rilevazione riuscita.', stale: 'Questa rilevazione risale a oltre 48 ore fa.',
      dmg: 'DMG', zip: 'ZIP', homebrew: 'File Homebrew', other: 'Altri file', unknown: 'non disponibile',
      definition: 'Rilasci stabili pubblicati. Totale app = DMG + ZIP + file Homebrew. I vecchi download Homebrew sono inclusi nei DMG e non possono essere separati. ZIP include gli aggiornamenti Sparkle. Il file Homebrew può essere scaricato anche manualmente. GitHub non espone i conteggi degli archivi Source code automatici.',
      legacy: 'Questa vecchia rilevazione contiene solo i conteggi DMG e ZIP. Homebrew, altri file, dettagli dei file e crescita giornaliera non sono disponibili. I vecchi download Homebrew sono inclusi nei DMG; ZIP include gli aggiornamenti Sparkle. GitHub non espone i conteggi degli archivi Source code automatici.',
      noHomebrew: 'Un file Homebrew separato non è ancora disponibile; il suo conteggio inizia quando viene introdotto.',
      files: 'Tutti i file caricati nei rilasci', file: 'File', version: 'Versione', downloads: 'Download',
      since: 'Raccolta giornaliera dal {date}.', growth: 'Download app dal giorno UTC precedente: +{count}.',
      noGrowth: 'La crescita giornaliera sarà disponibile con rilevazioni di giorni UTC consecutivi.',
      all: 'Tutti i file',
    },
    uk: {
      loading: 'Завантаження статистики…', unavailable: 'Статистика завантажень зараз недоступна.',
      failed: 'Не вдалося оновити дані; показано останній успішний знімок.', stale: 'Цьому знімку понад 48 годин.',
      dmg: 'DMG', zip: 'ZIP', homebrew: 'Файл Homebrew', other: 'Інші файли', unknown: 'недоступно',
      definition: 'Опубліковані стабільні релізи. Разом для програми = DMG + ZIP + файл Homebrew. Давні завантаження Homebrew входять у DMG і невіддільні від них. ZIP включає оновлення Sparkle. Файл Homebrew можна завантажити й вручну. GitHub не надає лічильників автоматичних архівів Source code.',
      legacy: 'Цей давніший знімок містить лише DMG і ZIP. Homebrew, інші файли, перелік файлів і добовий приріст недоступні. Давні завантаження Homebrew входять у DMG; ZIP включає оновлення Sparkle. GitHub не надає лічильників автоматичних архівів Source code.',
      noHomebrew: 'Окремого файлу Homebrew ще немає; його лічильник почнеться з появою цього файлу.',
      files: 'Усі завантажені файли релізів', file: 'Файл', version: 'Версія', downloads: 'Завантаження',
      since: 'Щоденний збір із {date}.', growth: 'Завантаження програми від попередньої доби UTC: +{count}.',
      noGrowth: 'Добовий приріст буде доступний після знімків за послідовні доби UTC.',
      all: 'Усі файли',
    },
  };
  const source = 'https://github.com/denzam/SystemEQ-for-Mac/releases';
  const categories = ['dmg', 'zip', 'homebrew', 'other'];
  const counts = ['total', ...categories, 'total_all_assets'];
  const integer = value => Number.isSafeInteger(value) && value >= 0;
  const dateOnly = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
  const validTimestamp = value => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|\+00:00)$/.test(value)) return false;
    const timestamp = Date.parse(value);
    return dateOnly(value.slice(0, 10)) && Number.isFinite(timestamp) && new Date(timestamp).toISOString().slice(0, 19) === value.slice(0, 19) && timestamp <= Date.now() + 300000;
  };
  const validTotals = data => counts.every(key => integer(data[key])) && data.total === data.dmg + data.zip + data.homebrew && data.total_all_assets === data.total + data.other;
  const validate = data => {
    if (!data || ![1, 2].includes(data.schema_version) || ![data.total, data.dmg, data.zip, data.package_assets, data.releases].every(integer) || data.package_assets === 0 || !validTimestamp(data.updated_at) || data.source !== source) throw new Error('Invalid download statistics');
    if (data.schema_version === 1) {
      if (data.total !== data.dmg + data.zip) throw new Error('Invalid legacy totals');
      return data;
    }
    if (!validTotals(data) || typeof data.homebrew_available !== 'boolean' || !Array.isArray(data.assets) || !dateOnly(data.history_since) || data.history_since > data.updated_at.slice(0, 10)) throw new Error('Invalid download breakdown');
    const sums = { dmg: 0, zip: 0, homebrew: 0, other: 0 };
    const assetIds = new Set();
    const fileNames = new Set();
    const releaseVersions = new Map();
    const versionIds = new Map();
    let packages = 0;
    let homebrewAssets = 0;
    for (const asset of data.assets) {
      if (!asset || !integer(asset.id) || asset.id === 0 || assetIds.has(asset.id) || !integer(asset.release_id) || asset.release_id === 0 || typeof asset.version !== 'string' || !/^v\d+\.\d+\.\d+$/.test(asset.version) || typeof asset.name !== 'string' || !asset.name.trim() || !categories.includes(asset.category) || !integer(asset.downloads) || !integer(asset.size) || asset.size === 0) throw new Error('Invalid release file');
      const expected = asset.name === `SystemEQ-${asset.version}.dmg` ? 'dmg' : asset.name === `SystemEQ-${asset.version}.zip` ? 'zip' : asset.name === `SystemEQ-${asset.version}-homebrew.dmg` ? 'homebrew' : 'other';
      const fileKey = JSON.stringify([asset.release_id, asset.name]);
      if (fileNames.has(fileKey) || asset.category !== expected || (releaseVersions.has(asset.release_id) && releaseVersions.get(asset.release_id) !== asset.version) || (versionIds.has(asset.version) && versionIds.get(asset.version) !== asset.release_id)) throw new Error('Invalid file category or version');
      assetIds.add(asset.id);
      fileNames.add(fileKey);
      releaseVersions.set(asset.release_id, asset.version);
      versionIds.set(asset.version, asset.release_id);
      sums[asset.category] += asset.downloads;
      if (!integer(sums[asset.category])) throw new Error('Download sum overflow');
      if (asset.category !== 'other') packages += 1;
      if (asset.category === 'homebrew') homebrewAssets += 1;
    }
    if (categories.some(key => sums[key] !== data[key]) || packages !== data.package_assets || data.homebrew_available !== (homebrewAssets > 0) || releaseVersions.size > data.releases) throw new Error('Inconsistent download totals');
    if (data.daily_change !== null && (!data.daily_change || !validTotals(data.daily_change) || counts.some(key => data.daily_change[key] > data[key]) || data.history_since === data.updated_at.slice(0, 10))) throw new Error('Invalid daily change');
    return data;
  };
  const validateTransition = (previous, next) => {
    if (Date.parse(next.updated_at) < Date.parse(previous.updated_at) || next.schema_version < previous.schema_version) throw new Error('Older download snapshot');
    const comparable = previous.schema_version === 1 ? ['total', 'dmg', 'zip', 'package_assets', 'releases'] : [...counts, 'package_assets', 'releases'];
    if (comparable.some(key => next[key] < previous[key])) throw new Error('Download counter decreased');
    if (previous.schema_version !== 2) return;
    const nextAssets = new Map(next.assets.map(asset => [asset.id, asset]));
    const identity = ['release_id', 'version', 'name', 'category', 'size'];
    for (const asset of previous.assets) {
      const replacement = nextAssets.get(asset.id);
      if (!replacement || identity.some(key => replacement[key] !== asset[key]) || replacement.downloads < asset.downloads) throw new Error('Previously known release file changed or disappeared');
    }
  };
  let snapshot = null;
  let failed = false;
  let pending = false;
  const put = (id, value) => { elements[id].textContent = value; };
  const render = () => {
    const language = Object.hasOwn(translations, document.documentElement.lang) ? document.documentElement.lang : 'en';
    const t = translations[language];
    const number = value => new Intl.NumberFormat(language).format(value);
    put('appDownloadStatus', snapshot ? [failed ? t.failed : '', Date.now() - Date.parse(snapshot.updated_at) > 172800000 ? t.stale : ''].filter(Boolean).join(' ') : failed ? t.unavailable : t.loading);
    if (!snapshot) return;
    put('appDownloadCount', number(snapshot.total));
    elements.appDownloadsUpdated.dateTime = snapshot.updated_at;
    put('appDownloadsUpdated', new Intl.DateTimeFormat(language, { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }).format(new Date(snapshot.updated_at)) + ' UTC');
    elements.appDownloadBreakdown.replaceChildren();
    for (const category of categories) {
      const item = document.createElement('span');
      const known = (snapshot.schema_version === 2 || ['dmg', 'zip'].includes(category)) && (category !== 'homebrew' || snapshot.homebrew_available === true);
      item.textContent = `${t[category]}: ${known ? number(snapshot[category]) : t.unknown}`;
      elements.appDownloadBreakdown.append(item);
    }
    put('appDownloadDefinition', snapshot.schema_version === 1 ? t.legacy : `${t.definition}${snapshot.homebrew_available ? '' : ' ' + t.noHomebrew}`);
    elements.appDownloadFiles.hidden = snapshot.schema_version !== 2;
    elements.appDownloadAssets.replaceChildren();
    put('appDownloadGrowth', '');
    if (snapshot.schema_version !== 2) return;
    const historyDate = new Intl.DateTimeFormat(language, { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(snapshot.history_since + 'T00:00:00Z'));
    const growth = snapshot.daily_change;
    put('appDownloadGrowth', `${t.since.replace('{date}', historyDate)} ${growth ? t.growth.replace('{count}', number(growth.total)) + ' ' + categories.map(key => `${t[key]}: +${number(growth[key])}`).join(' · ') : t.noGrowth}`);
    put('appDownloadFilesLabel', `${t.files} (${number(snapshot.assets.length)}) · ${t.all}: ${number(snapshot.total_all_assets)}`);
    put('appDownloadFileHeading', t.file);
    put('appDownloadVersionHeading', t.version);
    put('appDownloadCountHeading', t.downloads);
    for (const asset of snapshot.assets) {
      const row = document.createElement('tr');
      for (const value of [asset.name, asset.version, number(asset.downloads)]) {
        const cell = document.createElement('td');
        cell.textContent = value;
        row.append(cell);
      }
      elements.appDownloadAssets.append(row);
    }
  };
  const refresh = async () => {
    if (pending) return;
    pending = true;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetch('app-downloads.json', { signal: controller.signal, cache: 'no-cache' });
      if (!response.ok) throw new Error(`Download statistics HTTP ${response.status}`);
      const data = validate(await response.json());
      if (snapshot) validateTransition(snapshot, data);
      snapshot = data;
      failed = false;
    } catch (error) {
      failed = true;
      console.warn('Application download statistics unavailable:', error.message);
    } finally {
      clearTimeout(timeout);
      pending = false;
      render();
    }
  };
  document.addEventListener('seq-language-changed', render);
  window.addEventListener('online', refresh);
  window.addEventListener('focus', refresh);
  render();
  refresh();
})();
