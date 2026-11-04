// Collapsible nav search: a lens button that expands into a package/CVE search
// with the same live VEX suggestions as the homepage catalog search.
import { VEX_URL, normalizeVex, vexSearchIndex, searchSuggestions, navigatorHref, loadFeed } from './feed-data.mjs';

function mount() {
  const form = document.querySelector('form[data-nav-search]');
  if (!form) return;
  const btn = form.querySelector('.nav-search-btn');
  const input = form.querySelector('input[name="q"]');
  const list = form.querySelector('.nav-suggest');
  if (!input || !list) return;
  let index = [];
  let loaded = false;
  let loading = false;
  const go = query => { location.href = navigatorHref({ q: query, releases: 'all' }); };
  const show = items => {
    list.replaceChildren();
    list.hidden = items.length === 0;
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
  const matches = () => searchSuggestions(index, input.value.trim(), 10);
  const loadSuggestions = async () => {
    if (loaded || loading) return;
    loading = true;
    try {
      const { data } = await loadFeed(VEX_URL, normalizeVex);
      index = vexSearchIndex(data.entries);
      loaded = true;
      show(matches());
    } catch {
      // Suggestions are optional; plain submit still works.
    } finally { loading = false; }
  };
  const open = () => {
    form.classList.add('open');
    if (btn) btn.setAttribute('aria-expanded', 'true');
    input.focus();
    loadSuggestions();
  };
  const close = () => {
    form.classList.remove('open');
    if (btn) btn.setAttribute('aria-expanded', 'false');
    show([]);
  };
  if (btn) btn.addEventListener('click', () => form.classList.contains('open') ? close() : open());
  input.addEventListener('focus', loadSuggestions);
  input.addEventListener('input', () => { loadSuggestions(); show(matches()); });
  input.addEventListener('keydown', event => { if (event.key === 'Escape') close(); });
  form.addEventListener('submit', event => {
    event.preventDefault();
    const query = input.value.trim();
    if (!query) { input.focus(); return; }
    go(query);
  });
  document.addEventListener('click', event => {
    if (!form.contains(event.target)) {
      show([]);
      if (!input.value.trim()) close();
    }
  });
}

if (typeof document !== 'undefined') mount();
