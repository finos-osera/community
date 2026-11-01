import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { navigatorHref, searchSuggestions } from '../assets/feed-data.mjs';

test('homepage submits exact queries without depending on a partial or unavailable suggestions feed', async () => {
  const handlers = {};
  const input = { value: '', addEventListener() {}, focus() {} };
  const form = { querySelector: () => input, addEventListener: (name, handler) => { handlers[name] = handler; } };
  const location = { href: '' };
  const document = { getElementById: id => id === 'fix-search' ? form : null, querySelector: () => null };
  const source = (await readFile(new URL('../assets/published.mjs', import.meta.url), 'utf8')).replace(/^import .*;\n/, '');
  vm.runInNewContext(source, { document, location, navigatorHref, searchSuggestions });
  for (const query of ['CVE-2025-66566', 'GHSA-cmp6-m4wj-q63q', 'at.yawk.lz4:lz4-java']) {
    input.value = query;
    handlers.submit({ preventDefault() {} });
    assert.equal(location.href, navigatorHref({ q: query, releases: 'all' }));
  }
});
