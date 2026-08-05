/* Archive Watch viewer — service worker.
   Shell: stale-while-revalidate (instant offline open, self-healing). Data
   (catalog index, featured): network-first with cache fallback, so the catalog
   stays fresh online and the app still opens with the last-good copy offline.
   Video is NEVER cached.

   The shell was previously cache-first with NO revalidation, which had two
   failure modes: a tab left open for days never picked up a new build, and —
   worse — a deploy that changed watch.js WITHOUT bumping SHELL froze every
   existing install permanently, because nothing ever re-fetched the asset.
   Serving from cache while refreshing in the background keeps the instant open
   and makes the next load correct without depending on a version bump. */
const SHELL = 'aw-root-shell-v27';
const DATA = 'aw-root-data-v1';
const SHELL_URLS = [
  './', 'index.html', 'watch.css', 'watch.js', 'tv.css', 'tv.js', 'cast-sender.js',
  'manifest.json', 'js/api.js',
  'assets/app-icon/app-icon.png',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(SHELL).then(c => c.addAll(SHELL_URLS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) {
      if (k !== SHELL && k !== DATA) await caches.delete(k);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  if (url.hostname.includes('archive.org')) return;   // media/API straight through
  if (url.pathname.startsWith('/curate')) return;     // the editorial tool stays live

  const isData = url.pathname.endsWith('catalog-index.json')
    || url.pathname.endsWith('featured.json')
    || url.pathname.endsWith('channel-pools.json')
    || url.pathname.includes('/details/')
    || url.pathname.includes('/series/');

  if (isData) {
    e.respondWith((async () => {
      try {
        const fresh = await fetch(e.request);
        const cache = await caches.open(DATA);
        cache.put(e.request, fresh.clone());
        return fresh;
      } catch {
        const hit = await caches.match(e.request);
        if (hit) return hit;
        throw new Error('offline, no cached copy');
      }
    })());
    return;
  }

  // Shell: stale-while-revalidate. Answer from cache instantly when we have it,
  // and refresh that entry in the background so the NEXT load is current even if
  // SHELL wasn't bumped. e.waitUntil keeps the background fetch alive after the
  // response is returned.
  e.respondWith((async () => {
    const cache = await caches.open(SHELL);
    const hit = await cache.match(e.request, { ignoreSearch: true });
    const revalidate = fetch(e.request).then(res => {
      if (res && res.ok && res.type === 'basic') cache.put(e.request, res.clone());
      return res;
    }).catch(() => null);
    if (hit) {
      e.waitUntil(revalidate);
      return hit;
    }
    return (await revalidate) || fetch(e.request);
  })());
});
