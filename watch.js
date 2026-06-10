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

  const PAGES_ROOT = new URL('.', location.href);   // the site root (archivewatch.org/)
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
      // title rides along so Continue Watching can render episodes, whose
      // ids aren't rows in the catalog index.
      saveProgress: (id, position, duration, title) =>
        tx('progress', 'readwrite',
          s => s.put({ id, position, duration, title, at: Date.now() })),
    };
  })();

  /* ---------------------------------------------------------------- *
   * Catalog data                                                      *
   * ---------------------------------------------------------------- */
  const Data = {
    rows: [],            // [id, title, year, type, poster?] popularity-sorted
    byID: new Map(),
    shelves: {},         // shelfID → [archiveIDs] (editorial item_shelves analog)
    featured: null,

    async load() {
      const [idxR, featR] = await Promise.all([
        fetch(INDEX_URL), fetch(FEATURED_URL),
      ]);
      if (!idxR.ok) throw new Error(`catalog index ${idxR.status}`);
      const idx = await idxR.json();
      this.rows = idx.items || [];
      this.shelves = idx.shelves || {};
      this.rows.forEach(r => this.byID.set(r[0], r));
      if (featR.ok) this.featured = await featR.json();
    },

    poster(row) {
      return (row && row[4]) || API.thumbnailURL(row ? row[0] : '');
    },

    /** Resolve a featured.json shelf through the index's editorial shelves
        map — the same curated item_shelves assignments the apps query, so
        Home inherits the rights audit + adult filter and every shelf has its
        own identity (live scrape did neither; see WEB-DESIGN §2.3). Shuffled
        fresh per visit, designed artwork leading. */
    shelfRows(shelf, limit = 16) {
      let rows;
      if (shelf.type === 'curated' && Array.isArray(shelf.items)) {
        rows = shelf.items.map(i => this.byID.get(i.archiveID)).filter(Boolean);
      } else {
        rows = (this.shelves[shelf.id] || []).map(id => this.byID.get(id)).filter(Boolean);
      }
      const designed = shuffle(rows.filter(r => r[4]));
      const plain = shuffle(rows.filter(r => !r[4]));
      return designed.concat(plain).slice(0, limit);
    },
  };

  /* ---------------------------------------------------------------- *
   * Detail shards — the catalog's own per-item display fields           *
   * (downloadURL, synopsis, director, cast, genres, runtime, backdrop), *
   * sharded by FNV-1a low byte (keep in sync with build_web_details.py).*
   * ---------------------------------------------------------------- */
  const Details = {
    cache: new Map(),
    shardOf(id) {
      let h = 0x811c9dc5;
      for (const b of new TextEncoder().encode(id)) {
        h ^= b;
        h = Math.imul(h, 0x01000193) >>> 0;
      }
      return (h & 0xff).toString(16).padStart(2, '0');
    },
    async get(id) {
      const shard = this.shardOf(id);
      if (!this.cache.has(shard)) {
        this.cache.set(shard, fetch(new URL(`details/${shard}.json`, PAGES_ROOT),
          { signal: AbortSignal.timeout(10000) })
          .then(r => (r.ok ? r.json() : {}))
          .catch(() => ({})));
      }
      const data = await this.cache.get(shard);
      const rec = data[id];
      if (!rec) return null;
      return {
        downloadURL: rec[0] || null,
        synopsis: rec[1] || null,
        director: rec[2] || null,
        cast: (rec[3] || []).map(c => Array.isArray(c)
          ? { name: c[0], profilePath: c[1] } : { name: c, profilePath: null }),
        genres: rec[4] || null,
        runtimeSeconds: rec[5] || null,
        backdropURL: rec[6] || null,
      };
    },
  };

  /** Where are we? (iPadOS reports as Macintosh — the touch check catches it.) */
  const Platform = {
    iOS: /iPhone|iPad|iPod/.test(navigator.userAgent)
      || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1),
    android: /Android/.test(navigator.userAgent),
  };

  /** Era labels shared with the apps' decade tiles (same vocabulary). */
  function eraLabel(year) {
    if (!year) return '';
    if (year < 1910) return 'Earliest cinema';
    if (year <= 1927) return 'Silent era';
    if (year <= 1939) return 'Pre-code';
    if (year <= 1949) return 'Wartime';
    if (year <= 1959) return 'Atomic age';
    if (year <= 1969) return 'New wave';
    if (year <= 1979) return 'Analog';
    if (year <= 1989) return 'Home video';
    return 'Modern';
  }

  /** Per-visit shuffle (WEB-DESIGN §4.1): every page load deals a fresh hand
      from the pre-screened pools, so Home is never the same twice (owner
      direction 2026-06-10 — deliberately fresher than the apps' daily
      rotation). */
  function shuffle(arr) {
    const a = [...arr];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  /* ---------------------------------------------------------------- *
   * Rendering helpers                                                 *
   * ---------------------------------------------------------------- */
  const $ = id => document.getElementById(id);

  function card(row) {
    const [id, title, year, type] = row;
    const a = document.createElement('a');
    a.className = 'card';
    // TV series cards carry "series:<slug>" ids — they're spines on Pages,
    // not archive.org items, so they get the series surface (the same slug
    // rule as the apps; CATALOG-CONTRACT series section).
    a.href = type === 'tv-series'
      ? `#/series/${encodeURIComponent(id.replace(/^series:/, ''))}`
      : `#/item/${encodeURIComponent(id)}`;
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
  const VIEWS = ['home', 'browse', 'search', 'library', 'item', 'series', 'about'];
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
    if (name === 'series') SeriesView.render(decodeURIComponent(seg[1] || ''));
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

    render() {
      if (this.rendered) return;
      this.rendered = true;
      const heroIDs = this.hero();
      const host = $('home-shelves');
      // Cross-shelf dedup (the apps' Home rule): an item shows once, in the
      // first shelf that claims it, so Home isn't aliases of one popular list.
      const used = new Set(heroIDs);
      for (const shelf of Data.featured?.shelves || []) {
        const rows = Data.shelfRows(shelf, 32)
          .filter(r => r[4] && !used.has(r[0])).slice(0, 16);
        if (rows.length < 4) continue;
        rows.forEach(r => used.add(r[0]));
        const sec = document.createElement('section');
        sec.className = 'shelf';
        const h = document.createElement('h2');
        h.textContent = shelf.title;
        const rail = document.createElement('div');
        rail.className = 'shelf-row';
        rail.append(...rows.map(card));
        sec.append(h, rail);
        host.append(sec);
      }
      if (!host.children.length) {
        const p = document.createElement('p');
        p.className = 'muted';
        p.textContent = 'Shelves are unavailable right now — try Browse.';
        host.append(p);
      }
    },

    /** Marquee hero (WEB-DESIGN §4.1): a native scroll-snap carousel over the
        day-shuffled designed-art pool. Auto-advance pauses on hover/touch and
        hidden tabs, and is off entirely under prefers-reduced-motion. */
    hero() {
      // A wide pre-screened pool (designed art, popularity-ranked) dealt
      // randomly per visit — the hero is different every time.
      const pool = shuffle(Data.rows.filter(r => r[4]).slice(0, 300)).slice(0, 6);
      if (!pool.length) return [];
      const el = $('hero');
      const rail = $('hero-rail');
      const dots = $('hero-dots');
      el.hidden = false;

      rail.replaceChildren(...pool.map((row, i) => {
        const [id, title, year, type] = row;
        const slide = document.createElement('article');
        slide.className = 'hero-slide';
        slide.setAttribute('role', 'group');
        slide.setAttribute('aria-roledescription', 'slide');
        slide.setAttribute('aria-label', `${i + 1} of ${pool.length}: ${title}`);
        slide.onclick = () => { location.hash = `#/item/${encodeURIComponent(id)}`; };

        const ambient = document.createElement('div');
        ambient.className = 'hero-ambient';
        ambient.style.backgroundImage = `url("${Data.poster(row)}")`;

        const poster = document.createElement('img');
        poster.className = 'hero-poster';
        poster.alt = '';
        poster.loading = i === 0 ? 'eager' : 'lazy';
        poster.src = Data.poster(row);
        poster.onerror = () => { poster.onerror = null; poster.src = API.thumbnailURL(id); };

        const copy = document.createElement('div');
        copy.className = 'hero-copy';
        const eyebrow = document.createElement('p');
        eyebrow.className = 'hero-eyebrow';
        eyebrow.textContent = [eraLabel(year), (type || '').replace(/-/g, ' ')]
          .filter(Boolean).join(' · ');
        const h = document.createElement('h2');
        h.className = 'hero-title';
        h.textContent = title;
        const meta = document.createElement('p');
        meta.className = 'hero-meta';
        meta.textContent = year ? String(year) : '';
        const cta = document.createElement('span');
        cta.className = 'hero-cta';
        cta.textContent = 'Details';
        copy.append(eyebrow, h, meta, cta);

        slide.append(ambient, poster, copy);
        return slide;
      }));

      dots.replaceChildren(...pool.map((row, i) => {
        const b = document.createElement('button');
        b.setAttribute('role', 'tab');
        b.setAttribute('aria-label', `Show featured film ${i + 1}: ${row[1]}`);
        b.setAttribute('aria-selected', String(i === 0));
        b.onclick = e => {
          e.stopPropagation();
          rail.scrollTo({ left: i * rail.clientWidth, behavior: 'smooth' });
        };
        return b;
      }));

      const current = () => Math.round(rail.scrollLeft / Math.max(1, rail.clientWidth));
      const sync = () => {
        const c = current();
        [...dots.children].forEach((d, i) => d.setAttribute('aria-selected', String(i === c)));
      };
      rail.addEventListener('scroll', () => requestAnimationFrame(sync), { passive: true });

      // Auto-advance: the one ambient motion moment. Hover/touch pauses it;
      // reduced-motion users never see it (the snap rail stays manual).
      clearInterval(this.heroTimer);
      if (!matchMedia('(prefers-reduced-motion: reduce)').matches) {
        let paused = false;
        el.addEventListener('pointerenter', () => { paused = true; });
        el.addEventListener('pointerleave', () => { paused = false; });
        el.addEventListener('touchstart', () => { paused = true; }, { passive: true });
        this.heroTimer = setInterval(() => {
          if (paused || document.hidden || !el.isConnected) return;
          const next = (current() + 1) % pool.length;
          rail.scrollTo({ left: next * rail.clientWidth, behavior: 'smooth' });
        }, 7000);
      }
      return pool.map(r => r[0]);
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
      // Episodes aren't index rows — synthesize a card from the saved title.
      const cont = progress.map(p => Data.byID.get(p.id)
        || [p.id, p.title || p.id, null, '', null]);
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
      if (id.startsWith('series:')) {   // shared/old links to a series card
        location.replace(`#/series/${encodeURIComponent(id.slice(7))}`);
        return;
      }
      const row = Data.byID.get(id) || [id, id, null, '', null];
      this.current = { id, row, summary: null, detail: null };

      $('item-title').textContent = row[1];
      $('item-meta').textContent = [row[2], row[3].replace(/-/g, ' ')]
        .filter(Boolean).join(' · ');
      $('item-poster').src = Data.poster(row);
      $('item-poster').onerror = () => { $('item-poster').src = API.thumbnailURL(id); };
      $('item-desc').textContent = '';
      $('item-cast').replaceChildren();
      $('item-cast').hidden = true;
      $('item-error').hidden = true;
      $('item-play').disabled = true;

      // Storage can be unavailable (private browsing) — never let it take
      // down the whole detail render.
      const fav = await DB.isFavorite(id).catch(() => false);
      this.favUI(fav);
      $('item-fav').onclick = async () =>
        this.favUI(await DB.toggleFavorite(id).catch(() => false));
      $('item-share').onclick = () => this.shareMenu(row);
      $('item-play').onclick = () => {
        const d = this.current.detail;
        if (d?.downloadURL) {
          Player.start({ id, title: row[1], url: d.downloadURL });
        } else {
          Player.play(this.current);
        }
      };

      // The catalog's own record first (synopsis, cast, the build-time picked
      // downloadURL) — instant, and immune to archive.org metadata-API hangs.
      const det = await Details.get(id);
      if (this.current.id !== id) return;     // navigated away mid-fetch
      if (det) {
        this.current.detail = det;
        const meta = [
          row[2] && String(row[2]),
          det.runtimeSeconds && `${Math.round(det.runtimeSeconds / 60)} min`,
          row[3] && row[3].replace(/-/g, ' '),
          det.director && `Dir. ${det.director}`,
        ].filter(Boolean).join(' · ');
        if (meta) $('item-meta').textContent = meta;
        if (det.synopsis) $('item-desc').textContent = det.synopsis;
        this.castRow(det);
        if (det.downloadURL) {
          $('item-play').disabled = false;
          return;                              // playable — done, no archive.org call
        }
      }
      // Fallback (item not in the shards yet, or no baked URL): resolve via
      // the metadata API, bounded so a hung response can't strand the page.
      try {
        const meta = await API.fetchMetadata(id, { timeoutMs: 12000 });
        const s = API.summarize(meta);
        if (this.current.id !== id) return;
        this.current.summary = s;
        if (!$('item-desc').textContent) {
          $('item-desc').textContent = stripHTML(s.description).slice(0, 1200);
        }
        if (s.videoFile) {
          $('item-play').disabled = false;
        } else if (!det?.downloadURL) {
          this.fail('No playable video file on this item.');
        }
      } catch (err) {
        if (det) return;                       // shard gave us a page; good enough
        this.fail(`Couldn't reach archive.org for this title (${err.message}). ` +
                  'Playback and synopsis are unavailable right now.');
      }
    },

    /** Cast & crew bubbles (the iOS CastRow's web twin): TMDb w185 photos,
        initial-letter fallback, director leads the row. */
    castRow(det) {
      const host = $('item-cast');
      const people = [];
      if (det.director) people.push({ name: det.director, role: 'Director', profilePath: null });
      for (const c of det.cast || []) people.push(c);
      host.replaceChildren(...people.slice(0, 10).map(p => {
        const fig = document.createElement('figure');
        fig.className = 'person';
        if (p.profilePath) {
          const img = document.createElement('img');
          img.loading = 'lazy'; img.alt = '';
          img.src = p.profilePath.startsWith('http')
            ? p.profilePath
            : `https://image.tmdb.org/t/p/w185${p.profilePath}`;
          img.onerror = () => fig.replaceChild(this.initial(p.name), img);
          fig.append(img);
        } else {
          fig.append(this.initial(p.name));
        }
        const cap = document.createElement('figcaption');
        cap.textContent = p.name;
        if (p.role) {
          const r = document.createElement('span');
          r.textContent = p.role;
          cap.append(r);
        }
        fig.append(cap);
        return fig;
      }));
      host.hidden = !people.length;
    },

    initial(name) {
      const d = document.createElement('div');
      d.className = 'person-initial';
      d.textContent = (name || '?').trim()[0].toUpperCase();
      return d;
    },

    /** The share menu (§4.6): one Share button opens a small dialog with
        every outbound action — system share/copy, open-in-app (mobile),
        archive.org — so the action row stays Play · ♡ · Share. */
    shareMenu(row) {
      const dlg = $('sharemenu');
      $('sharemenu-app').hidden = !(Platform.iOS || Platform.android);
      $('sharemenu-app').onclick = () => {
        dlg.close();
        location.href = Platform.android
          ? `intent://item/${encodeURIComponent(row[0])}#Intent;scheme=archivewatch;` +
            `package=app.archivewatch.android;S.browser_fallback_url=` +
            `${encodeURIComponent(location.href)};end`
          : `archivewatch://item/${encodeURIComponent(row[0])}`;
      };
      $('sharemenu-share').onclick = async () => { dlg.close(); await this.share(row); };
      $('sharemenu-archive').onclick = () => {
        dlg.close();
        window.open(API.detailsURL(row[0]), '_blank', 'noopener');
      };
      $('sharemenu-cancel').onclick = () => dlg.close();
      dlg.showModal();
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

  /* ---------------------------------------------------------------- *
   * TV series — spine fetched from Pages (series/{slug}.json), the    *
   * same canonical season→episode data the apps render (PARITY §3).   *
   * ---------------------------------------------------------------- */
  const SeriesView = {
    current: null,

    async render(slug) {
      if (!slug) { location.hash = '#/'; return; }
      this.current = slug;
      const card = Data.byID.get(`series:${slug}`);
      $('series-title').textContent = card ? card[1] : slug;
      $('series-meta').textContent = '';
      $('series-overview').textContent = '';
      $('series-poster').src = card ? Data.poster(card) : '';
      $('series-season').hidden = true;
      $('series-error').hidden = true;
      $('series-loading').hidden = false;
      $('series-episodes').replaceChildren();

      let series;
      try {
        const r = await fetch(new URL(`series/${encodeURIComponent(slug)}.json`, PAGES_ROOT));
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        series = await r.json();
      } catch (err) {
        if (this.current !== slug) return;
        $('series-loading').hidden = true;
        const e = $('series-error');
        e.textContent = `Couldn't load this series (${err.message}). Check your connection and retry.`;
        e.hidden = false;
        return;
      }
      if (this.current !== slug) return;   // navigated away mid-fetch
      $('series-loading').hidden = true;

      $('series-title').textContent = series.title || slug;
      const yr = series.yearStart
        ? (series.yearEnd ? `${series.yearStart}–${series.yearEnd}` : String(series.yearStart))
        : null;
      const eps = (series.seasons || []).flatMap(s => s.episodes || [])
        .filter(e => e.downloadURL);
      $('series-meta').textContent = [yr, `${eps.length} playable episodes`]
        .filter(Boolean).join(' · ');
      $('series-overview').textContent = stripHTML(series.overview || '').slice(0, 600);
      if (series.posterURL) $('series-poster').src = series.posterURL;

      const seasons = (series.seasons || []).filter(s => (s.episodes || []).some(e => e.downloadURL));
      if (!seasons.length) {
        const e = $('series-error');
        e.textContent = 'This series is in the catalog, but no playable episodes have been matched yet.';
        e.hidden = false;
        return;
      }
      const sel = $('series-season');
      if (seasons.length > 1) {
        sel.hidden = false;
        sel.replaceChildren(...seasons.map((s, i) => new Option(
          s.seasonNumber != null ? `Season ${s.seasonNumber}` : 'More episodes', String(i))));
        sel.onchange = () => this.episodes(series, seasons[Number(sel.value)]);
      }
      this.episodes(series, seasons[0]);
    },

    /** Rows render synchronously (the list must never wait on storage);
        resume badges hydrate once IndexedDB answers. */
    episodes(series, season) {
      const host = $('series-episodes');
      const rows = (season.episodes || []).filter(e => e.downloadURL).map(ep => {
        const b = document.createElement('button');
        b.className = 'episode';
        b.dataset.ep = ep.archiveID;
        const img = document.createElement('img');
        img.loading = 'lazy'; img.alt = '';
        img.src = ep.stillURL || API.thumbnailURL(ep.archiveID);
        img.onerror = () => { img.onerror = null; img.src = API.thumbnailURL(ep.archiveID); };
        const txt = document.createElement('span');
        const n = document.createElement('span'); n.className = 'ep-n';
        n.textContent = epLabel(ep);
        const t = document.createElement('span'); t.className = 'ep-t';
        t.textContent = ep.title || ep.archiveID;
        txt.append(n, t);
        if (ep.overview) {
          const o = document.createElement('span'); o.className = 'ep-o';
          o.textContent = stripHTML(ep.overview);
          txt.append(o);
        }
        b.append(img, txt);
        b.onclick = () => Player.start({
          id: ep.archiveID,
          title: [series.title, epLabel(ep)].filter(Boolean).join(' · '),
          url: ep.downloadURL,
        });
        return b;
      });
      host.replaceChildren(...rows);

      DB.progress().then(progress => {
        const byEp = new Map(progress.map(p => [p.id, p]));
        for (const b of host.children) {
          const p = byEp.get(b.dataset.ep);
          if (p && p.duration > 0 && p.position > 10 && p.position / p.duration < 0.95) {
            const r = document.createElement('span'); r.className = 'ep-resume';
            r.textContent = `Resume · ${Math.round(p.position / 60)} min in`;
            b.lastChild.append(r);
          }
        }
      }).catch(() => { /* storage unavailable → rows still play */ });
    },
  };

  function epLabel(ep) {
    if (ep.seasonNumber != null && ep.episodeNumber != null) {
      return `S${ep.seasonNumber} · E${ep.episodeNumber}`;
    }
    return ep.episodeNumber != null ? `Ep. ${ep.episodeNumber}` : '';
  }

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
      const url = `https://archive.org/download/${encodeURIComponent(id)}/` +
        encodeURIComponent(summary.videoFile.name).replace(/%2F/g, '/');
      await this.start({ id, title: row[1], url });
    },

    /** Direct-URL entry (episodes carry downloadURL in the series spine). */
    async start({ id, title, url }) {
      this.ctx = { id, title };
      const video = $('video');

      $('player-title').textContent = title;
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
      DB.saveProgress(this.ctx.id, video.currentTime, video.duration, this.ctx.title);
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
