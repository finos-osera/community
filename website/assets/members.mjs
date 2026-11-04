// Temporary official total confirmed by mindthegab on 2026-11-01.
// The public API is consent-filtered; its length is not total membership.
// Replace this override only when an authoritative total is available.
export const MEMBER_COUNT = 7;
export const MEMBERS_URL = 'https://api-gw.platform.linuxfoundation.org/project-service/v1/public/projects/lfcK5vEVcgon9SNzAg/members?status=Active&orderBy=name';

export function memberView(members) {
  const list = Array.isArray(members) ? members.filter(member => member && typeof member.Name === 'string' && member.Name.trim()) : [];
  const withLogo = [];
  const withoutLogo = [];
  for (const member of list) {
    if (typeof member.Logo === 'string' && member.Logo.trim()) withLogo.push(member);
    else withoutLogo.push(member);
  }
  return { count: MEMBER_COUNT, withLogo, withoutLogo };
}

function websiteUrl(site) {
  if (!site) return '';
  const value = String(site).trim();
  if (!value) return '';
  if (/^https?:\/\//i.test(value)) return value;
  return 'https://' + value.replace(/^\/+/, '');
}

function nameFallback(name) {
  const span = document.createElement('span');
  span.className = 'name';
  span.textContent = name;
  return span;
}

function renderLogos(root, members) {
  const fragment = document.createDocumentFragment();
  for (const member of members) {
    const name = member.Name.trim();
    const href = websiteUrl(member.Website);
    const tile = document.createElement(href ? 'a' : 'div');
    tile.className = 'mtile';
    if (href) {
      tile.href = href;
      tile.target = '_blank';
      tile.rel = 'noopener';
      tile.setAttribute('aria-label', name);
    }
    const membershipName = member.Membership && member.Membership.Name;
    if (membershipName && /general/i.test(membershipName)) tile.className += ' general';
    const img = document.createElement('img');
    img.src = member.Logo;
    img.alt = name;
    img.loading = 'lazy';
    img.addEventListener('error', () => {
      if (img.parentNode) img.parentNode.replaceChild(nameFallback(name), img);
    });
    tile.appendChild(img);
    if (membershipName && !root.hasAttribute('data-hide-tiers')) {
      const tier = document.createElement('span');
      tier.className = 'tier';
      tier.textContent = membershipName;
      tile.appendChild(tier);
    }
    fragment.appendChild(tile);
  }
  root.replaceChildren(fragment);
}

function renderNames(root, members) {
  if (!root) return;
  root.replaceChildren();
  if (!members.length) {
    root.hidden = true;
    return;
  }
  root.hidden = false;
  root.append('Also members: ');
  members.forEach((member, index) => {
    const name = member.Name.trim();
    const href = websiteUrl(member.Website);
    if (href) {
      const link = document.createElement('a');
      link.href = href;
      link.target = '_blank';
      link.rel = 'noopener';
      link.textContent = name;
      root.append(link);
    } else {
      root.append(name);
    }
    root.append(index < members.length - 1 ? ', ' : '.');
  });
}

async function mount() {
  const tiles = document.querySelector('[data-member-tiles]');
  if (!tiles) return;
  try {
    const response = await fetch(MEMBERS_URL);
    if (!response.ok) throw new Error('members ' + response.status);
    const members = await response.json();
    if (!Array.isArray(members)) throw new Error('Invalid member roster');
    const view = memberView(members);
    renderLogos(tiles, view.withLogo);
    renderNames(document.querySelector('[data-member-names]'), view.withoutLogo);
    const status = document.querySelector('[data-member-status]');
    if (status) status.textContent = `${view.count} members · Members include:`;
  } catch {
    const status = document.querySelector('[data-member-status]');
    if (status) status.textContent = `${MEMBER_COUNT} members · Members include those shown below. Live logo list unavailable; showing fallback logos.`;
  }
}

if (typeof document !== 'undefined') mount();
