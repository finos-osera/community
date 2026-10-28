export const METRICS_URL = 'https://feed.finos.org/stats/metrics.json';
export const VEX_URL = 'https://feed.finos.org/openvex.json';
export const CDX_URL = 'https://feed.finos.org/cyclonedx.json';
export const STATUSES = ['fixed', 'affected', 'not_affected', 'under_investigation'];
export function timestamp(value) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw new Error('Missing publication timestamp');
  return value;
}
export function validateMetrics(data) {
  timestamp(data?.as_of);
  for (const field of ['libraries', 'releases', 'libraries_with_a_fixed_cve', 'fixed_entries']) {
    if (!Number.isSafeInteger(data?.totals?.[field]) || data.totals[field] < 0) throw new Error('Invalid metrics');
  }
  if (!Array.isArray(data.ecosystems) || !data.ecosystems.every(x => typeof x === 'string')) throw new Error('Invalid ecosystems');
  if (!Array.isArray(data.releases_per_day) || !data.releases_per_day.every(x => /^\d{4}-\d{2}-\d{2}$/.test(x.date) && Number.isSafeInteger(x.count) && x.count >= 0)) throw new Error('Invalid activity');
  return data;
}
export function recentReleases(data) {
  const end = Date.parse(data.as_of.slice(0, 10) + 'T00:00:00Z');
  return data.releases_per_day.filter(x => { const day = Date.parse(x.date); return day <= end && day >= end - 6 * 86400000; }).reduce((sum, x) => sum + x.count, 0);
}
export function parseProduct(id) {
  if (typeof id !== 'string' || !id) throw new Error('Missing product identifier');
  const match = /^pkg:([^/]+)\/(.+)$/.exec(id);
  if (!match) return { library: id, version: 'Not specified', ecosystem: 'Other' };
  const coordinate = match[2].split(/[?#]/)[0];
  const at = coordinate.lastIndexOf('@');
  const decode = value => { try { return decodeURIComponent(value); } catch { return value; } };
  return { library: decode(at < 0 ? coordinate : coordinate.slice(0, at)).replaceAll('/', ':'), version: at < 0 ? 'Not specified' : decode(coordinate.slice(at + 1)), ecosystem: match[1] === 'maven' ? 'Java' : match[1] };
}
export function normalizeVex(data) {
  timestamp(data?.last_updated || data?.timestamp);
  if (!Array.isArray(data.statements)) throw new Error('Invalid VEX document');
  const records = new Map();
  for (const statement of data.statements) {
    const vulnerability = statement.vulnerability?.name || statement.vulnerability?.['@id'];
    if (!vulnerability || typeof vulnerability !== 'string' || !STATUSES.includes(statement.status) || !Array.isArray(statement.products) || !statement.products.length) throw new Error('Invalid VEX statement');
    for (const product of statement.products) {
      const purl = product['@id'];
      const entry = { ...parseProduct(purl), purl, vulnerability, status: statement.status,
        aliases: Array.isArray(statement.vulnerability.aliases) ? statement.vulnerability.aliases.filter(x => typeof x === 'string') : [],
        supplier: typeof statement.supplier === 'string' ? statement.supplier : 'Not specified',
        timestamp: statement.timestamp || '', statement };
      // Preserve differing statements/statuses rather than silently overwriting evidence.
      const key = JSON.stringify([purl, vulnerability, statement]);
      records.set(key, entry);
    }
  }
  return { published: data.last_updated || data.timestamp, version: data.version, entries: [...records.values()] };
}
export function fixedTotals(entries) {
  const fixed = entries.filter(x => x.status === 'fixed');
  return { libraries: new Set(entries.map(x => x.ecosystem + ':' + x.library)).size,
    cves: new Set(fixed.filter(x => /^CVE-\d{4}-\d+$/i.test(x.vulnerability)).map(x => x.vulnerability.toUpperCase())).size,
    fixed: new Set(fixed.map(x => JSON.stringify([x.purl, x.vulnerability.toUpperCase()]))).size };
}
export function filterEntries(entries, filters) {
  const term = (filters.q || '').trim().toLowerCase();
  return entries.filter(x => (!filters.status || x.status === filters.status) && (!filters.supplier || x.supplier === filters.supplier) && (!filters.ecosystem || x.ecosystem === filters.ecosystem) && (!filters.library || x.library === filters.library) && (!term || [x.library, x.version, x.purl, x.vulnerability, ...x.aliases, x.supplier].join(' ').toLowerCase().includes(term)));
}
export async function loadFeed(url, validate, { fetcher = globalThis.fetch, storage } = {}) {
  const key = 'osera-feed-v1:' + url;
  if (storage === undefined) { try { storage = globalThis.localStorage; } catch { storage = null; } }
  try {
    const response = await fetcher(url, { signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error('Feed request failed');
    const raw = await response.json();
    const data = validate(raw);
    try { storage?.setItem(key, JSON.stringify(raw)); } catch { /* Browsing without storage is supported. */ }
    return { data, cached: false };
  } catch (error) {
    try {
      const raw = storage?.getItem(key);
      if (raw) return { data: validate(JSON.parse(raw)), cached: true };
    } catch { /* Invalid caches must not replace an unavailable feed with false data. */ }
    throw error;
  }
}
export function publicationLabel(value) {
  return new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }).format(new Date(value)) + ' UTC';
}
export function freshness(value, cached) {
  const days = Math.max(0, Math.floor((Date.now() - Date.parse(value)) / 86400000));
  return (cached ? 'Update unavailable — showing the last saved snapshot. ' : '') + 'Published ' + publicationLabel(value) + (days >= 1 ? ` · ${days} day${days === 1 ? '' : 's'} old` : '');
}

export function advisoryUrl(id) {
  if (/^CVE-\d{4}-\d+$/i.test(id)) return 'https://nvd.nist.gov/vuln/detail/' + id.toUpperCase();
  if (/^GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}$/i.test(id)) return 'https://github.com/advisories/' + id.toLowerCase().replace('ghsa-', 'GHSA-');
  return null;
}
export function releaseIdentity(entry) { return JSON.stringify([entry.purl, entry.supplier]); }
export function versionLine(entry) {
  const match = /^(.*)-osera-(\d+)$/.exec(entry.version);
  return match ? { base: match[1], sequence: BigInt(match[2]), key: JSON.stringify([entry.ecosystem, entry.library, entry.supplier, match[1]]) } : null;
}
export function latestReleases(entries) {
  const latest = new Map();
  for (const entry of entries) {
    const line = versionLine(entry);
    if (line && (!latest.has(line.key) || line.sequence > latest.get(line.key))) latest.set(line.key, line.sequence);
  }
  // Unknown version schemes are retained; statement dates are not release dates.
  return entries.filter(entry => { const line = versionLine(entry); return !line || line.sequence === latest.get(line.key); });
}
export function groupReleases(entries) {
  const groups = new Map();
  for (const entry of entries) {
    const key = releaseIdentity(entry);
    if (!groups.has(key)) groups.set(key, { ...entry, entries: [] });
    groups.get(key).entries.push(entry);
  }
  return [...groups.values()].sort((a, b) => a.library.localeCompare(b.library) || a.supplier.localeCompare(b.supplier) || b.version.localeCompare(a.version, undefined, { numeric: true }));
}
