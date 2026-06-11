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
        const req = indexedDB.open('archivewatch', 2);
        req.onupgradeneeded = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains('favorites')) {
            db.createObjectStore('favorites', { keyPath: 'id' });
          }
          if (!db.objectStoreNames.contains('progress')) {
            db.createObjectStore('progress', { keyPath: 'id' });
          }
          if (!db.objectStoreNames.contains('playlists')) {
            db.createObjectStore('playlists', { keyPath: 'id' });
          }
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
      playlists: () => getAll('playlists'),
      savePlaylist: pl =>
        tx('playlists', 'readwrite', s => s.put({ ...pl, modifiedAt: Date.now() })),
      deletePlaylist: id => tx('playlists', 'readwrite', s => s.delete(id)),
      togglePlaylistItem: async (plID, archiveID) => {
        const pl = (await getAll('playlists')).find(p => p.id === plID);
        if (!pl) return false;
        const i = pl.archiveIDs.indexOf(archiveID);
        if (i >= 0) pl.archiveIDs.splice(i, 1); else pl.archiveIDs.push(archiveID);
        await DB.savePlaylist(pl);
        return i < 0;
      },
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

    /** Professional artwork (the apps' hasProfessionalArtwork): designed
        poster, NOT a generated frame cover. Schema-3 rows (no pro column)
        degrade to designed-art. Home admits only these. */
    isPro(row) {
      return row[5] === 1 || (row[5] === undefined && !!row[4]);
    },

    /** Resolve a featured.json shelf through the index's editorial shelves
        map — the same curated item_shelves assignments the apps query, so
        Home inherits the rights audit + adult filter and every shelf has its
        own identity (live scrape did neither; see WEB-DESIGN §2.3). Shuffled
        fresh per visit, designed artwork leading. */
    shelfRows(shelf, limit = 16) {
      // TV shelves surface SERIES cards (professional TVDB/TVmaze posters,
      // tap → episodes), not individual tv-specials whose art is frame
      // grabs — the item-level pro coverage measured 1–10 per shelf
      // (owner direction 2026-06-10: pull the show poster).
      if (shelf.category === 'tv-series') {
        const m = shelf.id.match(/(\d{4})s?$/);
        const decade = m ? Number(m[1]) : null;
        const cards = this.rows.filter(r => r[3] === 'tv-series' && this.isPro(r)
          && (!decade || (r[2] && r[2] >= decade && r[2] < decade + 10)));
        return shuffle(cards).slice(0, limit);
      }
      let rows;
      if (shelf.type === 'curated' && Array.isArray(shelf.items)) {
        rows = shelf.items.map(i => this.byID.get(i.archiveID)).filter(Boolean);
      } else {
        rows = (this.shelves[shelf.id] || []).map(id => this.byID.get(id)).filter(Boolean);
      }
      const pro = shuffle(rows.filter(r => this.isPro(r)));
      const rest = shuffle(rows.filter(r => !this.isPro(r)));
      return pro.concat(rest).slice(0, limit);
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
    let art;
    if (type === 'tv-series' && !row[4]) {
      // series: ids aren't archive.org items — no thumbnail exists to fetch
      art = placeholderArt(row);
    } else {
      const img = document.createElement('img');
      img.loading = 'lazy';
      img.decoding = 'async';
      img.alt = '';
      wireArt(img,
        type === 'tv-series' ? [row[4]] : [Data.poster(row), API.thumbnailURL(id)],
        null, () => img.replaceWith(placeholderArt(row)));
      art = img;
    }
    const t = document.createElement('span'); t.className = 't'; t.textContent = title;
    const y = document.createElement('span'); y.className = 'y';
    y.textContent = year ? String(year) : '';
    a.append(art, t, y);
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

  /** archive.org throttles image bursts (transient 503s on /services/img and
      /download), so a one-shot onerror fallback left tiles broken until a
      manual refresh. Walk the fallback chain, then retry the whole chain up
      to twice with jittered backoff — removing src first so the browser
      actually re-requests instead of ignoring a same-value assignment. */
  function wireArt(img, urls, onLoad, onFail) {
    const chain = [...new Set(urls.filter(Boolean))];
    if (!chain.length) { if (onFail) onFail(); return; }
    // Persistent imgs (detail/series posters) get re-wired on navigation; the
    // token keeps a pending retry from clobbering the next title's art.
    const token = img.dataset.artToken = String(Number(img.dataset.artToken || 0) + 1);
    let step = 0, round = 0;
    const set = () => { img.removeAttribute('src'); img.src = chain[step]; };
    img.onerror = () => {
      if (step < chain.length - 1) { step++; set(); return; }
      if (round >= 2) { img.onerror = null; if (onFail) onFail(); return; }
      round++; step = 0;
      setTimeout(() => {
        if (img.isConnected && img.dataset.artToken === token) set();
      }, 1800 * round + Math.random() * 700);
    };
    if (onLoad) img.onload = () => onLoad(img.currentSrc || img.src);
    set();
  }

  /** Decision 013 semantic accents — content meaning only, never chrome. */
  const TYPE_ACCENTS = {
    'feature-film': '#FF5C35', 'tv-series': '#2D5BFF', 'silent-film': '#C9A66B',
    'animation': '#FF4D8D', 'newsreel': '#8A8F98', 'documentary': '#3FA796',
    'ephemeral': '#7C5BBA', 'short-film': '#E8A317',
  };

  /** The apps' procedural typographic card, web twin: shown when an item has
      no real/generated art to fetch (series: ids aren't archive.org items, so
      /services/img would return the Archive's generic placeholder) or when
      every fetch attempt failed. Never an archive.org placeholder. */
  function placeholderArt(row) {
    const d = document.createElement('div');
    d.className = 'card-ph';
    d.style.setProperty('--ph-accent', TYPE_ACCENTS[row[3]] || '#555');
    const s = document.createElement('span');
    s.textContent = row[1];
    d.append(s);
    return d;
  }

  /* ---------------------------------------------------------------- *
   * Router — URL-driven state (the web superpower)                    *
   * ---------------------------------------------------------------- */
  const VIEWS = ['home', 'browse', 'search', 'library', 'item', 'series', 'about',
                 'surprise', 'playlist', 'channels'];
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
    if (name === 'surprise') Surprise.render();
    if (name === 'playlist') PlaylistView.render(decodeURIComponent(seg[1] || ''));
    if (name === 'channels') ChannelsView.render();
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
      const shelfSection = (title, subtitle, rows) => {
        const sec = document.createElement('section');
        sec.className = 'shelf';
        const h = document.createElement('h2');
        h.textContent = title;
        sec.append(h);
        if (subtitle) {
          const s = document.createElement('p');
          s.className = 'muted shelf-sub';
          s.textContent = subtitle;
          sec.append(s);
        }
        const rail = document.createElement('div');
        rail.className = 'shelf-row';
        rail.append(...rows.map(card));
        sec.append(rail);
        return sec;
      };
      host.append(this.categoryTiles());
      for (const shelf of Data.featured?.shelves || []) {
        const rows = Data.shelfRows(shelf, 32)
          .filter(r => Data.isPro(r) && !used.has(r[0])).slice(0, 16);
        if (rows.length < 4) continue;
        rows.forEach(r => used.add(r[0]));
        host.append(shelfSection(shelf.title, shelf.subtitle, rows));
      }
      // Hidden Gems (apps' parity row): designed art from the popularity TAIL.
      const tail = Data.rows.slice(Math.floor(Data.rows.length * 0.4));
      const gems = shuffle(tail.filter(r => Data.isPro(r) && !used.has(r[0]))).slice(0, 16);
      if (gems.length >= 6) {
        gems.forEach(r => used.add(r[0]));
        host.append(shelfSection('Hidden Gems', 'Lovingly restored, rarely watched', gems));
      }
      // Public Domain Day: this year's newly-free class (currentYear - 95).
      const pdYear = new Date().getFullYear() - 95;
      const pd = shuffle(Data.rows.filter(r =>
        r[2] === pdYear && Data.isPro(r) && !used.has(r[0]))).slice(0, 16);
      if (pd.length >= 6) {
        host.append(shelfSection('Public Domain Day',
          `Class of ${pdYear} — newly free to share`, pd));
      }
      host.append(this.eraTiles());   // last row, matching the apps
      if (!host.children.length) {
        const p = document.createElement('p');
        p.className = 'muted';
        p.textContent = 'Shelves are unavailable right now — try Browse.';
        host.append(p);
      }
    },

    /** Category tiles (apps' Browse-by-Category row): featured.json accents,
        count-gated ≥30 so a near-empty grid never ships behind a tile. */
    categoryTiles() {
      const counts = {};
      for (const r of Data.rows) counts[r[3]] = (counts[r[3]] || 0) + 1;
      const sec = document.createElement('section');
      sec.className = 'shelf';
      const h = document.createElement('h2');
      h.textContent = 'Browse by Category';
      const rail = document.createElement('div');
      rail.className = 'shelf-row tile-row';
      for (const cat of Data.featured?.categories || []) {
        if ((counts[cat.id] || 0) < 30) continue;
        const a = document.createElement('a');
        a.className = 'cat-tile';
        a.href = `#/browse?type=${encodeURIComponent(cat.id)}`;
        a.style.setProperty('--tile-accent', cat.accent || '#555');
        a.textContent = cat.displayName;
        rail.append(a);
      }
      sec.append(h, rail);
      return sec;
    },

    /** Era tiles (apps' Browse-by-Era row) — the LAST Home row. */
    eraTiles() {
      const counts = {};
      for (const r of Data.rows) {
        if (!r[2]) continue;
        const d = Math.floor(r[2] / 10) * 10;
        if (d >= 1890 && d <= 2020) counts[d] = (counts[d] || 0) + 1;
      }
      const sec = document.createElement('section');
      sec.className = 'shelf';
      const h = document.createElement('h2');
      h.textContent = 'Browse by Era';
      const rail = document.createElement('div');
      rail.className = 'shelf-row tile-row';
      for (const d of Object.keys(counts).map(Number).sort((a, b) => a - b)) {
        const a = document.createElement('a');
        a.className = 'era-tile';
        a.href = `#/browse?decade=${d}`;
        const big = document.createElement('strong');
        big.textContent = `${d}s`;
        const sub = document.createElement('span');
        sub.textContent = eraLabel(d + 5).toUpperCase();
        const n = document.createElement('em');
        n.textContent = `${counts[d].toLocaleString()} titles`;
        a.append(big, sub, n);
        rail.append(a);
      }
      sec.append(h, rail);
      return sec;
    },

    /** Marquee hero (WEB-DESIGN §4.1): a native scroll-snap carousel over the
        day-shuffled designed-art pool. Auto-advance pauses on hover/touch and
        hidden tabs, and is off entirely under prefers-reduced-motion. */
    hero() {
      // A wide pre-screened pool (designed art, popularity-ranked) dealt
      // randomly per visit — the hero is different every time.
      const pool = shuffle(Data.rows.filter(r => Data.isPro(r)).slice(0, 300)).slice(0, 6);
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

        const poster = document.createElement('img');
        poster.className = 'hero-poster';
        poster.alt = '';
        poster.loading = i === 0 ? 'eager' : 'lazy';
        // Ambient mirrors whatever art actually loaded (it shares the HTTP
        // cache entry), so a throttled poster can't strand a blank backdrop.
        wireArt(poster, [Data.poster(row), API.thumbnailURL(id)],
          src => { ambient.style.backgroundImage = `url("${src}")`; });

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

      const playlists = (await DB.playlists().catch(() => []))
        .sort((a, b) => (b.modifiedAt || 0) - (a.modifiedAt || 0));
      const host = $('library-playlists');
      host.replaceChildren(...playlists.map(pl => {
        const a = document.createElement('a');
        a.className = 'playlist-card';
        a.href = `#/playlist/${encodeURIComponent(pl.id)}`;
        const t = document.createElement('strong');
        t.textContent = pl.name;
        const n = document.createElement('span');
        n.textContent = `${pl.archiveIDs.length} titles`;
        a.append(t, n);
        return a;
      }));
      $('library-playlists-empty').hidden = playlists.length > 0;
    },
  };

  /* ---------------------------------------------------------------- *
   * Surprise — the serendipity grid (apps' re-rollable tiles)         *
   * ---------------------------------------------------------------- */
  const Surprise = {
    wired: false,
    render() {
      if (!this.wired) {
        this.wired = true;
        $('surprise-reroll').onclick = () => this.deal();
      }
      this.deal();
    },
    deal() {
      // One tile per major category plus extra popular picks — every tile a
      // designed-art random draw, fresh on every visit/re-roll.
      const byType = {};
      for (const r of Data.rows) {
        if (!Data.isPro(r)) continue;
        (byType[r[3]] ??= []).push(r);
      }
      const picks = [];
      const seen = new Set();
      for (const t of Object.keys(byType)) {
        const pool = byType[t];
        const pick = pool[Math.floor(Math.random() * pool.length)];
        if (pick && !seen.has(pick[0])) { seen.add(pick[0]); picks.push(pick); }
      }
      const pro = Data.rows.filter(r => Data.isPro(r) && !seen.has(r[0]));
      while (picks.length < 12 && pro.length) {
        const pick = pro.splice(Math.floor(Math.random() * pro.length), 1)[0];
        seen.add(pick[0]); picks.push(pick);
      }
      fillGrid($('surprise-grid'), shuffle(picks));
    },
  };

  /* ---------------------------------------------------------------- *
   * Playlist view                                                     *
   * ---------------------------------------------------------------- */
  const PlaylistView = {
    async render(id) {
      const pl = (await DB.playlists().catch(() => [])).find(p => p.id === id);
      if (!pl) { location.hash = '#/library'; return; }
      $('playlist-title').textContent = pl.name;
      const rows = pl.archiveIDs.map(aid => Data.byID.get(aid)).filter(Boolean);
      fillGrid($('playlist-grid'), rows);
      $('playlist-empty').hidden = rows.length > 0;
      $('playlist-delete').onclick = async () => {
        if (!confirm(`Delete the playlist “${pl.name}”?`)) return;
        await DB.deletePlaylist(id).catch(() => {});
        location.hash = '#/library';
      };
    },
  };

  /* ---------------------------------------------------------------- *
   * Channels — the EPG guide (PARITY §5, the apps' date-seeded grid)  *
   *                                                                   *
   * Pools come precomputed (channel-pools.json, build_channel_pools)  *
   * because the index has no runtime/genre; the SCHEDULE is computed  *
   * HERE with the same FNV-1a + SplitMix64 + 6 AM-local broadcast-day *
   * algorithm as the apps' ChannelScheduler, so the guide anchors to  *
   * the viewer's local day. Sticky rail + ruler = the web-native way  *
   * to pin both axes of a TV listing.                                 *
   * ---------------------------------------------------------------- */
  const Scheduler = (() => {
    const MASK = (1n << 64n) - 1n;
    function fnv1a(str) {
      let h = 0xcbf29ce484222325n;
      for (const b of new TextEncoder().encode(str)) {
        h ^= BigInt(b);
        h = (h * 0x100000001b3n) & MASK;
      }
      return h;
    }
    function splitMix(seed) {
      let state = seed & MASK;
      return () => {
        state = (state + 0x9e3779b97f4a7c15n) & MASK;
        let z = state;
        z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK;
        z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK;
        return (z ^ (z >> 31n)) & MASK;
      };
    }
    function dayAnchor(now) {
      const d = new Date(now);
      d.setHours(6, 0, 0, 0);
      if (now < d) d.setDate(d.getDate() - 1);
      return d;
    }
    function runtimeSec(prog) {
      const [, , run, , type] = prog;
      if (run && run > 120) return Math.min(run, 3 * 3600);
      if (type === 'feature-film' || type === 'silent-film') return 90 * 60;
      if (type === 'tv-special' || type === 'documentary') return 50 * 60;
      if (['short-film', 'animation', 'newsreel', 'ephemeral'].includes(type)) return 12 * 60;
      return 3600;
    }
    /** [{prog, start, end}] covering anchor → now+26h, deterministic per day. */
    function schedule(channelID, programs, now) {
      if (!programs.length) return [];
      const anchor = dayAnchor(now);
      const key = `${channelID}${anchor.getFullYear()}-${anchor.getMonth() + 1}-${anchor.getDate()}`;
      const next = splitMix(fnv1a(key));
      const pool = [...programs];
      for (let i = pool.length - 1; i > 0; i--) {
        const j = Number(next() % BigInt(i + 1));
        [pool[i], pool[j]] = [pool[j], pool[i]];
      }
      const slots = [];
      let cursor = anchor.getTime();
      const until = now.getTime() + 26 * 3600e3;
      let i = 0;
      while (cursor < until && slots.length < 2000) {
        const prog = pool[i % pool.length];
        const end = cursor + runtimeSec(prog) * 1000;
        slots.push({ prog, start: cursor, end });
        cursor = end + 120e3;   // 2-minute inter-program buffer
        i++;
      }
      return slots;
    }
    return { schedule, dayAnchor };
  })();

  // Web stand-ins for the apps' SF Symbol channel icons.
  const CHANNEL_ICONS = {
    drama: '🎭', comedy: '😄', noir: '🔍', thrill: '⚡', horror: '🌙',
    western: '🤠', scifi: '🚀', silent: '🎞️', cartoon: '🖌️', news: '📰',
    docs: '🌍', tv: '📺', 'tv-comedy': '📺', 'tv-drama': '📺',
    'tv-western': '📺',
  };

  const ChannelsView = {
    data: null,
    built: false,

    async render() {
      const host = $('epg');
      if (this.built) return;
      if (!this.data) {
        try {
          const r = await fetch(new URL('channel-pools.json', PAGES_ROOT),
                                { signal: AbortSignal.timeout(15000) });
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          this.data = await r.json();
        } catch (err) {
          $('channels-error').textContent =
            `The channel guide couldn't load (${err.message}).`;
          $('channels-error').hidden = false;
          return;
        }
      }
      this.built = true;
      const now = new Date();
      const anchor = Scheduler.dayAnchor(now);
      // px per minute — tighter on phones so a feature film isn't two screens
      // wide and shorts stay tappable.
      const PPM = window.innerWidth < 600 ? 3 : 4;
      const totalMin = 26 * 60 + (now.getTime() - anchor.getTime()) / 60e3;
      const stripW = Math.ceil(totalMin * PPM);

      // Ruler: corner + a tick every 30 min from the anchor.
      const ruler = document.createElement('div');
      ruler.className = 'epg-ruler';
      const corner = document.createElement('div');
      corner.className = 'epg-corner';
      ruler.append(corner);
      const ticksHost = document.createElement('div');
      ticksHost.className = 'epg-strip';
      ticksHost.style.width = `${stripW}px`;
      const fmt = t => new Date(t).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
      for (let m = 0; m < totalMin; m += 30) {
        const tick = document.createElement('span');
        tick.className = 'epg-tick';
        tick.style.left = `${m * PPM}px`;
        tick.textContent = fmt(anchor.getTime() + m * 60e3);
        ticksHost.append(tick);
      }
      ruler.append(ticksHost);
      host.replaceChildren(ruler);

      for (const ch of this.data.channels) {
        const slots = Scheduler.schedule(ch.id, ch.programs, now);
        const row = document.createElement('div');
        row.className = 'epg-row';
        const rail = document.createElement('div');
        rail.className = 'epg-rail';
        rail.style.setProperty('--ch-accent', ch.accent);
        const dot = document.createElement('span');
        dot.className = 'epg-dot';
        dot.textContent = CHANNEL_ICONS[ch.id] || '📺';
        const name = document.createElement('span');
        name.textContent = ch.title;
        rail.append(dot, name);
        const strip = document.createElement('div');
        strip.className = 'epg-strip';
        strip.style.width = `${stripW}px`;
        for (const slot of slots) {
          const left = (slot.start - anchor.getTime()) / 60e3 * PPM;
          const width = Math.max(16, (slot.end - slot.start) / 60e3 * PPM - 3);
          const b = document.createElement('button');
          b.className = 'epg-block';
          b.title = slot.prog[1];   // tooltip carries the title for tiny blocks
          if (slot.start <= now.getTime() && slot.end > now.getTime()) {
            b.classList.add('airing');
            b.style.setProperty('--ch-accent', ch.accent);
          } else if (slot.end <= now.getTime()) {
            b.classList.add('past');   // already aired — recede, don't shout
          }
          if (width < 52) b.classList.add('tiny');   // no readable room: art only
          b.style.left = `${left}px`;
          b.style.width = `${width}px`;
          const t = document.createElement('span');
          t.className = 'epg-bt';
          t.textContent = slot.prog[1];
          const when = document.createElement('span');
          when.className = 'epg-bw';
          when.textContent = fmt(slot.start);
          b.append(t, when);
          b.onclick = () => this.tune(ch, slots, slot);
          strip.append(b);
        }
        row.append(rail, strip);
        host.append(row);
      }
      // The red now-line, then scroll the viewport to ~30 min before now.
      const nowX = (now.getTime() - anchor.getTime()) / 60e3 * PPM;
      const line = document.createElement('div');
      line.className = 'epg-now';
      line.style.left = `calc(var(--epg-rail-w) + ${nowX}px)`;
      host.append(line);
      requestAnimationFrame(() => {
        host.scrollLeft = Math.max(0, nowX - 30 * PPM);
      });
    },

    /** Tune in: lineup from the tapped slot, commercials woven, join live
        slots in progress. Channel playback never persists resume progress
        (the apps' rule). */
    tune(ch, slots, slot) {
      const idx = slots.indexOf(slot);
      const lineup = slots.slice(idx);
      const ads = shuffle(this.data.commercials || []);
      const queue = [];
      lineup.forEach((s, i) => {
        queue.push({ id: s.prog[0], title: `${s.prog[1]} · ${ch.title}`, url: s.prog[3] });
        if (ads.length && i < lineup.length - 1) {
          const ad = ads[i % ads.length];
          queue.push({ id: ad[0], title: `${ad[1]} · Commercial break`, url: ad[3] });
        }
      });
      const now = Date.now();
      const startAt = (slot.start <= now && slot.end > now)
        ? Math.max(0, (now - slot.start) / 1000) : 0;
      Player.start({ ...queue[0], queue, queueIndex: 0, startAt, persist: false });
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
      wireArt($('item-poster'), [Data.poster(row), API.thumbnailURL(id)]);
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
      $('item-playlist').onclick = () => this.playlistMenu(id);
      this.related(row);
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

    /** More Like This (apps' related query, index approximation): same type,
        same era ±15y, designed art, never self. */
    related(row) {
      const [id, , year, type] = row;
      const host = $('item-related');
      const rows = shuffle(Data.rows.filter(r =>
        r[0] !== id && r[3] === type && Data.isPro(r) &&
        (!year || !r[2] || Math.abs(r[2] - year) <= 15))).slice(0, 12);
      $('item-related-row').replaceChildren(...rows.map(card));
      host.hidden = rows.length < 4;
    },

    /** Add-to-playlist dialog: toggle membership per playlist, create new. */
    async playlistMenu(archiveID) {
      const dlg = $('playlistmenu');
      const renderList = async () => {
        const playlists = await DB.playlists().catch(() => []);
        $('playlistmenu-list').replaceChildren(...playlists.map(pl => {
          const b = document.createElement('button');
          b.className = 'btn-ghost';
          const inList = pl.archiveIDs.includes(archiveID);
          b.textContent = `${inList ? '✓ ' : ''}${pl.name} (${pl.archiveIDs.length})`;
          b.onclick = async () => {
            await DB.togglePlaylistItem(pl.id, archiveID).catch(() => {});
            renderList();
          };
          return b;
        }));
      };
      $('playlistmenu-new').onclick = async () => {
        const name = prompt('Playlist name');
        if (!name || !name.trim()) return;
        await DB.savePlaylist({
          id: `pl-${Date.now().toString(36)}`,
          name: name.trim(), archiveIDs: [archiveID],
          createdAt: Date.now(),
        }).catch(() => {});
        renderList();
      };
      $('playlistmenu-cancel').onclick = () => dlg.close();
      await renderList();
      dlg.showModal();
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
      // Only real art — services/img on a series: id returns the Archive's
      // generic placeholder; an empty 2:3 well is quieter until the spine's
      // posterURL (if any) arrives below.
      if (card && card[4]) wireArt($('series-poster'), [card[4]]);
      else $('series-poster').removeAttribute('src');
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
      if (series.posterURL) wireArt($('series-poster'), [series.posterURL]);

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
      const playable = (season.episodes || []).filter(e => e.downloadURL);
      // The binge queue (apps' episode auto-advance): when an episode ends,
      // the next one in the season plays automatically.
      const queue = playable.map(e => ({
        id: e.archiveID,
        title: [series.title, epLabel(e)].filter(Boolean).join(' · '),
        url: e.downloadURL,
      }));
      const rows = playable.map((ep, qi) => {
        const b = document.createElement('button');
        b.className = 'episode';
        b.dataset.ep = ep.archiveID;
        const img = document.createElement('img');
        img.loading = 'lazy'; img.alt = '';
        wireArt(img, [ep.stillURL, API.thumbnailURL(ep.archiveID)]);
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
        b.onclick = () => Player.start({ ...queue[qi], queue, queueIndex: qi });
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

    /** Direct-URL entry (episodes carry downloadURL in the series spine).
        `queue`/`queueIndex` enable binge: on ended, the next queued entry
        plays. `startAt` joins a channel program in progress; `persist:false`
        keeps channel playback out of Continue Watching (the apps' rule). */
    async start({ id, title, url, queue = null, queueIndex = 0,
                  startAt = 0, persist = true }) {
      this.ctx = { id, title, queue, queueIndex, persist };
      const video = $('video');

      $('player-title').textContent = title;
      $('player-error').hidden = true;
      video.src = url;

      // Seek AFTER metadata arrives — Safari/Chrome can silently drop a
      // currentTime set on a src that hasn't loaded yet (join-in-progress
      // landed at 0:00 instead of mid-program).
      let seekTo = 0;
      if (startAt > 0) {
        seekTo = startAt;
      } else if (persist) {
        const saved = await DB.progressFor(id);
        if (saved && saved.position > 10 && (!saved.duration ||
            saved.position / saved.duration < 0.95)) {
          seekTo = saved.position;
        }
      }
      if (seekTo > 0) {
        if (video.readyState >= 1) video.currentTime = seekTo;
        else video.addEventListener('loadedmetadata',
          () => { video.currentTime = seekTo; }, { once: true });
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
      video.onended = () => {
        this.persist();
        const { queue, queueIndex, persist } = this.ctx || {};
        if (queue && queueIndex + 1 < queue.length) {
          const next = queue[queueIndex + 1];
          this.start({ ...next, queue, queueIndex: queueIndex + 1, persist });
        } else {
          this.close();
        }
      };
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
      if (!this.ctx || this.ctx.persist === false) return;
      if (!video.duration || !isFinite(video.duration)) return;
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
