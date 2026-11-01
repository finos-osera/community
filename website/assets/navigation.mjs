const nav = document.querySelector('header nav');
const toggle = nav?.querySelector('.nav-toggle');
const links = nav?.querySelector('.navlinks');
if (toggle && links) {
  const narrow = matchMedia('(max-width: 1200px)');
  const setOpen = open => {
    links.classList.toggle('is-open', open);
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Close navigation menu' : 'Open navigation menu');
  };
  links.classList.add('nav-collapsible');
  toggle.hidden = false;
  setOpen(false);
  toggle.addEventListener('click', () => setOpen(toggle.getAttribute('aria-expanded') !== 'true'));
  links.addEventListener('click', event => { if (event.target.closest('a')) setOpen(false); });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') {
      setOpen(false);
      toggle.focus();
    }
  });
  document.addEventListener('click', event => { if (!nav.contains(event.target)) setOpen(false); });
  narrow.addEventListener('change', () => setOpen(false));
}
