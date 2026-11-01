import test from 'node:test';
import assert from 'node:assert/strict';
import { memberView } from '../assets/members.mjs';

test('confirmed total is independent of the consent-filtered public list', () => {
  const view = memberView([
    { Name: 'Citi', Logo: 'https://example.test/citi.png', Membership: { Name: 'Premier Member' } },
    { Name: 'No Logo Bank' },
  ]);
  assert.equal(view.count, 7);
  assert.equal(view.withLogo.length, 1);
  assert.equal(view.withoutLogo.length, 1);
  assert.equal(view.withLogo[0].Name, 'Citi');
});

test('empty or unusable public lists retain the confirmed total without inventing names', () => {
  assert.equal(memberView(null).count, 7);
  assert.deepEqual(memberView([]), { count: 7, withLogo: [], withoutLogo: [] });
  assert.equal(memberView([{ Logo: 'https://example.test/x.png' }]).withLogo.length, 0);
});
