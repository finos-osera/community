import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeVex, fixedTotals, parseProduct, filterEntries, loadFeed, validateMetrics, recentReleases, latestReleases, groupReleases, advisoryUrl } from '../assets/feed-data.mjs';
const statement = (overrides = {}) => ({ vulnerability: { name: 'CVE-2026-1234', aliases: ['GHSA-example'] }, products: [{ '@id': 'pkg:maven/org.example/demo@1.0' }], status: 'fixed', supplier: 'Producer', ...overrides });
const doc = statements => ({ timestamp: '2026-10-28T12:00:00Z', statements });
test('expands products, preserves evidence and deduplicates fixed pairs across differing evidence', () => {
  const a = statement({ products: [{ '@id': 'pkg:maven/org.example/demo@1.0' }, { '@id': 'pkg:maven/org.example/demo@2.0' }] });
  const result = normalizeVex(doc([a, a, statement({ timestamp: '2026-10-27T12:00:00Z' }), statement({ status: 'affected' })]));
  assert.equal(result.entries.length, 4);
  assert.deepEqual(fixedTotals(result.entries), { libraries: 1, cves: 1, fixed: 2 });
  assert.equal(result.entries.at(-1).status, 'affected');
});
test('package identity preserves namespace, strips qualifiers, handles non-PURL products', () => {
  assert.deepEqual(parseProduct('pkg:npm/%40scope/demo@1.2?arch=x#src'), { library: '@scope:demo', version: '1.2', ecosystem: 'npm' });
  assert.equal(parseProduct('https://example.org/product').version, 'Not specified');
  assert.equal(parseProduct('pkg:maven/org.other/demo@1.0').library, 'org.other:demo');
});
test('filters aliases, supplier, exact library and status without treating absence as unaffected', () => {
  const entries = normalizeVex(doc([statement(), statement({ status: 'under_investigation', supplier: 'Other' })])).entries;
  assert.equal(filterEntries(entries, { q: 'ghsa-EXAMPLE', supplier: 'Producer', status: 'fixed', library: 'org.example:demo' }).length, 1);
  assert.equal(filterEntries(entries, { status: 'not_affected' }).length, 0);
  assert.equal(filterEntries(entries, { library: 'org.example:dem' }).length, 0);
});
test('rejects malformed documents instead of silently dropping records', () => {
  assert.throws(() => normalizeVex(doc([statement({ products: [{}] })])));
  assert.throws(() => normalizeVex({ statements: [] }));
  assert.throws(() => normalizeVex(doc([statement({ status: 'unknown' })])));
  assert.equal(normalizeVex(doc([])).entries.length, 0);
});
test('counts activity relative to snapshot UTC date, not browser clock', () => {
  const m = { as_of: '2026-10-28T12:00:00Z', totals: { libraries: 0, releases: 0, libraries_with_a_fixed_cve: 0, fixed_entries: 0 }, ecosystems: [], releases_per_day: [{ date: '2026-10-21', count: 100 }, { date: '2026-10-22', count: 3 }, { date: '2026-10-28', count: 2 }, { date: '2026-10-29', count: 100 }] };
  assert.equal(recentReleases(validateMetrics(m)), 5);
  assert.throws(() => validateMetrics({ ...m, totals: {} }));
});
test('network success works with unavailable browser storage', async () => {
  const result = await loadFeed('test', normalizeVex, { fetcher: async () => ({ ok: true, json: async () => doc([statement()]) }), storage: { setItem() { throw new Error('Quota'); } } });
  assert.equal(result.cached, false);
  assert.equal(result.data.entries.length, 1);
});
test('failed or invalid refresh uses only a validated cache and marks it cached', async () => {
  const storage = { getItem: () => JSON.stringify(doc([statement()])) };
  const result = await loadFeed('test', normalizeVex, { fetcher: async () => ({ ok: true, json: async () => ({}) }), storage });
  assert.equal(result.cached, true);
  assert.equal(result.data.entries.length, 1);
});
test('failed request without valid cache stays unavailable, never zero', async () => {
  const fetcher = async () => ({ ok: false });
  await assert.rejects(loadFeed('test', normalizeVex, { fetcher, storage: { getItem: () => '{}' } }));
  await assert.rejects(loadFeed('test', normalizeVex, { fetcher, storage: null }));
});

test('GHSA-only advisories remain navigable without inflating the CVE count', () => {
  const entries = normalizeVex(doc([statement(), statement({ vulnerability: { name: 'GHSA-example-only' } })])).entries;
  assert.deepEqual(fixedTotals(entries), { libraries: 1, cves: 1, fixed: 2 });
  assert.equal(filterEntries(entries, { q: 'GHSA-example-only' }).length, 1);
});

test('latest tags are numeric, isolated by version line and supplier, never by statement date', () => {
  const make = (version, supplier = 'A') => normalizeVex(doc([statement({ products: [{ '@id': 'pkg:maven/org.example/demo@' + version }], supplier })])).entries[0];
  const entries = [make('2.13.5.1-osera-9'), make('2.13.5.1-osera-10'), make('2.15.4.1-osera-2'), make('2.13.5.1-osera-3','B'), make('3.0-RC1'), make('3.0-RC2')];
  const latest = latestReleases(entries);
  assert.deepEqual(latest.map(x => x.version), ['2.13.5.1-osera-10','2.15.4.1-osera-2','2.13.5.1-osera-3','3.0-RC1','3.0-RC2']);
  assert.equal(filterEntries(latest, {q:'osera-9'}).length, 0);
  assert.equal(filterEntries(entries, {q:'osera-9'}).length, 1);
});
test('latest evidence retains carried-forward statements but does not invent inheritance', () => {
  const make = (version, cve) => statement({products:[{'@id':'pkg:maven/org.example/demo@1.0-osera-'+version}], vulnerability:{name:cve}});
  const entries = normalizeVex(doc([make('1','CVE-2026-1111'),make('1','CVE-2026-2222'),make('5','CVE-2026-1111'),make('5','CVE-2026-3333')])).entries;
  const releases = groupReleases(latestReleases(entries));
  assert.equal(releases.length,1);
  assert.deepEqual(releases[0].entries.map(x=>x.vulnerability),['CVE-2026-1111','CVE-2026-3333']);
  assert.equal(groupReleases(entries).length,2);
});
test('advisory links allow only canonical CVE and GHSA identifiers', () => {
  assert.equal(advisoryUrl('CVE-2025-66566'),'https://nvd.nist.gov/vuln/detail/CVE-2025-66566');
  assert.equal(advisoryUrl('GHSA-cmp6-m4wj-q63q'),'https://github.com/advisories/GHSA-cmp6-m4wj-q63q');
  assert.equal(advisoryUrl('javascript:alert(1)'),null);
  assert.equal(advisoryUrl('CVE-2025-66566/../../evil'),null);
});
