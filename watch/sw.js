/* Archive Watch viewer — service worker.
   Shell: cache-first (instant offline open). Data (catalog index, featured):
   network-first with cache fallback, so the catalog stays fresh online and the
   app still opens with the last-good copy offline. Video is NEVER cached. */
const SHELL = 'aw-shell-v1';
const DATA = 'aw-data-v1';
const SHELL_URLS = [
  './', 'index.html', 'watch.css', 'watch.js', 'manifest.json', '../js/api.js',
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

  const isData = url.pathname.endsWith('catalog-index.json')
    || url.pathname.endsWith('featured.json');

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

  e.respondWith((async () => {
    const hit = await caches.match(e.request, { ignoreSearch: true });
    return hit || fetch(e.request);
  })());
});
