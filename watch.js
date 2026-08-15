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

  // The site root. A PACKAGED TV app (webOS .ipk / Tizen .wgt) runs its
  // document from file://, where a relative data URL would resolve to a local
  // file that isn't in the package — every fetch would 404 and the app would
  // launch to an empty catalog. Fall back to the canonical origin so ONE build
  // serves the browser and both packages (Decision 047 §7.1).
  const CANONICAL_ROOT = 'https://archivewatch.org/';
  const PAGES_ROOT = /^https?:$/.test(location.protocol)
    ? new URL('.', location.href)
    : new URL(CANONICAL_ROOT);
  const INDEX_URL = new URL('catalog-index.json', PAGES_ROOT);
  const EPISODES_URL = new URL('episodes-index.json', PAGES_ROOT);
  const FEATURED_URL = new URL('featured.json', PAGES_ROOT);
  const PAGE_SIZE = 60;
  // Canonical Home shelf order, matching Apple TV (Featured.homeShelfPriority) — owner 2026-06-29.
  const HOME_SHELF_PRIORITY = [
    'popular-features', 'wikidata-pd', 'film-noir', 'scifi-horror',
    'silent-hall-of-fame', 'melies', 'video-cellar', 'comedy',
    'animation-all', 'vintage-cartoons', 'nasa', 'classic-tv-1960s',
    'classic-tv-1950s', 'classic-tv-1970s', 'ephemera', 'newsreels',
    'educational', 'picfixer', 'silent-era', 'popular-classic-tv',
    'all-time-features',
  ];

  /* ---------------------------------------------------------------- *
   * Tiny IndexedDB store: favorites + watch progress (offline-first)  *
   * ---------------------------------------------------------------- */
  const DB = (() => {
    let dbp = null;
    function open() {
      dbp ??= new Promise((res, rej) => {
        const req = indexedDB.open('archivewatch', 3);
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
          if (!db.objectStoreNames.contains('channels')) {
            db.createObjectStore('channels', { keyPath: 'id' });
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
      // Raw puts for the Drive sync merge (js/drivesync.js): write a record
      // exactly as merged, no semantics re-applied.
      putProgressRaw: rec => tx('progress', 'readwrite', s => s.put(rec)),
      saveFavorite: f => tx('favorites', 'readwrite', s => s.put(f)),
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
      // History semantics (Decision 078 parity): first-watch date, session
      // count (>6h gap = new session), durable everDone — a rewatch resets
      // the position but never removes "you have watched this".
      saveProgress: async (id, position, duration, title) => {
        const prior = (await getAll('progress')).find(p => p.id === id);
        const now = Date.now();
        const plays = (prior?.plays || 1) + (prior && now - prior.at > 6 * 3600_000 ? 1 : 0);
        const everDone = !!(prior?.everDone
          || (duration > 0 && position / duration >= 0.95));
        return tx('progress', 'readwrite',
          s => s.put({ id, position, duration, title, at: now,
                       firstAt: prior?.firstAt || prior?.at || now,
                       plays, everDone }));
      },
      playlists: () => getAll('playlists'),
      userChannels: () => getAll('channels'),
      saveUserChannel: ch => tx('channels', 'readwrite', s => s.put(ch)),
      deleteUserChannel: id => tx('channels', 'readwrite', s => s.delete(id)),
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
    rows: [],            // [id, title, year, type, poster, pro, search?] popularity-sorted
    byID: new Map(),
    shelves: {},         // shelfID → [archiveIDs] (editorial item_shelves analog)
    facets: { keywords: [], studios: [] },  // Decision 046 — Browse filter chips
    featured: null,
    episodes: [],        // episode-items (Decision 045) — see episodes-index.json
    episodeMeta: new Map(),  // archiveID → {slug, series, season, episode}

    loadedAt: 0,

    async load() {
      const [idxR, featR, epR] = await Promise.all([
        fetch(INDEX_URL), fetch(FEATURED_URL), fetch(EPISODES_URL).catch(() => null),
      ]);
      if (!idxR.ok) throw new Error(`catalog index ${idxR.status}`);
      const idx = await idxR.json();
      this.byID.clear();          // a reload re-populates; never accumulate
      this.rows = idx.items || [];
      this.shelves = idx.shelves || {};
      this.collections = idx.collections || {};
      // Decision 046 — keyword/studio facet names (schema 6; absent on older idx).
      this.facets = idx.facets || { keywords: [], studios: [] };
      this.rows.forEach(r => this.byID.set(r[0], r));
      if (featR.ok) this.featured = await featR.json();
      // Episodes are first-class items (Decision 045): resolve by archiveID like
      // any film (favorites / playlists / share / Detail), but stay OUT of
      // Data.rows so Home/Browse film grids never include them.
      if (epR && epR.ok) {
        const eps = (await epR.json()).episodes || [];
        this.episodes = eps;
        for (const [aid, slug, series, season, episode, title, still, year] of eps) {
          // Catalog-index row shape [id, title, year, type, poster, pro].
          this.byID.set(aid, [aid, title, year, 'tv-episode', still, 1]);
          this.episodeMeta.set(aid, { slug, series, season, episode });
        }
      }
      this.loadedAt = Date.now();
    },

    /**
     * Re-fetch the catalog when a long-open tab comes back to the foreground.
     * load() ran once from boot(), so a PWA left open for days kept serving the
     * rows parsed at first boot — the web twin of the native cold-resume bug.
     * The SW is network-first for data URLs, so this really does get fresh
     * bytes. Returns true when the caller should re-render.
     */
    async reloadIfStale(ttlMs = 6 * 60 * 60 * 1000) {
      if (!this.loadedAt || Date.now() - this.loadedAt < ttlMs) return false;
      try {
        await this.load();
        return true;
      } catch {
        return false;      // keep the last-good copy; try again next resume
      }
    },

    /** "S1 · E2" / "Ep. 2" byline for an episode archiveID, else null. */
    episodeNumberLabel(aid) {
      const m = this.episodeMeta.get(aid);
      if (!m) return null;
      if (m.season != null && m.episode != null) return `S${m.season} · E${m.episode}`;
      if (m.episode != null) return `Ep. ${m.episode}`;
      return null;
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

    /** Byte-verified playable (index col 8 — check_liveness). Only the HERO used
        to check this, so a title whose archive.org copy had been removed could
        still headline a Home SHELF and spin forever when opened. Rows from an
        older index have no column 8; those pass, so the shelf degrades rather
        than emptying while probe coverage climbs. */
    plays(row) {
      return row[8] === undefined || row[8] === 1;
    },

    /** A film-surface row: never TV (series cards OR standalone tv-specials).
        TV has its own browse chips; it must never appear in film grids/shelves
        (owner directive 2026-06-18). */
    isFilm(row) {
      return !TV_TYPES.has(row[3]);
    },
    // The Documentary CATEGORY resolves by the genre flag (index col 9), not by
    // contentType — only ~8 items are typed documentary vs 1,109 carrying the
    // genre, so a contentType match would show almost nothing. Every other
    // category is still a plain contentType match. Matches the apps.
    matchesCategory(row, type) {
      if (!type) return !TV_TYPES.has(row[3]);
      if (type === 'documentary') return row[9] === 1 && row[3] !== "animation";
      return row[3] === type;
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
      const x = rec[9] || null;     // rich-metadata extras (Decision 046)
      return {
        downloadURL: rec[0] || null,
        synopsis: rec[1] || null,
        director: rec[2] || null,
        directorProfilePath: x?.dp || null,
        cast: (rec[3] || []).map(c => Array.isArray(c)
          ? { name: c[0], profilePath: c[1] || null, tmdbPersonID: c[2] || null }
          : { name: c, profilePath: null, tmdbPersonID: null }),
        genres: rec[4] || null,
        runtimeSeconds: rec[5] || null,
        backdropURL: rec[6] || null,
        captions: rec[7] || null,   // [[lang, label, vttURL], …]
        community: rec[8] || null,  // {r:avgRating, v:views, f:favorites, rv:[[stars,title,body,reviewer,date],…]}
        // Decision 046 extras — present keys only (object omitted when empty).
        writer: x?.w || null,
        studios: x?.st || null,
        franchise: x?.fr || null,
        tagline: x?.tg || null,
        awards: x?.aw || null,
        composer: x?.co || null,
        cinematographer: x?.ci || null,
        releaseDate: x?.rd || null,
        originalTitle: x?.ot || null,
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
      // Designed poster ONLY — never the archive.org services/img thumbnail (owner 2026-06-29).
      // An art-less row falls through to the typographic placeholder card, not a frame grab.
      wireArt(img,
        Data.isPro(row) ? [row[4]] : [],
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
                 'surprise', 'playlist', 'channels', 'collections', 'collection',
                 'cartoons'];
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
    updateSmartBanner(name, seg);

    if (name === 'home') Home.render();
    if (name === 'browse') Browse.render(q);
    if (name === 'search') Search.render(q);
    if (name === 'library') Library.render();
    if (name === 'item') Item.render(decodeURIComponent(seg[1] || ''));
    if (name === 'series') SeriesView.render(decodeURIComponent(seg[1] || ''));
    if (name === 'surprise') Surprise.render();
    if (name === 'playlist') PlaylistView.render(decodeURIComponent(seg[1] || ''));
    if (name === 'channels') ChannelsView.render();
    if (name === 'collections') Collections.renderList();
    if (name === 'collection') Collections.renderOne(decodeURIComponent(seg[1] || ''));
    if (name === 'cartoons') Cartoons.render();
  }

  /** Point the iOS Smart App Banner's `app-argument` at the current page's
      universal link, so "Open" in the native banner deep-links into the app
      (item/series open their detail; everything else opens to home). Native
      Safari renders the banner from the meta tag — we only refresh its target. */
  function updateSmartBanner(name, seg) {
    const meta = document.querySelector('meta[name="apple-itunes-app"]');
    if (!meta) return;
    let arg = 'https://archivewatch.org/';
    if (name === 'item' && seg[1]) arg += `item/${encodeURIComponent(decodeURIComponent(seg[1]))}`;
    else if (name === 'series' && seg[1]) arg += `series/${encodeURIComponent(decodeURIComponent(seg[1]))}`;
    meta.setAttribute('content', `app-id=6776697407, app-argument=${arg}`);
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
      // Keyed on normalized TITLE+year (not archiveID) so two uploads of the same
      // film — different ids, same title — can't repeat across shelves either.
      const dedupKey = r => {
        const t = String(r[1] || '').toLowerCase().normalize('NFKD').replace(/[^a-z0-9]/g, '');
        return (t && r[2]) ? `ty:${t}|${r[2]}` : `id:${r[0]}`;
      };
      const used = new Set(heroIDs.map(id => Data.byID.get(id)).filter(Boolean).map(dedupKey));
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
      // Featured shelves in the CANONICAL Apple-TV order (not featured.json file order) — owner
      // 2026-06-29 shelf parity. Ids absent from the catalog are skipped.
      const shelfById = Object.fromEntries((Data.featured?.shelves || []).map(s => [s.id, s]));
      for (const sid of HOME_SHELF_PRIORITY) {
        const shelf = shelfById[sid];
        if (!shelf) continue;
        const rows = Data.shelfRows(shelf, 32)
          .filter(r => Data.isPro(r) && Data.isFilm(r) && Data.plays(r) && !used.has(dedupKey(r))).slice(0, 16);
        if (rows.length < 4) continue;
        rows.forEach(r => used.add(dedupKey(r)));
        host.append(shelfSection(shelf.title, shelf.subtitle, rows));
      }
      // Community shelves (archive.org usage signals; index computes them vote-
      // floored). Render from the index shelves map, dedup-aware like the apps.
      const communityShelf = (id, title, subtitle) => {
        const rows = (Data.shelves[id] || []).map(x => Data.byID.get(x))
          .filter(r => r && Data.isPro(r) && Data.isFilm(r) && Data.plays(r) && !used.has(dedupKey(r))).slice(0, 16);
        if (rows.length >= 4) {
          rows.forEach(r => used.add(dedupKey(r)));
          host.append(shelfSection(title, subtitle, rows));
        }
      };
      communityShelf('watching-now', 'Watching Now', 'Most-viewed on archive.org this month');
      communityShelf('community-favorites', 'Community Favorites', 'Most-favorited by archive.org viewers');
      communityShelf('most-discussed', 'Most Discussed', 'The films people are talking about');
      // Hidden Gems — the index's `hidden-gems` shelf, which the pipeline fills
      // from the SAME computed flag the apps query (build_sqlite _mark_hidden_gems).
      // This used to shuffle the popularity TAIL, which is "random obscure", not
      // "high craft, low traffic" — no quality signal took part at all.
      let gems = (Data.shelves['hidden-gems'] || []).map(x => Data.byID.get(x))
        .filter(r => r && Data.isPro(r) && Data.isFilm(r) && Data.plays(r) && !used.has(dedupKey(r))).slice(0, 16);
      if (!gems.length) {
        // Index predates the shelf: fall back to the old tail shuffle so the row
        // degrades rather than disappearing.
        const tail = Data.rows.slice(Math.floor(Data.rows.length * 0.4));
        gems = shuffle(tail.filter(r => Data.isPro(r) && Data.isFilm(r) && Data.plays(r) && !used.has(dedupKey(r)))).slice(0, 16);
      }
      if (gems.length >= 6) {
        gems.forEach(r => used.add(dedupKey(r)));
        host.append(shelfSection('Hidden Gems', 'Lovingly restored, rarely watched', gems));
      }
      // Public Domain Day: this year's newly-free class (currentYear - 95).
      const pdYear = new Date().getFullYear() - 95;
      const pd = shuffle(Data.rows.filter(r =>
        r[2] === pdYear && Data.isPro(r) && Data.isFilm(r) && Data.plays(r) && !used.has(dedupKey(r)))).slice(0, 16);
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
      // Documentary is genre-resolved, so its tile count isn't a contentType
      // tally — count the flagged rows (index col 9) instead.
      counts['documentary'] = Data.rows.reduce(
        (n, r) => n + (r[9] === 1 && r[3] !== 'animation' ? 1 : 0), 0);
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
      // Prefer WIDE backdrops (col 7) so the hero is well-composed art, never a cropped 2:3 poster
      // (owner 2026-06-29). Fall back to the poster pool only if too few backdrops exist (e.g. before
      // the index carries the backdrop column).
      const filmPool = Data.rows.filter(r => Data.isPro(r) && Data.isFilm(r));
      const wide = filmPool.filter(r => r[7]).slice(0, 300);
      const useWide = wide.length >= 4;
      let base = useWide ? wide : filmPool.slice(0, 300);
      // Never marquee a title that doesn't play (index col 8, schema 8 — verified
      // from the video's own bytes, not its metadata). Matches the app gate.
      // Falls back to the ungated pool while probe coverage climbs, and on an
      // older index that has no column 8, so the hero can never go empty.
      const verified = base.filter(r => r[8] === 1);
      if (verified.length >= 4) base = verified;
      const pool = shuffle(base).slice(0, 6);
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
        poster.className = useWide ? 'hero-poster hero-wide' : 'hero-poster';
        poster.alt = '';
        poster.loading = i === 0 ? 'eager' : 'lazy';
        // Ambient mirrors whatever art actually loaded (it shares the HTTP
        // cache entry), so a throttled poster can't strand a blank backdrop.
        wireArt(poster, useWide ? [row[7]] : [Data.poster(row), API.thumbnailURL(id)],
          src => { ambient.style.backgroundImage = `url("${src}")`; },
          () => { const ph = placeholderArt(row); ph.classList.add('hero-poster'); poster.replaceWith(ph); });

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
    ['tv-special', 'TV Specials'],
    ['silent-film', 'Silent'], ['animation', 'Animation'],
    ['short-film', 'Shorts'], ['newsreel', 'Newsreels'],
    ['documentary', 'Documentary'], ['ephemeral', 'Ephemera'],
    ['commercial', 'Commercials'],
  ];
  // TV never appears in the "All" film grid (owner directive 2026-06-18) — both
  // series cards and standalone tv-specials are reachable only via their chips.
  const TV_TYPES = new Set(['tv-series', 'tv-special']);

  const Browse = {
    filtered: [],
    shown: 0,

    render(q) {
      const type = q.get('type') || '';
      const decade = q.get('decade') || '';
      const sort = q.get('sort') || 'pop';
      // Keyword/studio filters (Decision 046) run client-side against the index's
      // search column (r[6]) — no per-row id map, so the committed index stays lean.
      const kw = (q.get('kw') || '').toLowerCase();
      const studio = (q.get('studio') || '').toLowerCase();
      this.controls(type, decade, sort, kw, studio);

      this.filtered = Data.rows.filter(r =>
        Data.matchesCategory(r, type) &&
        (!decade || (r[2] && Math.floor(r[2] / 10) * 10 === Number(decade))) &&
        (!kw || (r[6] && r[6].includes(kw))) &&
        (!studio || (r[6] && r[6].includes(studio))));
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

    controls(type, decade, sort, kw, studio) {
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

      // Keyword + studio facet dropdowns (Decision 046) — most-common names from
      // the index; the long tail is still reachable via the free-text search box.
      // <option> value is lowercased to match the lowercased search column.
      const kwSel = $('browse-keyword');
      kwSel.replaceChildren(new Option('All keywords', ''),
        ...(Data.facets.keywords || []).map(k => new Option(k, k.toLowerCase())));
      kwSel.value = kw;
      kwSel.onchange = () => this.setParam('kw', kwSel.value);

      const stSel = $('browse-studio');
      stSel.replaceChildren(new Option('All studios', ''),
        ...(Data.facets.studios || []).map(s => new Option(s, s.toLowerCase())));
      stSel.value = studio;
      stSel.onchange = () => this.setParam('studio', stSel.value);

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
      if (!qs) { grid.replaceChildren(); this.renderEpisodes([]); $('search-hint').hidden = false; return; }
      $('search-hint').hidden = true;
      const terms = qs.toLowerCase().split(/\s+/).filter(Boolean);
      const hits = [];
      for (const r of Data.rows) {
        // Title + the rich-metadata search blob (Decision 046, schema 6): a film
        // is now findable by a TMDb keyword, an AKA/original title, its writer,
        // or its studio. r[6] is null/absent on unmatched films + older indexes.
        const hay = r[1].toLowerCase() + ' ' + (r[6] || '');
        if (terms.every(t => hay.includes(t))) {
          hits.push(r);
          if (hits.length >= 200) break;
        }
      }
      // Episode items (Decision 045): match the episode title OR its series name.
      // Row: [archiveID, slug, series, season, episode, title, still, year].
      const ehits = [];
      for (const e of Data.episodes) {
        const hay = ((e[5] || '') + ' ' + (e[2] || '')).toLowerCase();
        if (terms.every(t => hay.includes(t))) { ehits.push(e); if (ehits.length >= 60) break; }
      }
      this.renderEpisodes(ehits);

      fillGrid(grid, hits);
      if (!hits.length && !ehits.length) {
        const p = document.createElement('p');
        p.className = 'muted';
        p.textContent = `Nothing matches “${qs}”.`;
        grid.append(p);
      }
    },

    // The "Episodes" section above the film grid. Each row opens the episode's
    // OWN Detail (#/item/{archiveID}) — favorite / playlist / share all work there.
    renderEpisodes(hits) {
      let sec = document.getElementById('search-episodes');
      if (!sec) { sec = document.createElement('div'); sec.id = 'search-episodes'; $('search-grid').before(sec); }
      sec.replaceChildren();
      if (!hits.length) return;
      const h = document.createElement('h2'); h.textContent = 'Episodes'; sec.append(h);
      for (const [aid, , series, season, episode, title, still] of hits) {
        const a = document.createElement('a');
        a.className = 'episode-row';
        a.href = `#/item/${encodeURIComponent(aid)}`;
        const thumb = document.createElement('span'); thumb.className = 'episode-still';
        if (still) { const img = document.createElement('img'); img.loading = 'lazy'; img.alt = ''; img.src = still; thumb.append(img); }
        const meta = document.createElement('div'); meta.className = 'episode-meta';
        const t = document.createElement('strong'); t.textContent = title || 'Episode';
        const num = (season != null && episode != null) ? `S${season} · E${episode}`
          : (episode != null ? `Ep. ${episode}` : '');
        const s = document.createElement('span'); s.textContent = [series, num].filter(Boolean).join(' · ');
        meta.append(t, s); a.append(thumb, meta);
        sec.append(a);
      }
    },
  };

  /* ---------------------------------------------------------------- *
   * Library — favorites + continue watching (IndexedDB, this browser) *
   * ---------------------------------------------------------------- */
  // Cross-device sync (js/drivesync.js): a no-op until the owner sets
  // AW_GOOGLE_CLIENT_ID in index.html. Init after DB exists.
  setTimeout(() => window.AWDriveSync?.init(DB, document.getElementById('library-sync')), 0);

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

      // The complete watch record (Decision 078): everything ever played,
      // newest first — finished or not, resumable or not.
      const all = (await DB.progress()).sort((a, b) => b.at - a.at);
      const hist = all.map(p => Data.byID.get(p.id)
        || [p.id, p.title || p.id, null, '', null]);
      fillGrid($('library-history'), hist);
      $('library-history-empty').hidden = hist.length > 0;
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
        if (!Data.isPro(r) || !Data.isFilm(r)) continue;   // Random Film never lands on TV
        (byType[r[3]] ??= []).push(r);
      }
      const picks = [];
      const seen = new Set();
      for (const t of Object.keys(byType)) {
        const pool = byType[t];
        const pick = pool[Math.floor(Math.random() * pool.length)];
        if (pick && !seen.has(pick[0])) { seen.add(pick[0]); picks.push(pick); }
      }
      const pro = Data.rows.filter(r => Data.isPro(r) && Data.isFilm(r) && !seen.has(r[0]));
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
   * Collections — curated Archive collections (PARITY §3)             *
   * ---------------------------------------------------------------- */
  const Collections = {
    meta: null,
    async loadMeta() {
      if (this.meta) return this.meta;
      try {
        const r = await fetch(new URL('ArchiveWatch/ArchiveWatch/collection_metadata.json',
                                      PAGES_ROOT));
        this.meta = (await r.json()).collections || [];
      } catch { this.meta = []; }
      return this.meta;
    },
    async renderList() {
      const metas = await this.loadMeta();
      const host = $('collections-list');
      const available = metas.filter(m => (Data.collections[m.id] || []).length >= 6);
      host.replaceChildren(...available.map(m => {
        const a = document.createElement('a');
        a.className = 'coll-card';
        a.href = `#/collection/${encodeURIComponent(m.id)}`;
        a.style.setProperty('--coll-accent', m.accent || '#555');
        const t = document.createElement('strong'); t.textContent = m.title;
        const b = document.createElement('span'); b.textContent = m.blurb || '';
        const n = document.createElement('em');
        n.textContent = `${(Data.collections[m.id] || []).length} titles`;
        a.append(t, b, n);
        return a;
      }));
    },
    async renderOne(id) {
      const metas = await this.loadMeta();
      const m = metas.find(x => x.id === id);
      $('collection-title').textContent = m?.title || id;
      $('collection-blurb').textContent = m?.blurb || '';
      const rows = (Data.collections[id] || [])
        .map(aid => Data.byID.get(aid)).filter(Boolean);
      fillGrid($('collection-grid'), rows);
    },
  };

  /* ---------------------------------------------------------------- *
   * Cartoon Mode — kid-leaning animation surface (PARITY §5)          *
   * ---------------------------------------------------------------- */
  const CARTOON_CHARACTERS = [
    ['Popeye', ['popeye']], ['Betty Boop', ['betty boop']],
    ['Porky Pig', ['porky']], ['Mr. Magoo', ['magoo']],
    ['Looney Tunes', ['looney']], ['Felix the Cat', ['felix']],
    ['Daffy Duck', ['daffy']], ['Bosko', ['bosko']],
    ['Mighty Mouse', ['mighty mouse']], ['Casper', ['casper']],
    ['Superman', ['superman']], ['Little Lulu', ['little lulu']],
  ];

  const Cartoons = {
    rendered: false,
    async render() {
      if (this.rendered) return;
      this.rendered = true;
      // Marathon plays the channel-pools cartoon pool (color-emphasized,
      // URLs baked) — the web twin of the apps' marathon lineup.
      $('cartoons-marathon').onclick = async () => {
        const pools = await ChannelsView.loadPools();
        const cartoon = pools?.channels?.find(c => c.id === 'cartoon');
        if (!cartoon) return;
        const queue = shuffle(cartoon.programs).map(p =>
          ({ id: p[0], title: `${p[1]} · Cartoon Marathon`, url: p[3] }));
        if (queue.length) Player.start({ ...queue[0], queue, queueIndex: 0, persist: false });
      };
      const host = $('cartoons-shelves');
      const animation = Data.rows.filter(r => r[3] === 'animation');
      for (const [name, terms] of CARTOON_CHARACTERS) {
        const rows = animation.filter(r =>
          terms.some(t => r[1].toLowerCase().includes(t))).slice(0, 20);
        if (rows.length < 4) continue;
        const sec = document.createElement('section');
        sec.className = 'shelf';
        const h = document.createElement('h2'); h.textContent = name;
        const rail = document.createElement('div'); rail.className = 'shelf-row';
        rail.append(...rows.map(card));
        sec.append(h, rail);
        host.append(sec);
      }
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

    async loadPools() {
      if (!this.data) {
        const r = await fetch(new URL('channel-pools.json', PAGES_ROOT),
                              { signal: AbortSignal.timeout(15000) });
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        this.data = await r.json();
      }
      return this.data;
    },

    async render() {
      const host = $('epg');
      if (this.built) return;
      try {
        await this.loadPools();
      } catch (err) {
        $('channels-error').textContent =
          `The channel guide couldn't load (${err.message}).`;
        $('channels-error').hidden = false;
        return;
      }
      $('channels-create').onclick = () => this.createDialog();
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

      // User channels first (type/era filters over the index — the web can't
      // filter by genre; the create form says so). Program entries resolve
      // their playback URLs lazily at tune time via the detail shards.
      const userChannels = await DB.userChannels().catch(() => []);
      const guideChannels = [
        ...userChannels.map(uc => ({
          id: `user-${uc.id}`, title: uc.name, accent: '#0047FF', user: true,
          programs: Data.rows
            .filter(r => (!uc.type || r[3] === uc.type) &&
                         (!uc.decade || (r[2] && Math.floor(r[2] / 10) * 10 === uc.decade)))
            .slice(0, 150)
            .map(r => [r[0], r[1], null, null, r[3]]),
        })).filter(c => c.programs.length >= 5),
        ...this.data.channels,
      ];
      for (const ch of guideChannels) {
        const slots = Scheduler.schedule(ch.id, ch.programs, now);
        const row = document.createElement('div');
        row.className = 'epg-row';
        const rail = document.createElement('div');
        rail.className = 'epg-rail';
        rail.style.setProperty('--ch-accent', ch.accent);
        const dot = document.createElement('span');
        dot.className = 'epg-dot';
        dot.textContent = ch.user ? '📡' : (CHANNEL_ICONS[ch.id] || '📺');
        const name = document.createElement('span');
        name.textContent = ch.title;
        rail.append(dot, name);
        if (ch.user) {
          rail.style.cursor = 'pointer';
          rail.title = 'Tap to delete this channel';
          rail.onclick = async () => {
            if (!confirm(`Delete the channel “${ch.title}”?`)) return;
            await DB.deleteUserChannel(ch.id.slice(5)).catch(() => {});
            this.built = false;
            this.render();
          };
        }
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
    async tune(ch, slots, slot) {
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
      // User-channel entries carry no baked URL — resolve the first few from
      // the detail shards (shared shard fetches are cached); unplayable items
      // drop out of the queue.
      const unresolved = queue.filter(q => !q.url).slice(0, 12);
      if (unresolved.length) {
        await Promise.all(unresolved.map(async q => {
          const det = await Details.get(q.id).catch(() => null);
          q.url = det?.downloadURL || null;
        }));
      }
      const playable = queue.filter(q => q.url);
      if (!playable.length) return;
      const now = Date.now();
      const startAt = (slot.start <= now && slot.end > now && playable[0].id === slot.prog[0])
        ? Math.max(0, (now - slot.start) / 1000) : 0;
      Player.start({ ...playable[0], queue: playable, queueIndex: 0, startAt, persist: false });
    },

    /** Create-channel dialog: type + era only (the web index has no genre —
        the form says so; the apps' genre channels stay preset-only here). */
    async createDialog() {
      const type = prompt(
        'Channel type — one of: feature-film, silent-film, animation, '
        + 'short-film, newsreel, tv-special (blank = any)') || '';
      const decadeRaw = prompt('Era decade, e.g. 1950 (blank = any)') || '';
      const decade = Number(decadeRaw) || null;
      if (!type && !decade) return;
      const name = prompt('Channel name',
        [decade ? `${decade}s` : '', type.replace(/-/g, ' ')].filter(Boolean).join(' ')
        || 'My Channel');
      if (!name) return;
      await DB.saveUserChannel({
        id: Date.now().toString(36), name: name.trim(),
        type: type.trim() || null, decade, createdAt: Date.now(),
      }).catch(() => {});
      this.built = false;
      this.render();
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

      // Episode item (Decision 045): a link back to the full series.
      const epMeta = Data.episodeMeta.get(id);
      let epLink = document.getElementById('item-series');
      if (!epLink) {
        epLink = document.createElement('a');
        epLink.id = 'item-series';
        epLink.className = 'item-series-link';
        $('item-meta').after(epLink);
      }
      epLink.hidden = !epMeta;
      if (epMeta) {
        epLink.textContent = `Part of ${epMeta.series || 'the series'}`;
        epLink.href = `#/series/${encodeURIComponent(epMeta.slug)}`;
      }
      $('item-desc').textContent = '';
      $('item-tagline').textContent = '';
      $('item-tagline').hidden = true;
      $('item-facts').replaceChildren();
      $('item-facts').hidden = true;
      $('item-cast').replaceChildren();
      $('item-cast').hidden = true;
      $('item-community').replaceChildren();
      $('item-community').hidden = true;
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
        if (det.tagline) {
          $('item-tagline').textContent = det.tagline;
          $('item-tagline').hidden = false;
        }
        if (det.synopsis) $('item-desc').textContent = det.synopsis;
        this.factsRow(det);
        this.castRow(det);
        this.communityRow(det);
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
      if (det.director) people.push({ name: det.director, role: 'Director', profilePath: det.directorProfilePath || null });
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

    /** Rich-metadata facts (Decision 046): writer / studios / franchise / awards
        and the lesser crew, surfaced only when present. Studios + franchise link
        into Browse so a fact becomes a door to more of the same. */
    factsRow(det) {
      const dl = $('item-facts');
      dl.replaceChildren();
      const addText = (label, value) => {
        if (!value) return;
        const dt = document.createElement('dt'); dt.textContent = label;
        const dd = document.createElement('dd'); dd.textContent = value;
        dl.append(dt, dd);
      };
      const addLinks = (label, values, href) => {
        const list = (values || []).filter(Boolean);
        if (!list.length) return;
        const dt = document.createElement('dt'); dt.textContent = label;
        const dd = document.createElement('dd');
        list.forEach((v, i) => {
          if (i) dd.append(', ');
          const a = document.createElement('a');
          a.href = href(v); a.textContent = v;
          dd.append(a);
        });
        dl.append(dt, dd);
      };
      addText('Writer', det.writer);
      addText('Composer', det.composer);
      addText('Cinematography', det.cinematographer);
      addLinks('Studio', det.studios,
        v => `#/browse?studio=${encodeURIComponent(v.toLowerCase())}`);
      if (det.franchise) {
        addLinks('Series', [det.franchise],
          v => `#/search?q=${encodeURIComponent(v)}`);
      }
      addText('Original title', det.originalTitle);
      addText('Awards', det.awards);
      dl.hidden = !dl.children.length;
    },

    /** archive.org community stats + pipeline-filtered reviews (P2). The reviews
        are already filtered upstream (comment_fit.py) to genuine reviews of the
        title — never file-quality or inappropriate comments. */
    communityRow(det) {
      const host = $('item-community');
      const c = det && det.community;
      if (!c) { host.hidden = true; return; }
      host.replaceChildren();
      const compact = n => n >= 1e6 ? (n / 1e6).toFixed(1) + 'M'
        : n >= 1e3 ? (n / 1e3).toFixed(1) + 'K' : String(n);
      const stats = [];
      if (c.r) stats.push(`★ ${c.r.toFixed(1)}`);
      if (c.v) stats.push(`▶ ${compact(c.v)} views`);
      if (c.f) stats.push(`♥ ${compact(c.f)} favorites`);
      if (stats.length) {
        const p = document.createElement('p');
        p.className = 'muted community-stats';
        p.textContent = stats.join('   ');
        host.append(p);
      }
      const reviews = c.rv || [];
      if (reviews.length) {
        const h = document.createElement('h2');
        h.textContent = 'From archive.org viewers';
        host.append(h);
        for (const [stars, title, body, reviewer, date] of reviews.slice(0, 6)) {
          const card = document.createElement('div');
          card.className = 'review-card';
          const head = [stars ? '★'.repeat(stars) : '', title || ''].filter(Boolean).join('  ');
          if (head) {
            const t = document.createElement('p');
            t.className = 'review-head';
            t.textContent = head;
            card.append(t);
          }
          if (body) {
            const b = document.createElement('p');
            b.className = 'review-body';
            b.textContent = body;
            card.append(b);
          }
          const m = document.createElement('p');
          m.className = 'review-meta muted';
          m.textContent = (reviewer || 'Archive viewer') + (date ? ` · ${date}` : '');
          card.append(m);
          host.append(card);
        }
      }
      host.hidden = !host.children.length;
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
            `package=com.archivewatch.app;S.browser_fallback_url=` +
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

    /** More Like This (apps' related query): same category, then YEAR proximity (±10y),
        then POPULARITY (index order). No shuffle — that made it random on every visit.
        (colorMode isn't in the index, so the apps' color tiebreak is app-only.) */
    related(row) {
      const [id, , year, type] = row;
      const host = $('item-related');
      const rows = Data.rows
        .filter(r => r[0] !== id && r[3] === type && Data.isPro(r))
        .map((r, idx) => ({
          r, idx,
          near: (year && r[2] && Math.abs(r[2] - year) <= 10) ? 0 : 1,
          dy: (year && r[2]) ? Math.abs(r[2] - year) : 9999,
        }))
        .sort((a, b) => a.near - b.near || a.dy - b.dy || a.idx - b.idx)
        .slice(0, 12)
        .map(s => s.r);
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
      $('series-share').onclick = async () => {
        const url = `${PAGES_ROOT}series/${encodeURIComponent(slug)}`;
        try {
          if (navigator.share) { await navigator.share({ title: $('series-title').textContent, url }); return; }
        } catch { /* fall through */ }
        try {
          await navigator.clipboard.writeText(url);
          $('series-share').textContent = 'Link copied ✓';
          setTimeout(() => { $('series-share').textContent = 'Share'; }, 1600);
        } catch { /* no clipboard */ }
      };

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
      const rows = playable.map((ep) => {
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
        // Open the episode's OWN Detail (favorite / playlist / share / play, Decision 045) —
        // like any film. The Detail's play resolves the downloadURL (baked or via metadata).
        b.onclick = () => { location.hash = `#/item/${encodeURIComponent(ep.archiveID)}`; };
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

  /** Attach one subtitle track, fetching it into a same-origin blob first.
   *
   *  ⚠️ A cross-origin <track> silently fails: the element needs `crossorigin`
   *  on the MEDIA element, and we cannot set that — archive.org 302s video to a
   *  storage node that sends NO CORS header (verified; Decision 029), so
   *  `crossorigin` on <video> would break PLAYBACK, which is far worse than
   *  missing subtitles.
   *
   *  This matters most for the PACKAGED TV apps (webOS .ipk / Tizen .wgt),
   *  where the page is served from a local app origin, so the remote VTT is
   *  ALWAYS cross-origin and subtitles would never appear. On archivewatch.org
   *  itself the VTT happens to be same-origin, which is exactly why this hid.
   *
   *  The VTT host does send CORS, so fetch() works and a blob: URL is
   *  same-origin by construction. Also converts SRT, for the handful of
   *  captions the pipeline has not pre-converted. */
  async function addSubtitleTrack(video, id, lang, label, url) {
    const tr = document.createElement('track');
    // Keep the ORIGINAL https URL alongside the blob. The blob is what makes
    // the local <track> work (a cross-origin track fails silently), but a blob
    // is scoped to THIS document — a Cast receiver handed one cannot fetch it.
    // cast-sender.js sends this instead, and the receiver, served from the same
    // origin as the VTT, loads it directly.
    tr.dataset.awSrc = url;
    tr.kind = 'subtitles';
    tr.srclang = lang || 'en';
    tr.label = label || (lang || 'en').toUpperCase();
    if (lang === 'en') tr.default = true;
    video.appendChild(tr);
    try {
      const res = await fetch(url, { credentials: 'omit' });
      if (!res.ok) return;
      let text = await res.text();
      if (!/^\uFEFF?WEBVTT/.test(text)) text = srtToVtt(text);
      // Player may have moved on while this was in flight.
      if (!video.isConnected || video.dataset.awItem !== id) return;
      tr.src = URL.createObjectURL(new Blob([text], { type: 'text/vtt' }));
    } catch { /* no subtitles is a degradation, never an error */ }
  }

  /** Minimal SRT -> WebVTT: header, and comma decimal separators to dots. */
  function srtToVtt(srt) {
    return 'WEBVTT\n\n' + srt
      .replace(/\r+/g, '')
      .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');
  }

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
      video.querySelectorAll('track').forEach(t => t.remove());   // clear last title's subs
      video.dataset.awItem = id;
      video.src = url;

      // Title + description overlay (fades with the controls — see syncOverlay).
      $('player-overlay-title').textContent = title;
      $('player-overlay-desc').textContent = '';
      Details.get(id).then(det => {
        if (this.ctx?.id !== id) return;
        if (det?.synopsis) $('player-overlay-desc').textContent = det.synopsis;
        // Native subtitles (Decision 039): same-origin VTT on Pages → a <track>
        // the browser lists in its own CC menu. English defaults on.
        for (const [lang, label, vttURL] of (det?.captions || [])) {
          if (!vttURL) continue;
          addSubtitleTrack(video, id, lang, label, vttURL);
        }
      }).catch(() => {});
      this.syncOverlay();

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
      video.playbackRate = Number(localStorage.getItem('aw_rate') || 1);
      $('player-rate').value = String(video.playbackRate);
      try { await video.play(); } catch { /* user gesture rules; controls remain */ }

      // Lock-screen / media-key controls (the MediaSession parity row).
      if ('mediaSession' in navigator) {
        navigator.mediaSession.metadata = new MediaMetadata({
          title, artist: 'Archive Watch',
        });
        navigator.mediaSession.setActionHandler('play', () => video.play());
        navigator.mediaSession.setActionHandler('pause', () => video.pause());
        navigator.mediaSession.setActionHandler('seekbackward',
          () => { video.currentTime = Math.max(0, video.currentTime - 10); });
        navigator.mediaSession.setActionHandler('seekforward',
          () => { video.currentTime += 10; });
        const hasNext = queue && queueIndex + 1 < queue.length;
        navigator.mediaSession.setActionHandler('nexttrack', hasNext ? () => {
          this.persist();
          this.start({ ...queue[queueIndex + 1], queue,
                       queueIndex: queueIndex + 1, persist });
        } : null);
        navigator.mediaSession.setActionHandler('previoustrack',
          queue && queueIndex > 0 ? () => {
            this.persist();
            this.start({ ...queue[queueIndex - 1], queue,
                         queueIndex: queueIndex - 1, persist });
          } : null);
      }

      clearInterval(this.saveTimer);
      this.saveTimer = setInterval(() => this.persist(), 10000);

      video.onerror = () => this.recover('error');   // a real error needs the full reset
      this._lastBufferedEnd = 0;
      video.onwaiting = () => this.onStall();
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

    /** Two-stage, buffer-preserving stall recovery. A full `recover()` throws
        away the entire buffer and pays a fresh 302 + node handshake, so a flaky
        connection thrashes if we do it on every 12s stall. Instead:
        (1) if bytes are STILL arriving (networkState LOADING + buffered end
            advancing), just wait — the download is healthy, don't touch it;
        (2) otherwise try a lightweight nudge (currentTime += 0.1 + play), which
            often un-sticks a transient underrun WITHOUT dropping the buffer;
        (3) only if still stalled after a short window fall through to the full
            src-reset recover('stall'). */
    onStall() {
      clearTimeout(this.stallTimer);
      const video = $('video');
      if (!this.ctx || !video.src) return;
      const bufferedEnd = video.buffered.length
        ? video.buffered.end(video.buffered.length - 1) : 0;
      // Stage 1 — bytes still flowing and the buffer is growing: extend, wait.
      if (video.networkState === HTMLMediaElement.NETWORK_LOADING &&
          bufferedEnd > (this._lastBufferedEnd || 0) + 0.01) {
        this._lastBufferedEnd = bufferedEnd;
        this.stallTimer = setTimeout(() => this.onStall(), 2000);
        return;
      }
      this._lastBufferedEnd = bufferedEnd;
      // Stage 2 — cheap nudge (no buffer drop, no fresh 302).
      try { video.currentTime = video.currentTime + 0.1; } catch { /* seeking not ready */ }
      video.play().catch(() => { /* user-gesture rules; controls remain */ });
      // Stage 3 — still stuck after a short window → full buffer-dropping reset.
      this.stallTimer = setTimeout(() => this.recover('stall'), 4000);
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
      window.AWDriveSync?.nudge();
    },

    /** Show the title/description overlay and mirror the native controls'
        activity timer: visible on pointer/touch activity and while paused,
        auto-hiding ~3.2s after the last interaction during playback. HTML5
        `<video controls>` exposes no controls-visibility event, so we mirror
        the same user-activity signal the browser uses (web-platform idiom). */
    overlayHideTimer: null,
    syncOverlay() {
      const ov = $('player-overlay');
      const video = $('video');
      if (!ov) return;
      const show = () => {
        ov.classList.remove('hidden');
        clearTimeout(this.overlayHideTimer);
        if (!video.paused) {
          this.overlayHideTimer = setTimeout(() => ov.classList.add('hidden'), 3200);
        }
      };
      if (!this._overlayBound) {
        this._overlayBound = true;
        const stage = ov.parentElement;
        ['pointermove', 'pointerdown', 'touchstart'].forEach(ev =>
          stage.addEventListener(ev, show, { passive: true }));
        video.addEventListener('pause', show);   // controls stay up while paused
        video.addEventListener('play', show);     // then auto-hide via the timer
      }
      show();
    },

    close() {
      const video = $('video');
      this.persist();
      clearInterval(this.saveTimer);
      clearTimeout(this.stallTimer);
      clearTimeout(this.overlayHideTimer);
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

    // Playback speed (persisted) + Picture-in-Picture (Chrome and Safari APIs).
    $('player-rate').onchange = () => {
      const rate = Number($('player-rate').value) || 1;
      $('video').playbackRate = rate;
      localStorage.setItem('aw_rate', String(rate));
    };
    const video = $('video');
    const pipSupported = document.pictureInPictureEnabled
      || typeof video.webkitSetPresentationMode === 'function';
    if (pipSupported) {
      $('player-pip').hidden = false;
      $('player-pip').onclick = () => {
        if (typeof video.webkitSetPresentationMode === 'function') {
          video.webkitSetPresentationMode(
            video.webkitPresentationMode === 'picture-in-picture'
              ? 'inline' : 'picture-in-picture');
        } else if (document.pictureInPictureElement) {
          document.exitPictureInPicture().catch(() => {});
        } else {
          video.requestPictureInPicture().catch(() => {});
        }
      };
    }

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

    // Cold-resume refresh: a tab or installed PWA left open for days otherwise
    // renders forever from the rows parsed at first boot. Never re-render while
    // the player is open — that would interrupt playback; the data still
    // updates and the next route() picks it up.
    let resuming = false;
    let swRegistration = null;
    const resumeRefresh = async () => {
      if (resuming || document.visibilityState !== 'visible') return;
      resuming = true;
      try {
        swRegistration?.update().catch(() => {});   // pick up a new build
        if (await Data.reloadIfStale() && !$('player').open) route();
      } finally {
        resuming = false;
      }
    };
    document.addEventListener('visibilitychange', resumeRefresh);
    window.addEventListener('pageshow', resumeRefresh);
    window.addEventListener('online', resumeRefresh);

    // Packaged TV apps (file://) ship their shell inside the package and have
    // no sw.js — registering would only produce a rejected promise.
    if ('serviceWorker' in navigator && /^https?:$/.test(location.protocol)) {
      navigator.serviceWorker.register('sw.js').then(reg => {
        // Long-open tabs never re-check for a new worker on their own. Ask on
        // every resume (cheap — the browser 304s), alongside the catalog reload.
        swRegistration = reg;
        // When a new worker takes over, the page is still running the OLD code.
        // Reload once so they match — but NEVER mid-film: the player dialog
        // holds the video, and reloading would kill playback. A user who is
        // watching gets the new build on their next visit instead.
        let reloading = false;
        navigator.serviceWorker.addEventListener('controllerchange', () => {
          if (reloading || $('player').open) return;
          reloading = true;
          location.reload();
        });
      }).catch(() => { /* http or old browser */ });
    }
  }

  boot();
})();
