import { ARTIFACTS_URL, artifactSourceIndex, VEX_URL, CDX_URL, loadFeed, normalizeVex, fixedTotals, filterEntries, freshness, publicationLabel, advisoryUrl, latestReleases, groupReleases, releaseIdentity } from './feed-data.mjs';
const $ = id => document.getElementById(id);
const releaseScope = () => form.elements.namedItem('releases');
const form = $('filters');
const labels = { fixed: 'Fixed', affected: 'Affected', not_affected: 'Not affected', under_investigation: 'Under investigation' };
const defaults = { view: 'libraries', releases: 'latest', pageSize: '5' };
function pageLength(count) {
  const choice = document.getElementById('page-size');
  const raw = choice ? choice.value : '5';
  if (raw === 'all') return Math.max(count, 1);
  const size = Number.parseInt(raw, 10);
  return Number.isFinite(size) && size > 0 ? size : 5;
}
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
  const size = document.getElementById('page-size');
  if (size) size.value = params.get('pageSize') || defaults.pageSize;
}
function filters() { return { ...Object.fromEntries(new FormData(form)), library }; }
function updateUrl() {
  const url = new URL(location.href); url.search = '';
  for (const [key, value] of Object.entries(filters())) if (value && value !== defaults[key]) url.searchParams.set(key, value);
  if (page) url.searchParams.set('page', page + 1);
  const size = document.getElementById('page-size');
  if (size && size.value && size.value !== defaults.pageSize) url.searchParams.set('pageSize', size.value);
  history.replaceState(null, '', url);
}
function clearRealFilters() {
  for (const name of ['q', 'status', 'supplier', 'ecosystem']) form.elements.namedItem(name).value = '';
  library = '';
}
function iconButton(parent, label, svg, action) {
  const b = element(parent, 'button', undefined, 'icon-btn');
  b.type = 'button'; b.title = label; b.setAttribute('aria-label', label);
  b.innerHTML = svg; b.addEventListener('click', action); return b;
}
function activeFilters() {
  const host = $('active-filters'); host.replaceChildren(); host.hidden = false;
  const values = filters();
  const names = { library: 'Library', q: 'Search', status: 'Status', supplier: 'Producer', ecosystem: 'Ecosystem' };
  const active = Object.entries(names).filter(([key]) => values[key]);
  const viewLabels = { libraries: 'Libraries', releases: 'Maintained versions', entries: 'Individual statements' };
  const head = element(host, 'div', undefined, 'vex-active-head');
  element(head, 'strong', 'Filtered view');
  const tools = element(head, 'div', undefined, 'vex-active-tools');
  if (active.length) {
    iconButton(tools, 'remove all filters', '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" d="M6 6l12 12M18 6L6 18"/></svg>', () => {
      clearTimeout(debounce); clearRealFilters(); page = 0; render(); $('query').focus();
    });
    iconButton(tools, 'copy this view link', '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2" fill="none" stroke="currentColor" stroke-width="2"/><path fill="none" stroke="currentColor" stroke-width="2" d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg>', async () => {
      clearTimeout(debounce); render();
      try { await navigator.clipboard.writeText(location.href); $('results-status').textContent = 'Link copied. It preserves this search, release scope, filters and page.'; }
      catch { $('results-status').textContent = 'Copy the URL from your address bar to share this view.'; }
    }).id = 'share';
  }
  const chips = element(host, 'div', undefined, 'vex-chip-row');
  const locked = [
    ['View', viewLabels[values.view] || values.view],
    ['Release scope', releaseScope().value === 'all' ? 'All maintained versions in VEX' : 'Latest OSERA tag per version line']
  ];
  for (const [name, value] of locked) {
    const chip = element(chips, 'span', `${name}: ${value}`, 'vex-filter-chip is-locked');
    chip.title = 'Change this with the options above';
  }
  for (const [key, name] of active) {
    const value = key === 'status' ? labels[values[key]] : values[key];
    const chip = button(chips, `${name}: ${value} ×`, () => {
      clearTimeout(debounce);
      if (key === 'library') library = ''; else form.elements.namedItem(key).value = '';
      page = 0; render();
    }, 'vex-filter-chip');
    chip.setAttribute('aria-label', `Remove ${name.toLowerCase()} filter: ${value}`);
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

// Resolve published mappings once per page, without delaying the VEX results.
let sourceIndexRequest;
const sourceIcons = {
  repository: 'M12 2C6.48 2 2 6.48 2 12c0 4.42 2.87 8.17 6.84 9.5.5.09.68-.22.68-.48v-1.86c-2.78.6-3.37-1.18-3.37-1.18-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.61.07-.61 1 .07 1.53 1.03 1.53 1.03.89 1.53 2.34 1.09 2.91.83.09-.65.35-1.09.64-1.34-2.22-.25-4.56-1.11-4.56-4.94 0-1.09.39-1.99 1.03-2.69-.1-.25-.45-1.27.1-2.65 0 0 .84-.27 2.75 1.03A9.6 9.6 0 0 1 12 6.83c.85 0 1.71.11 2.51.34 1.91-1.3 2.75-1.03 2.75-1.03.55 1.38.2 2.4.1 2.65.64.7 1.03 1.6 1.03 2.69 0 3.84-2.34 4.69-4.57 4.94.36.31.68.92.68 1.85v2.75c0 .27.18.58.69.48A10 10 0 0 0 12 2Z',
  tag: 'M20 13 13 20a2 2 0 0 1-2.83 0L2 11.83V2h9.83L20 10.17A2 2 0 0 1 20 13ZM7 7h.01'
};
function sourceIcon(host, kind, label, href) {
  const node = href ? link(host, '', href, true) : element(host, 'span');
  node.className = 'vex-source-icon';
  node.title = label;
  node.setAttribute('aria-label', label + (href ? ' (opens in a new tab)' : ''));
  if (!href) { node.setAttribute('role', 'img'); node.setAttribute('aria-disabled', 'true'); }
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS(svg.namespaceURI, 'path');
  path.setAttribute('d', sourceIcons[kind]);
  if (kind === 'tag') { svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '1.8'); svg.setAttribute('stroke-linecap', 'round'); }
  else svg.setAttribute('fill', 'currentColor');
  svg.appendChild(path); node.appendChild(svg);
}
async function sourceLinks(host, record) {
  const actions = element(host, 'span', undefined, 'vex-source-links');
  const draw = (source, unavailable = false) => {
    actions.replaceChildren();
    for (const [kind, name] of [['repository', 'Patched GitHub repository'], ['tag', 'Source at release tag']]) {
      const label = `${name} for ${record.library} ${record.version}`;
      sourceIcon(actions, kind, source ? label : `${label} — ${unavailable ? 'unavailable' : 'loading'}`, source?.[kind]);
    }
  };
  draw();
  try {
    sourceIndexRequest ||= fetch(ARTIFACTS_URL, { cache: 'no-cache', signal: AbortSignal.timeout(30000) })
      .then(response => { if (!response.ok) throw new Error('Source manifest unavailable'); return response.json(); })
      .then(artifactSourceIndex);
    const source = (await sourceIndexRequest).get(JSON.stringify([record.purl, record.supplier]));
    draw(source, !source);
  } catch { draw(null, true); }
}

function evidence(row, records) {
  const details = element(row, 'details', undefined, 'vex-original');
  element(details, 'summary', records.length === 1 ? 'Inspect original statement' : `Inspect ${records.length} original statements`);
  details.addEventListener('toggle', () => {
    if (!details.open || details.dataset.loaded) return;
    details.dataset.loaded = 'true';
    const actions = element(details, 'div', undefined, 'feed-actions');
    link(actions, 'OpenVEX source', VEX_URL, true); link(actions, 'CycloneDX source', CDX_URL, true);
    const copy = button(actions, 'Copy package URL (PURL)', async () => { try { await navigator.clipboard.writeText(records[0].purl); copy.textContent = 'Copied'; } catch { copy.textContent = 'Select the package URL above to copy'; } }, 'feed-retry');
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
  if (all) releaseScope().value = 'all';
  page = 0; render(); $('query').focus();
  $('active-filters').scrollIntoView({ block: 'center' });
}
function render() {
  disclosures = [];
  // Select latest versions before searching; an old matching CVE must never redefine "latest".
  const scoped = releaseScope().value === 'all' ? entries : latestReleases(entries);
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
  const size = pageLength(items.length);
  const pages = Math.max(1, Math.ceil(items.length / size)); page = Math.min(page, pages - 1);
  updateUrl(); activeFilters();
  $('results-status').textContent = `${items.length.toLocaleString()} ${view === 'libraries' ? 'libraries' : view === 'releases' ? 'maintained versions' : 'statements'} match · ${filtered.length.toLocaleString()} product statements`;
  $('page-status').textContent = `Page ${page + 1} of ${pages}`;
  $('previous').disabled = page === 0; $('next').disabled = page === pages - 1;
  const host = $('results'); host.replaceChildren();
  if (!items.length) element(host, 'p', 'No published VEX statements match this search. Try all releases, another search, or clear the active filters.', 'vex-empty');
  for (const item of items.slice(page * size, (page + 1) * size)) {
    const row = element(host, 'article', undefined, 'vex-record'); const summary = element(row, 'div');
    element(summary, 'h2', item.library);
    if (view === 'libraries') {
      const releases = groupReleases(item.entries);
      element(summary, 'p', `${item.ecosystem} · ${releases.length} maintained version${releases.length === 1 ? '' : 's'}`, 'vex-meta');
      const versionRow = element(summary, 'div', undefined, 'vex-version-row');
      for (const release of releases.slice(0, 4)) {
        const chip = element(versionRow, 'div', undefined, 'vex-version-chip');
        const heading = element(chip, 'div', undefined, 'vex-release-heading');
        element(heading, 'strong', `${release.version} (producer: ${release.supplier})`);
        sourceLinks(heading, release);
        advisories(chip, release.entries);
      }
      if (releases.length > 4) element(summary, 'p', `Plus ${releases.length - 4} more maintained versions.`, 'feed-note');
      const actions = element(row, 'div', undefined, 'vex-row-actions');
      button(actions, 'Inspect versions →', () => drill(item, 'releases'));
      const all = entries.filter(x => x.library === item.library && x.ecosystem === item.ecosystem && (!$('supplier').value || x.supplier === $('supplier').value));
      const selected = new Set(scoped.map(releaseIdentity));
      const older = new Set(all.filter(x => !selected.has(releaseIdentity(x))).map(releaseIdentity)).size;
      if (older) button(actions, `See ${older} other maintained version${older === 1 ? '' : 's'}`, () => drill(item, 'releases', true));
    } else {
      const heading = element(summary, 'div', undefined, 'vex-release-heading');
      element(heading, 'h3', `${item.version} (producer: ${item.supplier})`);
      sourceLinks(heading, item);
      element(summary, 'p', item.purl, 'vex-coordinate');
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
  const all = element(select, 'option', id === 'supplier' ? 'All producers' : 'All ecosystems'); all.value = '';
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
const pageSize = document.getElementById('page-size');
if (pageSize) pageSize.addEventListener('change', () => { page = 0; render(); });
for (const [id, offset] of [['previous', -1], ['next', 1]]) $(id).addEventListener('click', () => { page += offset; render(); $('results-status').scrollIntoView({ block: 'center' }); });
window.addEventListener('popstate', () => { readUrl(); render(); }); $('retry').addEventListener('click', refresh); refresh();
