import test from 'node:test';
import assert from 'node:assert/strict';
import { memberView } from '../assets/members.mjs';

test('counts the official roster including members without logos', () => {
  const view = memberView([
    { Name: 'Citi', Logo: 'https://example.test/citi.png', Membership: { Name: 'Premier Member' } },
    { Name: 'No Logo Bank' },
  ]);
  assert.equal(view.count, 2);
  assert.equal(view.withLogo.length, 1);
  assert.equal(view.withoutLogo.length, 1);
  assert.equal(view.withLogo[0].Name, 'Citi');
});

test('empty or unusable rosters do not invent members', () => {
  assert.equal(memberView(null).count, 0);
  assert.deepEqual(memberView([]), { count: 0, withLogo: [], withoutLogo: [] });
  assert.equal(memberView([{ Logo: 'https://example.test/x.png' }]).withLogo.length, 0);
});
