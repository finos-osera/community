import { VEX_URL, CDX_URL, loadFeed, normalizeVex, fixedTotals, filterEntries, freshness, publicationLabel } from './feed-data.mjs';
const $ = id => document.getElementById(id);
const form = $('filters');
const labels = { fixed: 'Fixed', affected: 'Affected', not_affected: 'Not affected', under_investigation: 'Under investigation' };
const pageSize = 25;
let entries = [], page = 0, library = '', debounce;
function element(parent, tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  parent.appendChild(node);
  return node;
}
function link(parent, text, href) { const a = element(parent, 'a', text); a.href = href; return a; }
function readUrl() {
  const params = new URLSearchParams(location.search);
  for (const control of form.querySelectorAll('[name]')) control.value = params.get(control.name) || (control.name === 'view' ? 'libraries' : '');
  if (!$('view').value) $('view').value = 'libraries';
  page = Math.max(0, (Number.parseInt(params.get('page'), 10) || 1) - 1);
  library = params.get('library') || '';
}
function filters() { return { ...Object.fromEntries(new FormData(form)), library }; }
function updateUrl() {
  const url = new URL(location.href); url.search = '';
  for (const [key, value] of Object.entries(filters())) if (value && !(key === 'view' && value === 'libraries')) url.searchParams.set(key, value);
  if (page) url.searchParams.set('page', page + 1);
  history.replaceState(null, '', url);
}
function render() {
  const filtered = filterEntries(entries, filters());
  const grouped = $('view').value === 'libraries';
  let items = filtered;
  if (grouped) {
    const groups = new Map();
    for (const entry of filtered) {
      const key = entry.ecosystem + ':' + entry.library;
      if (!groups.has(key)) groups.set(key, { library: entry.library, ecosystem: entry.ecosystem, entries: [], versions: new Set() });
      const group = groups.get(key); group.entries.push(entry); group.versions.add(entry.version);
    }
    items = [...groups.values()];
  }
  items.sort((a, b) => a.library.localeCompare(b.library) || (a.vulnerability || '').localeCompare(b.vulnerability || '') || (a.version || '').localeCompare(b.version || ''));
  const pages = Math.max(1, Math.ceil(items.length / pageSize));
  page = Math.min(page, pages - 1);
  updateUrl();
  $('results-status').textContent = `${items.length.toLocaleString()} ${grouped ? 'libraries' : 'statements'} match · ${filtered.length.toLocaleString()} product statements`;
  $('page-status').textContent = `Page ${page + 1} of ${pages}`;
  $('previous').disabled = page === 0; $('next').disabled = page === pages - 1;
  $('selected-library').hidden = !library;
  $('selected-library').textContent = library ? `Selected library: ${library}. Use Clear filters to return to all libraries.` : '';
  const host = $('results'); host.replaceChildren();
  if (!items.length) element(host, 'p', 'No matching published statements. Try another search or clear the filters.', 'vex-empty');
  for (const item of items.slice(page * pageSize, (page + 1) * pageSize)) {
    const row = element(host, 'article', undefined, 'vex-record');
    const summary = element(row, 'div');
    element(summary, 'h2', item.library);
    if (grouped) {
      const totals = fixedTotals(item.entries);
      element(summary, 'p', `${item.ecosystem} · ${item.versions.size} artifact versions · ${totals.cves} distinct fixed CVEs · ${totals.fixed} fixed entries`);
      element(summary, 'p', `${item.entries.length} published product statements`, 'feed-note');
      const button = element(row, 'button', 'Inspect versions →', 'btn ghost'); button.type = 'button';
      button.addEventListener('click', () => { library = item.library; $('ecosystem').value = item.ecosystem; $('view').value = 'entries'; page = 0; render(); $('view').focus(); });
    } else {
      element(summary, 'p', item.version + ' · ' + item.vulnerability);
      element(summary, 'p', item.purl, 'vex-coordinate');
      const status = element(summary, 'span', labels[item.status], 'vex-status'); status.dataset.status = item.status;
      element(summary, 'p', `Supplier: ${item.supplier}`);
      const details = element(row, 'details'); element(details, 'summary', 'Inspect original statement');
      details.addEventListener('toggle', () => {
        if (!details.open || details.dataset.loaded) return;
        details.dataset.loaded = 'true';
        if (Number.isFinite(Date.parse(item.timestamp))) element(details, 'p', `Statement timestamp: ${publicationLabel(item.timestamp)}`, 'feed-note');
        if (item.aliases.length) element(details, 'p', 'Aliases: ' + item.aliases.join(', '), 'feed-note');
        const actions = element(details, 'div', undefined, 'feed-actions');
        link(actions, 'OpenVEX source', VEX_URL); link(actions, 'CycloneDX source', CDX_URL);
        const copy = element(actions, 'button', 'Copy package URL', 'feed-retry'); copy.type = 'button';
        copy.addEventListener('click', async () => { try { await navigator.clipboard.writeText(item.purl); copy.textContent = 'Copied'; } catch { copy.textContent = 'Select the package URL above to copy'; } });
        element(details, 'pre', JSON.stringify(item.statement, null, 2));
      });
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
    const { data, cached } = await loadFeed(VEX_URL, normalizeVex);
    entries = data.entries;
    options('supplier', entries.map(x => x.supplier)); options('ecosystem', entries.map(x => x.ecosystem));
    $('ecosystem-filter').hidden = new Set(entries.map(x => x.ecosystem)).size <= 1;
    readUrl();
    const totals = fixedTotals(entries);
    $('vex-summary').replaceChildren();
    for (const text of [`${totals.libraries} libraries with statements`, `${totals.cves} distinct fixed CVEs`, `${totals.fixed.toLocaleString()} fixed entries`]) element($('vex-summary'), 'span', text);
    $('feed-status').textContent = freshness(data.published, cached);
    $('retry').hidden = !cached; $('vex-content').hidden = false; render();
  } catch {
    $('feed-status').textContent = 'The OpenVEX feed could not be loaded. Retry, or use the public feed links below.';
    $('retry').hidden = false;
  }
}
form.addEventListener('submit', event => event.preventDefault());
form.addEventListener('input', event => { if (event.target.id !== 'query') return; clearTimeout(debounce); debounce = setTimeout(() => { page = 0; render(); }, 150); });
form.addEventListener('change', event => { if (event.target.id === 'query') return; clearTimeout(debounce); page = 0; render(); });
$('reset').addEventListener('click', () => { clearTimeout(debounce); form.reset(); library = ''; page = 0; render(); $('query').focus(); });
$('share').addEventListener('click', async () => { clearTimeout(debounce); render(); try { await navigator.clipboard.writeText(location.href); $('results-status').textContent = 'Link copied. It preserves this search, filters and page.'; } catch { $('results-status').textContent = 'Copy the URL from your address bar to share this view.'; } });
for (const [id, offset] of [['previous', -1], ['next', 1]]) $(id).addEventListener('click', () => { page += offset; render(); $('results-status').scrollIntoView({ block: 'center' }); });
window.addEventListener('popstate', () => { readUrl(); render(); });
$('retry').addEventListener('click', refresh);
refresh();
