/**
 * Archive Watch — web viewer.
 *
 * Data plane (docs/CATALOG-CONTRACT.md): catalog-index.json (GitHub Pages,
 * CORS) for browse/search; featured.json for shelves; the Archive metadata API
 * (CORS) resolves detail + the playable derivative at view time via js/api.js;
 * posters come from the index's designed-art URL or archive.org/services/img.
 * <video>/<img> elements don't need CORS, so playback + art are unrestricted.
 *
 * State is URL-driven (hash routes, shareable). Favorites + watch progress live
 * in IndexedDB on this browser — no account, no backend (Decision 028 §6).
 */
(() => {
  'use strict';

  const PAGES_ROOT = new URL('..', location.href);            // .../Archive-Watch/
  const INDEX_URL = new URL('catalog-index.json', PAGES_ROOT);
  const FEATURED_URL = new URL('featured.json', PAGES_ROOT);
  const PAGE_SIZE = 60;

  /* ---------------------------------------------------------------- *
   * Tiny IndexedDB store: favorites + watch progress (offline-first)  *
   * ---------------------------------------------------------------- */
  const DB = (() => {
    let dbp = null;
    function open() {
      dbp ??= new Promise((res, rej) => {
        const req = indexedDB.open('archivewatch', 1);
        req.onupgradeneeded = () => {
          req.result.createObjectStore('favorites', { keyPath: 'id' });
          req.result.createObjectStore('progress', { keyPath: 'id' });
        };
        req.onsuccess = () => res(req.result);
        req.onerror = () => rej(req.error);
      });
      return dbp;
    }
    async function tx(store, mode, fn) {
      const db = await open();
      return new Promise((res, rej) => {
        const t = db.transaction(store, mode);
        const out = fn(t.objectStore(store));
        t.oncomplete = () => res(out?.result ?? out);
        t.onerror = () => rej(t.error);
      });
    }
    async function getAll(store) {
      const db = await open();
      return new Promise((res, rej) => {
        const r = db.transaction(store).objectStore(store).getAll();
        r.onsuccess = () => res(r.result || []);
        r.onerror = () => rej(r.error);
      });
    }
    return {
      favorites: () => getAll('favorites'),
      isFavorite: async id => (await getAll('favorites')).some(f => f.id === id),
      toggleFavorite: async id => {
        const has = await DB.isFavorite(id);
        await tx('favorites', 'readwrite',
          s => has ? s.delete(id) : s.put({ id, addedAt: Date.now() }));
        return !has;
      },
      progress: () => getAll('progress'),
      progressFor: async id => (await getAll('progress')).find(p => p.id === id) || null,
      saveProgress: (id, position, duration) =>
        tx('progress', 'readwrite',
          s => s.put({ id, position, duration, at: Date.now() })),
    };
  })();

  /* ---------------------------------------------------------------- *
   * Catalog data                                                      *
   * ---------------------------------------------------------------- */
  const Data = {
    rows: [],            // [id, title, year, type, poster?] popularity-sorted
    byID: new Map(),
    featured: null,

    async load() {
      const [idxR, featR] = await Promise.all([
        fetch(INDEX_URL), fetch(FEATURED_URL),
      ]);
      if (!idxR.ok) throw new Error(`catalog index ${idxR.status}`);
      const idx = await idxR.json();
      this.rows = idx.items || [];
      this.rows.forEach(r => this.byID.set(r[0], r));
      if (featR.ok) this.featured = await featR.json();
    },

    poster(row) {
      return (row && row[4]) || API.thumbnailURL(row ? row[0] : '');
    },

    /** Resolve a featured.json shelf to index rows (curated) or a scrape
        (dynamic, cached for an hour so Home isn't N requests every visit). */
    async shelfRows(shelf, limit = 16) {
      if (shelf.type === 'curated' && Array.isArray(shelf.items)) {
        return shelf.items.map(i => this.byID.get(i.archiveID)).filter(Boolean).slice(0, limit);
      }
      if (!shelf.query) return [];
      const key = `aw_shelf_${shelf.id}`;
      try {
        const hit = JSON.parse(sessionStorage.getItem(key) || 'null');
        if (hit && Date.now() - hit.at < 3600e3) return hit.rows;
      } catch { /* re-fetch */ }
      const { items } = await API.scrape({
        q: shelf.query, sorts: shelf.sort || [], count: limit * 2 });
      const rows = items
        .map(it => this.byID.get(it.identifier)
          || [it.identifier, it.title || it.identifier,
              parseInt(String(it.year || it.date || '').slice(0, 4), 10) || null, '', null])
        .slice(0, limit);
      try { sessionStorage.setItem(key, JSON.stringify({ at: Date.now(), rows })); } catch { /* full */ }
      return rows;
    },
  };

  /* ---------------------------------------------------------------- *
   * Rendering helpers                                                 *
   * ---------------------------------------------------------------- */
  const $ = id => document.getElementById(id);

  function card(row) {
    const [id, title, year] = row;
    const a = document.createElement('a');
    a.className = 'card';
    a.href = `#/item/${encodeURIComponent(id)}`;
    const img = document.createElement('img');
    img.loading = 'lazy';
    img.alt = '';
    img.src = Data.poster(row);
    img.onerror = () => { img.onerror = null; img.src = API.thumbnailURL(id); };
    const t = document.createElement('span'); t.className = 't'; t.textContent = title;
    const y = document.createElement('span'); y.className = 'y';
    y.textContent = year ? String(year) : '';
    a.append(img, t, y);
    return a;
  }

  function fillGrid(el, rows) {
    el.replaceChildren(...rows.map(card));
  }

  function stripHTML(s) {
    const d = document.createElement('div');
    d.innerHTML = s || '';
    return (d.textContent || '').trim();
  }

  /* ---------------------------------------------------------------- *
   * Router — URL-driven state (the web superpower)                    *
   * ---------------------------------------------------------------- */
  const VIEWS = ['home', 'browse', 'search', 'library', 'item', 'about'];
  let browseObserver = null;   // disconnected on every view switch

  function route() {
    const hash = location.hash.replace(/^#\/?/, '');
    const [path, queryStr] = hash.split('?');
    const q = new URLSearchParams(queryStr || '');
    const seg = path.split('/').filter(Boolean);

    if (browseObserver) { browseObserver.disconnect(); browseObserver = null; }

    let name = seg[0] || 'home';
    if (!VIEWS.includes(name)) name = 'home';
    showView(name);

    if (name === 'home') Home.render();
    if (name === 'browse') Browse.render(q);
    if (name === 'search') Search.render(q);
    if (name === 'library') Library.render();
    if (name === 'item') Item.render(decodeURIComponent(seg[1] || ''));
  }

  function showView(name) {
    VIEWS.forEach(v => { $(`view-${v}`).hidden = v !== name; });
    document.querySelectorAll('.topnav a').forEach(a => {
      a.setAttribute('aria-current',
        String(a.dataset.nav === (name === 'item' ? '' : name)));
    });
    $('main').scrollTop = 0;
  }

  /* ---------------------------------------------------------------- *
   * Home                                                              *
   * ---------------------------------------------------------------- */
  const Home = {
    heroTimer: null,
    rendered: false,

    async render() {
      if (this.rendered) return;
      this.rendered = true;
      this.hero();
      const host = $('home-shelves');
      const shelves = (Data.featured?.shelves || []).slice(0, 14);
      for (const shelf of shelves) {
        try {
          const rows = await Data.shelfRows(shelf);
          if (rows.length < 4) continue;
          const sec = document.createElement('section');
          sec.className = 'shelf';
          const h = document.createElement('h2');
          h.textContent = shelf.title;
          const rail = document.createElement('div');
          rail.className = 'shelf-row';
          rail.append(...rows.map(card));
          sec.append(h, rail);
          host.append(sec);
        } catch { /* a failed dynamic shelf just doesn't render */ }
      }
      if (!host.children.length) {
        const p = document.createElement('p');
        p.className = 'muted';
        p.textContent = 'Shelves are unavailable right now — try Browse.';
        host.append(p);
      }
    },

    hero() {
      const pool = Data.rows.filter(r => r[4]).slice(0, 24);
      if (!pool.length) return;
      const el = $('hero');
      el.hidden = false;
      let i = Math.floor(Math.random() * pool.length);
      const show = () => {
        const row = pool[i % pool.length];
        $('hero-img').src = Data.poster(row);
        $('hero-title').textContent = row[1];
        $('hero-meta').textContent = row[2] ? String(row[2]) : '';
        el.onclick = () => { location.hash = `#/item/${encodeURIComponent(row[0])}`; };
      };
      show();
      clearInterval(this.heroTimer);
      this.heroTimer = setInterval(() => { i += 1; show(); }, 7000);
    },
  };

  /* ---------------------------------------------------------------- *
   * Browse — filters live in the URL (#/browse?type=…&decade=…)       *
   * ---------------------------------------------------------------- */
  const TYPES = [
    ['', 'All'], ['feature-film', 'Films'], ['tv-series', 'TV'],
    ['silent-film', 'Silent'], ['animation', 'Animation'],
    ['short-film', 'Shorts'], ['newsreel', 'Newsreels'],
    ['documentary', 'Documentary'], ['ephemeral', 'Ephemera'],
    ['commercial', 'Commercials'],
  ];

  const Browse = {
    filtered: [],
    shown: 0,

    render(q) {
      const type = q.get('type') || '';
      const decade = q.get('decade') || '';
      const sort = q.get('sort') || 'pop';
      this.controls(type, decade, sort);

      this.filtered = Data.rows.filter(r =>
        (!type || r[3] === type) &&
        (!decade || (r[2] && Math.floor(r[2] / 10) * 10 === Number(decade))));
      if (sort === 'az') this.filtered = [...this.filtered].sort((a, b) => a[1].localeCompare(b[1]));
      if (sort === 'new') this.filtered = [...this.filtered].sort((a, b) => (b[2] || 0) - (a[2] || 0));
      if (sort === 'old') this.filtered = [...this.filtered].sort((a, b) => (a[2] || 9999) - (b[2] || 9999));

      $('browse-count').textContent = `${this.filtered.length.toLocaleString()} titles`;
      this.shown = 0;
      $('browse-grid').replaceChildren();
      this.more();

      browseObserver = new IntersectionObserver(es => {
        if (es.some(e => e.isIntersecting)) this.more();
      });
      browseObserver.observe($('browse-sentinel'));
    },

    more() {
      const next = this.filtered.slice(this.shown, this.shown + PAGE_SIZE);
      this.shown += next.length;
      $('browse-grid').append(...next.map(card));
    },

    setParam(k, v) {
      const q = new URLSearchParams((location.hash.split('?')[1]) || '');
      if (v) q.set(k, v); else q.delete(k);
      location.hash = `#/browse?${q.toString()}`;
    },

    controls(type, decade, sort) {
      const chips = $('browse-type-chips');
      chips.replaceChildren(...TYPES.map(([val, label]) => {
        const b = document.createElement('button');
        b.textContent = label;
        b.setAttribute('aria-pressed', String(val === type));
        b.onclick = () => this.setParam('type', val);
        return b;
      }));

      const decades = [...new Set(Data.rows.map(r => r[2] && Math.floor(r[2] / 10) * 10)
        .filter(d => d && d >= 1890 && d <= 2020))].sort();
      const sel = $('browse-decade');
      sel.replaceChildren(new Option('All decades', ''),
        ...decades.map(d => new Option(`${d}s`, String(d))));
      sel.value = decade;
      sel.onchange = () => this.setParam('decade', sel.value);

      $('browse-sort').value = sort;
      $('browse-sort').onchange = () => this.setParam('sort', $('browse-sort').value);
    },
  };

  /* ---------------------------------------------------------------- *
   * Search — client-side over the popularity-sorted index             *
   * ---------------------------------------------------------------- */
  const Search = {
    wired: false,
    render(q) {
      const input = $('search-input');
      if (!this.wired) {
        this.wired = true;
        let t = null;
        input.addEventListener('input', () => {
          clearTimeout(t);
          t = setTimeout(() => {
            const qs = input.value.trim();
            history.replaceState(null, '',
              qs ? `#/search?q=${encodeURIComponent(qs)}` : '#/search');
            this.run(qs);
          }, 180);
        });
      }
      const initial = q.get('q') || '';
      input.value = initial;
      this.run(initial);
    },
    run(qs) {
      const grid = $('search-grid');
      if (!qs) { grid.replaceChildren(); $('search-hint').hidden = false; return; }
      $('search-hint').hidden = true;
      const terms = qs.toLowerCase().split(/\s+/).filter(Boolean);
      const hits = [];
      for (const r of Data.rows) {
        const hay = r[1].toLowerCase();
        if (terms.every(t => hay.includes(t))) {
          hits.push(r);
          if (hits.length >= 200) break;
        }
      }
      fillGrid(grid, hits);
      if (!hits.length) {
        const p = document.createElement('p');
        p.className = 'muted';
        p.textContent = `Nothing matches “${qs}”.`;
        grid.append(p);
      }
    },
  };

  /* ---------------------------------------------------------------- *
   * Library — favorites + continue watching (IndexedDB, this browser) *
   * ---------------------------------------------------------------- */
  const Library = {
    async render() {
      const progress = (await DB.progress())
        .filter(p => p.duration > 0 && p.position > 10 && p.position / p.duration < 0.95)
        .sort((a, b) => b.at - a.at);
      const cont = progress.map(p => Data.byID.get(p.id)).filter(Boolean);
      fillGrid($('library-continue'), cont);
      $('library-continue-empty').hidden = cont.length > 0;

      const favs = (await DB.favorites()).sort((a, b) => b.addedAt - a.addedAt)
        .map(f => Data.byID.get(f.id)).filter(Boolean);
      fillGrid($('library-favs'), favs);
      $('library-favs-empty').hidden = favs.length > 0;
    },
  };

  /* ---------------------------------------------------------------- *
   * Detail + player                                                   *
   * ---------------------------------------------------------------- */
  const Item = {
    current: null,

    async render(id) {
      if (!id) { location.hash = '#/'; return; }
      const row = Data.byID.get(id) || [id, id, null, '', null];
      this.current = { id, row, summary: null };

      $('item-title').textContent = row[1];
      $('item-meta').textContent = [row[2], row[3].replace(/-/g, ' ')]
        .filter(Boolean).join(' · ');
      $('item-poster').src = Data.poster(row);
      $('item-poster').onerror = () => { $('item-poster').src = API.thumbnailURL(id); };
      $('item-desc').textContent = '';
      $('item-error').hidden = true;
      $('item-play').disabled = true;
      $('item-archive-link').href = API.detailsURL(id);

      const fav = await DB.isFavorite(id);
      this.favUI(fav);
      $('item-fav').onclick = async () => this.favUI(await DB.toggleFavorite(id));
      $('item-share').onclick = () => this.share(row);
      $('item-play').onclick = () => Player.play(this.current);

      try {
        const meta = await API.fetchMetadata(id);
        const s = API.summarize(meta);
        if (this.current.id !== id) return;   // user navigated away mid-fetch
        this.current.summary = s;
        $('item-desc').textContent = stripHTML(s.description).slice(0, 1200);
        if (s.year && !row[2]) {
          $('item-meta').textContent = [s.year, row[3].replace(/-/g, ' ')]
            .filter(Boolean).join(' · ');
        }
        if (s.videoFile) {
          $('item-play').disabled = false;
        } else {
          this.fail('No playable video file on this item.');
        }
      } catch (err) {
        this.fail(`Couldn't reach archive.org for this title (${err.message}). ` +
                  'Playback and synopsis are unavailable right now.');
      }
    },

    favUI(on) {
      const b = $('item-fav');
      b.setAttribute('aria-pressed', String(on));
      b.textContent = on ? '♥ Favorited' : '♡ Favorite';
    },

    fail(msg) {
      const e = $('item-error');
      e.textContent = msg;
      e.hidden = false;
    },

    async share(row) {
      const url = `${PAGES_ROOT}item/${encodeURIComponent(row[0])}`;
      const data = { title: row[1], url };
      try {
        if (navigator.share) { await navigator.share(data); return; }
      } catch { /* fall through to clipboard */ }
      try {
        await navigator.clipboard.writeText(url);
        $('item-share').textContent = 'Link copied ✓';
        setTimeout(() => { $('item-share').textContent = 'Share'; }, 1600);
      } catch { /* no clipboard either; the archive link remains */ }
    },
  };

  /** <video> with a reconnect wrapper: archive.org idle-resets drop the
      connection mid-film; on error/stall we reload the src and re-seek to
      where we were (the browser's ranged GETs make this seamless) — the web
      analog of the tvOS ResilientStreamLoader (Decision 021). */
  const Player = {
    saveTimer: null,
    stallTimer: null,
    ctx: null,

    async play(ctx) {
      const { id, row, summary } = ctx;
      if (!summary?.videoFile) return;
      this.ctx = ctx;
      const video = $('video');
      const url = `https://archive.org/download/${encodeURIComponent(id)}/` +
        encodeURIComponent(summary.videoFile.name).replace(/%2F/g, '/');

      $('player-title').textContent = row[1];
      $('player-error').hidden = true;
      video.src = url;

      const saved = await DB.progressFor(id);
      if (saved && saved.position > 10 && (!saved.duration ||
          saved.position / saved.duration < 0.95)) {
        video.currentTime = saved.position;
      }

      $('player').showModal();
      try { await video.play(); } catch { /* user gesture rules; controls remain */ }

      clearInterval(this.saveTimer);
      this.saveTimer = setInterval(() => this.persist(), 10000);

      video.onerror = () => this.recover('error');
      video.onwaiting = () => {
        clearTimeout(this.stallTimer);
        this.stallTimer = setTimeout(() => this.recover('stall'), 12000);
      };
      video.onplaying = () => clearTimeout(this.stallTimer);
      video.onended = () => { this.persist(); this.close(); };
    },

    recover(kind) {
      const video = $('video');
      if (!this.ctx || !video.src) return;
      const t = video.currentTime || 0;
      this.persist();
      const src = video.src;
      video.src = '';
      video.src = src;
      video.currentTime = t;
      video.play().catch(() => {
        const e = $('player-error');
        e.textContent = `Playback ${kind === 'stall' ? 'stalled' : 'failed'} — ` +
          'tap play to retry, or try again in a moment.';
        e.hidden = false;
      });
    },

    persist() {
      const video = $('video');
      if (!this.ctx || !video.duration || !isFinite(video.duration)) return;
      DB.saveProgress(this.ctx.id, video.currentTime, video.duration);
    },

    close() {
      const video = $('video');
      this.persist();
      clearInterval(this.saveTimer);
      clearTimeout(this.stallTimer);
      video.pause();
      video.removeAttribute('src');
      video.load();
      $('player').close();
    },
  };

  /* ---------------------------------------------------------------- *
   * Boot                                                              *
   * ---------------------------------------------------------------- */
  async function boot() {
    $('player-close').onclick = () => Player.close();
    $('player').addEventListener('cancel', e => { e.preventDefault(); Player.close(); });

    try {
      await Data.load();
    } catch (err) {
      $('boot').hidden = true;
      const e = $('apperror');
      e.textContent = `The catalog index couldn't load (${err.message}). ` +
        'Check your connection and reload.';
      e.hidden = false;
      return;
    }
    $('boot').hidden = true;
    window.addEventListener('hashchange', route);
    route();

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('sw.js').catch(() => { /* http or old browser */ });
    }
  }

  boot();
})();
