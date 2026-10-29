import { METRICS_URL, validateMetrics, loadFeed, recentReleases, freshness } from './feed-data.mjs';
const root = document.getElementById('published');
const status = root.querySelector('[data-feed-status]');
const retry = root.querySelector('[data-retry]');
async function refresh() {
  retry.hidden = true;
  status.textContent = 'Loading published metrics…';
  try {
    const { data, cached } = await loadFeed(METRICS_URL, validateMetrics);
    for (const element of root.querySelectorAll('[data-metric]')) element.textContent = data.totals[element.dataset.metric].toLocaleString();
    root.querySelector('[data-ecosystems]').textContent = data.ecosystems.join(' · ') || 'No ecosystems published';
    root.querySelector('[data-activity]').textContent = `${recentReleases(data).toLocaleString()} release sets in the 7 UTC dates ending ${data.as_of.slice(0, 10)}`;
    status.textContent = freshness(data.as_of, cached);
    retry.hidden = !cached;
    root.querySelector('[data-metrics]').hidden = false;
  } catch {
    status.textContent = 'Published metrics are temporarily unavailable. Explore the navigator or view the source feed below.';
    retry.hidden = false;
  }
}
retry.addEventListener('click', refresh);
refresh();
