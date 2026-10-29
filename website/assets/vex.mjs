import { VEX_URL, CDX_URL, loadFeed, normalizeVex, fixedTotals, filterEntries, freshness, publicationLabel, advisoryUrl, latestReleases, groupReleases, releaseIdentity } from './feed-data.mjs';
const $ = id => document.getElementById(id);
const form = $('filters');
const labels = { fixed: 'Fixed', affected: 'Affected', not_affected: 'Not affected', under_investigation: 'Under investigation' };
const defaults = { view: 'libraries', releases: 'latest' };
const pageSize = 25;
let entries = [], page = 0, library = '', debounce;
let disclosureSequence = 0, disclosures = [];
document.addEventListener('pointerdown', event => { for (const disclosure of disclosures) if (!disclosure.host.contains(event.target)) disclosure.close(); });
document.addEventListener('keydown', event => { if (event.key === 'Escape') for (const disclosure of disclosures) disclosure.close(); });
function element(parent, tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  parent.appendChild(node); return node;
}
function link(parent, text, href, external = false) {
  const a = element(parent, 'a', text); a.href = href;
  if (external) { a.target = '_blank'; a.rel = 'noopener noreferrer'; a.setAttribute('aria-label', text + ' (opens in a new tab)'); }
  return a;
}
function button(parent, text, action, className = 'btn ghost') {
  const b = element(parent, 'button', text, className); b.type = 'button'; b.addEventListener('click', action); return b;
}
function readUrl() {
  const params = new URLSearchParams(location.search);
  for (const control of form.querySelectorAll('[name]')) {
    control.value = params.get(control.name) || defaults[control.name] || '';
    if (!control.value && defaults[control.name]) control.value = defaults[control.name];
  }
  page = Math.max(0, (Number.parseInt(params.get('page'), 10) || 1) - 1);
  library = params.get('library') || '';
}
function filters() { return { ...Object.fromEntries(new FormData(form)), library }; }
function updateUrl() {
  const url = new URL(location.href); url.search = '';
  for (const [key, value] of Object.entries(filters())) if (value && value !== defaults[key]) url.searchParams.set(key, value);
  if (page) url.searchParams.set('page', page + 1);
  history.replaceState(null, '', url);
}
function activeFilters() {
  const host = $('active-filters'); host.replaceChildren();
  const values = filters();
  const names = { library: 'Library', q: 'Search', status: 'Status', supplier: 'Supplier', ecosystem: 'Ecosystem' };
  const active = Object.entries(names).filter(([key]) => values[key]);
  host.hidden = !active.length;
  $('clear-filters').className = active.length ? 'btn primary' : 'btn ghost';
  $('clear-filters').textContent = active.length ? `Clear ${active.length} active filter${active.length === 1 ? '' : 's'}` : 'Clear filters';
  if (active.length) element(host, 'strong', 'Filtered view');
  for (const [key, name] of active) {
    const value = key === 'status' ? labels[values[key]] : values[key];
    const b = button(host, `${name}: ${value} ×`, () => {
      clearTimeout(debounce);
      if (key === 'library') library = ''; else form.elements.namedItem(key).value = '';
      page = 0; render(); $('clear-filters').focus();
    }, 'vex-filter-chip');
    b.setAttribute('aria-label', `Remove ${name.toLowerCase()} filter: ${value}`);
  }
}
function identifiers(host, ids) {
  for (const id of [...new Set(ids)]) {
    const url = advisoryUrl(id);
    if (url) link(host, id + ' ↗', url, true); else element(host, 'span', id);
  }
}
function advisories(host, records) {
  const fixed = records.filter(x => x.status === 'fixed');
  const ids = [...new Set(fixed.map(x => x.vulnerability))].sort();
  const aliases = [...new Set(fixed.flatMap(x => x.aliases))].filter(id => !ids.includes(id));
  const section = element(host, 'div', undefined, 'vex-advisories');
  if (!ids.length) { element(section, 'p', 'No fixed statements in this selection', 'feed-note'); return; }
  const cves = ids.filter(id => /^CVE-\d{4}-\d+$/i.test(id)).length;
  const count = `${cves} CVE${cves === 1 ? '' : 's'}` + (ids.length > cves ? ` · ${ids.length - cves} other advisor${ids.length - cves === 1 ? 'y' : 'ies'}` : '');
  let pinned = false;
  const trigger = button(section, `${count} addressed ▾`, () => {
    pinned = !pinned;
    setOpen(pinned);
  }, 'vex-fix-trigger');
  const panel = element(section, 'div', undefined, 'vex-fix-panel');
  panel.id = `fixes-${++disclosureSequence}`;
  panel.hidden = true;
  panel.setAttribute('role', 'region');
  panel.setAttribute('aria-label', 'CVEs addressed and offsite advisory details');
  trigger.setAttribute('aria-expanded', 'false');
  trigger.setAttribute('aria-controls', panel.id);
  element(panel, 'strong', 'CVEs addressed');
  element(panel, 'p', 'Published evidence for this release. Detail links open in a new tab.', 'feed-note');
  identifiers(element(panel, 'div', undefined, 'vex-advisory-links'), ids);
  if (aliases.length) {
    element(panel, 'p', 'Related advisory IDs', 'vex-evidence-label');
    identifiers(element(panel, 'div', undefined, 'vex-advisory-links'), aliases);
  }
  function setOpen(open) { panel.hidden = !open; trigger.setAttribute('aria-expanded', String(open)); }
  function close() {
    if (panel.contains(document.activeElement)) trigger.focus();
    pinned = false; setOpen(false);
  }
  button(panel, 'Close', () => { trigger.focus(); close(); }, 'vex-panel-close');
  section.addEventListener('pointerenter', event => { if (event.pointerType !== 'touch') setOpen(true); });
  section.addEventListener('pointerleave', () => { if (!pinned && !section.contains(document.activeElement)) setOpen(false); });
  section.addEventListener('focusin', () => setOpen(true));
  section.addEventListener('focusout', event => { if (!section.contains(event.relatedTarget)) close(); });
  disclosures.push({ host: section, close });
}

function evidence(row, records) {
  const details = element(row, 'details', undefined, 'vex-original');
  element(details, 'summary', records.length === 1 ? 'Inspect original statement' : `Inspect ${records.length} original statements`);
  details.addEventListener('toggle', () => {
    if (!details.open || details.dataset.loaded) return;
    details.dataset.loaded = 'true';
    const actions = element(details, 'div', undefined, 'feed-actions');
    link(actions, 'OpenVEX source', VEX_URL, true); link(actions, 'CycloneDX source', CDX_URL, true);
    const copy = button(actions, 'Copy package URL', async () => { try { await navigator.clipboard.writeText(records[0].purl); copy.textContent = 'Copied'; } catch { copy.textContent = 'Select the package URL above to copy'; } }, 'feed-retry');
    for (const item of records) {
      const section = element(details, 'section', undefined, 'vex-statement');
      identifiers(element(section, 'div', undefined, 'vex-advisory-links'), [item.vulnerability, ...item.aliases]);
      element(section, 'p', 'Publisher-reported status: ' + labels[item.status]);
      if (Number.isFinite(Date.parse(item.timestamp))) element(section, 'p', `Statement timestamp: ${publicationLabel(item.timestamp)}`, 'feed-note');
      element(section, 'pre', JSON.stringify(item.statement, null, 2));
    }
  });
}
function drill(item, view, all = false) {
  clearTimeout(debounce); library = item.library;
  $('ecosystem').value = item.ecosystem;
  $('view').value = view;
  if (all) $('releases').value = 'all';
  page = 0; render(); $('clear-filters').focus();
  $('active-filters').scrollIntoView({ block: 'center' });
}
function render() {
  disclosures = [];
  // Select latest versions before searching; an old matching CVE must never redefine "latest".
  const scoped = $('releases').value === 'all' ? entries : latestReleases(entries);
  const filtered = filterEntries(scoped, filters());
  const view = $('view').value;
  let items = filtered;
  if (view === 'libraries') {
    const groups = new Map();
    for (const entry of filtered) {
      const key = entry.ecosystem + ':' + entry.library;
      if (!groups.has(key)) groups.set(key, { library: entry.library, ecosystem: entry.ecosystem, entries: [] });
      groups.get(key).entries.push(entry);
    }
    items = [...groups.values()];
  } else if (view === 'releases') items = groupReleases(filtered);
  if (view !== 'releases') items.sort((a, b) => a.library.localeCompare(b.library) || (a.vulnerability || '').localeCompare(b.vulnerability || '') || (b.version || '').localeCompare(a.version || '', undefined, { numeric: true }));
  const pages = Math.max(1, Math.ceil(items.length / pageSize)); page = Math.min(page, pages - 1);
  updateUrl(); activeFilters();
  $('release-scope-note').textContent = $('releases').value === 'all' ? 'Showing all releases represented in VEX. Advisory lists apply to each exact release.' : 'Showing the highest OSERA tag per version line and supplier represented in VEX. Search older tags with “All releases in VEX”.';
  $('results-status').textContent = `${items.length.toLocaleString()} ${view === 'libraries' ? 'libraries' : view === 'releases' ? 'releases' : 'statements'} match · ${filtered.length.toLocaleString()} product statements`;
  $('page-status').textContent = `Page ${page + 1} of ${pages}`;
  $('previous').disabled = page === 0; $('next').disabled = page === pages - 1;
  const host = $('results'); host.replaceChildren();
  if (!items.length) element(host, 'p', 'No matching statements in this release scope. Try All releases in VEX, another search, or clear the active filters.', 'vex-empty');
  for (const item of items.slice(page * pageSize, (page + 1) * pageSize)) {
    const row = element(host, 'article', undefined, 'vex-record'); const summary = element(row, 'div');
    element(summary, 'h2', item.library);
    if (view === 'libraries') {
      const releases = groupReleases(item.entries);
      element(summary, 'p', `${item.ecosystem} · ${releases.length} matching release${releases.length === 1 ? '' : 's'}`);
      for (const release of releases.slice(0, 4)) {
        const releaseRow = element(summary, 'div', undefined, 'vex-release');
        element(releaseRow, 'h3', release.version);
        element(releaseRow, 'p', 'Supplier: ' + release.supplier, 'feed-note');
        advisories(releaseRow, release.entries);
      }
      if (releases.length > 4) element(summary, 'p', `Plus ${releases.length - 4} more matching releases. Inspect releases to see them all.`, 'feed-note');
      const actions = element(row, 'div', undefined, 'vex-row-actions');
      button(actions, 'Inspect releases →', () => drill(item, 'releases'));
      const all = entries.filter(x => x.library === item.library && x.ecosystem === item.ecosystem && (!$('supplier').value || x.supplier === $('supplier').value));
      const selected = new Set(scoped.map(releaseIdentity));
      const older = new Set(all.filter(x => !selected.has(releaseIdentity(x))).map(releaseIdentity)).size;
      if (older) button(actions, `See ${older} other release${older === 1 ? '' : 's'}`, () => drill(item, 'releases', true));
    } else {
      element(summary, 'h3', item.version);
      element(summary, 'p', item.purl, 'vex-coordinate');
      element(summary, 'p', `Supplier: ${item.supplier}`, 'feed-note');
      if (view === 'releases') advisories(summary, item.entries);
      else {
        identifiers(element(summary, 'div', undefined, 'vex-advisory-links'), [item.vulnerability, ...item.aliases]);
        const status = element(summary, 'span', labels[item.status], 'vex-status'); status.dataset.status = item.status;
      }
      evidence(row, view === 'releases' ? item.entries : [item]);
    }
  }
}
function options(id, values) {
  const select = $(id); select.replaceChildren();
  const all = element(select, 'option', id === 'supplier' ? 'All suppliers' : 'All ecosystems'); all.value = '';
  for (const value of [...new Set(values)].sort()) { const option = element(select, 'option', value); option.value = value; }
}
async function refresh() {
  $('retry').hidden = true; $('feed-status').textContent = 'Loading published OpenVEX statements…';
  try {
    const { data, cached } = await loadFeed(VEX_URL, normalizeVex); entries = data.entries;
    options('supplier', entries.map(x => x.supplier)); options('ecosystem', entries.map(x => x.ecosystem));
    readUrl();
    const totals = fixedTotals(entries); $('vex-summary').replaceChildren();
    for (const text of [`${totals.libraries} libraries with statements`, `${totals.cves} distinct CVEs addressed`, `${totals.fixed.toLocaleString()} patched entries`]) element($('vex-summary'), 'span', text);
    $('feed-status').textContent = freshness(data.published, cached);
    $('retry').hidden = !cached; $('vex-content').hidden = false; render();
  } catch {
    $('feed-status').textContent = 'The OpenVEX feed could not be loaded. Retry, or use the public feed links below.'; $('retry').hidden = false;
  }
}
form.addEventListener('submit', event => event.preventDefault());
form.addEventListener('input', event => { if (event.target.id !== 'query') return; clearTimeout(debounce); debounce = setTimeout(() => { page = 0; render(); }, 150); });
form.addEventListener('change', event => { if (event.target.id === 'query') return; clearTimeout(debounce); page = 0; render(); });
$('clear-filters').addEventListener('click', () => {
  clearTimeout(debounce);
  // Clearing filters preserves the explicit view and release-scope choices.
  for (const name of ['q', 'status', 'supplier', 'ecosystem']) form.elements.namedItem(name).value = '';
  library = ''; page = 0; render(); $('query').focus();
});
$('share').addEventListener('click', async () => { clearTimeout(debounce); render(); try { await navigator.clipboard.writeText(location.href); $('results-status').textContent = 'Link copied. It preserves this search, release scope, filters and page.'; } catch { $('results-status').textContent = 'Copy the URL from your address bar to share this view.'; } });
for (const [id, offset] of [['previous', -1], ['next', 1]]) $(id).addEventListener('click', () => { page += offset; render(); $('results-status').scrollIntoView({ block: 'center' }); });
window.addEventListener('popstate', () => { readUrl(); render(); }); $('retry').addEventListener('click', refresh); refresh();
