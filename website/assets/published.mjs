import { METRICS_URL, VEX_URL, normalizeVex, vexSearchIndex, validateMetrics, loadFeed, freshness, searchSuggestions, navigatorHref } from './feed-data.mjs';

let searchIndex = [];
let searchBound = false;

function setStatus(text) {
  const status = document.querySelector('[data-feed-status]');
  if (status) status.textContent = text;
}

function renderEcosystems(names) {
  const text = document.querySelector('[data-ecosystems]');
  if (text) text.textContent = names.join(' · ') || 'No ecosystems published';
  const chips = document.querySelector('[data-ecosystem-chips]');
  if (!chips) return;
  chips.replaceChildren();
  if (!names.length) {
    chips.textContent = 'No ecosystems published yet';
    return;
  }
  for (const name of names) {
    const link = document.createElement('a');
    link.className = 'eco-chip';
    link.href = navigatorHref({ ecosystem: name });
    link.textContent = name;
    chips.appendChild(link);
  }
}

function fill(data, cached) {
  for (const element of document.querySelectorAll('[data-metric]')) {
    const value = data.totals?.[element.dataset.metric];
    if (Number.isSafeInteger(value)) element.textContent = value.toLocaleString();
  }
  renderEcosystems(Array.isArray(data.ecosystems) ? data.ecosystems : []);
  const status = document.querySelector('[data-feed-status]');
  if (status) status.textContent = freshness(data.as_of, cached) + (status.dataset.feedNote ? ' ' + status.dataset.feedNote : '');
  const block = document.querySelector('[data-metrics]');
  if (block) block.hidden = false;
  const retry = document.querySelector('[data-retry]');
  if (retry) retry.hidden = !cached;
}

function bindSearch() {
  const form = document.getElementById('fix-search');
  if (!form || searchBound) return;
  searchBound = true;
  const input = form.querySelector('input[name="q"]');
  const list = document.getElementById('fix-suggestions');
  const empty = document.getElementById('fix-empty');
  const go = query => { location.href = navigatorHref({ q: query, releases: 'all' }); };
  const matchesFor = query => searchSuggestions(searchIndex, query, 10);
  form.addEventListener('submit', event => {
    event.preventDefault();
    const query = input.value.trim();
    if (!query) { input.focus(); return; }
    // Suggestions are a partial index, not proof that remediation is absent.
    go(query);
  });
  if (!input || !list) return;
  const show = items => {
    list.replaceChildren();
    list.hidden = items.length === 0;
    input.setAttribute('aria-expanded', items.length ? 'true' : 'false');
    for (const item of items) {
      const li = document.createElement('li');
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = item.detail ? `${item.label} · ${item.detail}` : item.label;
      button.addEventListener('click', () => go(item.q));
      li.appendChild(button);
      list.appendChild(li);
    }
  };
  let loading = false, loaded = false;
  const loadSuggestions = async () => {
    if (loaded || loading) return;
    loading = true;
    if (empty) { empty.hidden = false; empty.textContent = 'Loading suggestions from published VEX statements…'; }
    try {
      const { data, cached } = await loadFeed(VEX_URL, normalizeVex);
      searchIndex = vexSearchIndex(data.entries);
      loaded = true;
      if (empty) { empty.hidden = false; empty.textContent = 'Suggestions from OpenVEX · ' + freshness(data.published, cached); }
      show(matchesFor(input.value.trim()));
    } catch {
      if (empty) { empty.hidden = false; empty.textContent = 'Suggestions are unavailable. You can still search the published VEX statements.'; }
    } finally { loading = false; }
  };
  input.addEventListener('focus', loadSuggestions);
  input.addEventListener('input', () => { loadSuggestions(); show(matchesFor(input.value.trim())); });
  input.addEventListener('keydown', event => { if (event.key === 'Escape') show([]); });
}

async function refresh() {
  const retry = document.querySelector('[data-retry]');
  if (retry) retry.hidden = true;
  setStatus('Loading published metrics…');
  try {
    const { data, cached } = await loadFeed(METRICS_URL, validateMetrics);
    fill(data, cached);
  } catch {
    setStatus('Published metrics are temporarily unavailable. Search still opens the navigator.');
    if (retry) retry.hidden = false;
    const chips = document.querySelector('[data-ecosystem-chips]');
    if (chips && !chips.childElementCount) chips.textContent = 'Ecosystems will appear when the feed is available.';
  }
}

const retry = document.querySelector('[data-retry]');
if (retry) retry.addEventListener('click', refresh);
bindSearch();
if (document.querySelector('[data-metric], [data-ecosystem-chips], [data-feed-status], #published')) refresh();
