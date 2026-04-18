/**
 * Archive Watch — Seed Catalog Generator (browser)
 *
 * For each dynamic shelf declared in featured.json:
 *   1. Call Archive scrape to get the top N items.
 *   2. For each Archive ID, fetch metadata + pick the best video derivative.
 *   3. If a TMDb bearer token is available, enrich with TMDb detail
 *      (poster, backdrop, credits, runtime).
 *   4. Merge into the catalog output keyed by archiveID.
 *
 * Curated items from `type: "curated"` shelves (Editor's Picks) are
 * also included — those are the ones we've hand-picked.
 *
 * Output schema (catalog.json):
 *   {
 *     version, generatedAt, generator,
 *     stats: { totalItems, itemsWithIMDb, itemsWithTMDb, itemsWithPoster, itemsPlayable },
 *     items: [
 *       { archiveID, title, year, runtime, synopsis,
 *         collections[], subjects[], mediatype,
 *         imdbID, tmdbID, wikidataQID,
 *         videoFile: { name, format, tier },
 *         posterURL, backdropURL, artworkSource,
 *         contentType, genres[], countries[], decade,
 *         cast[], director,
 *         shelves: [shelfID...] }
 *     ]
 *   }
 */
(function () {
  'use strict';

  const $ = (id) => document.getElementById(id);

  // --- State ------------------------------------------------------

  let featured = null;
  let registry = null;
  let running = false;
  let stopRequested = false;
  let outputBlobURL = null;
  let catalog = null;

  // --- Logging ----------------------------------------------------

  function log(kind, msg) {
    const ol = $('bc-log');
    const tpl = document.getElementById('tpl-log-row');
    const node = tpl.content.cloneNode(true);
    const li = node.querySelector('.bc-log-row');
    li.dataset.kind = kind;
    const now = new Date();
    const hh = String(now.getHours()).padStart(2, '0');
    const mm = String(now.getMinutes()).padStart(2, '0');
    const ss = String(now.getSeconds()).padStart(2, '0');
    node.querySelector('.bc-log-time').textContent = `${hh}:${mm}:${ss}`;
    node.querySelector('.bc-log-msg').textContent = msg;
    ol.appendChild(node);
    ol.scrollTop = ol.scrollHeight;
  }

  function updateStats(partial) {
    const s = $('bc-stats');
    s.textContent = partial;
  }

  function updateBar(percent) {
    $('bc-bar-fill').style.width = Math.max(0, Math.min(100, percent)) + '%';
  }

  // --- TMDb mini-client (browser) --------------------------------

  const TMDB = (() => {
    const BASE = 'https://api.themoviedb.org/3';
    const IMG  = 'https://image.tmdb.org/t/p';
    let token = null;
    let lastCallAt = 0;
    const MIN_SPACING = 80; // ms between calls — TMDb allows ~40 r/s

    function setToken(t) { token = (t || '').trim() || null; }
    function hasToken()  { return !!token; }

    async function space() {
      const since = Date.now() - lastCallAt;
      if (since < MIN_SPACING) await new Promise(r => setTimeout(r, MIN_SPACING - since));
      lastCallAt = Date.now();
    }

    async function get(path, params = {}) {
      if (!token) throw new Error('TMDb: no token');
      await space();
      const url = new URL(BASE + path);
      Object.entries(params).forEach(([k, v]) => { if (v != null) url.searchParams.set(k, v); });
      const resp = await fetch(url, {
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' }
      });
      if (resp.status === 429) {
        const retryAfter = parseInt(resp.headers.get('Retry-After') || '1', 10);
        await new Promise(r => setTimeout(r, retryAfter * 1000));
        return get(path, params);
      }
      if (!resp.ok) throw new Error(`TMDb ${resp.status}: ${resp.statusText}`);
      return resp.json();
    }

    async function findByIMDb(imdbID) {
      const res = await get(`/find/${imdbID}`, { external_source: 'imdb_id', language: 'en-US' });
      return (res.movie_results && res.movie_results[0]) || null;
    }

    async function movieDetail(tmdbID) {
      return get(`/movie/${tmdbID}`, {
        language: 'en-US',
        append_to_response: 'credits,images,external_ids',
        include_image_language: 'en,null'
      });
    }

    function posterURL(path, size = 'w780') { return path ? `${IMG}/${size}${path}` : null; }
    function backdropURL(path, size = 'w1280') { return path ? `${IMG}/${size}${path}` : null; }

    return { setToken, hasToken, findByIMDb, movieDetail, posterURL, backdropURL };
  })();

  // --- Classification helpers ------------------------------------

  function parseYear(meta) {
    const y = meta.year || meta.date;
    if (!y) return null;
    const n = parseInt(String(y).slice(0, 4), 10);
    return isNaN(n) ? null : n;
  }

  function parseRuntimeSeconds(runtime) {
    if (!runtime) return null;
    const parts = String(runtime).split(':').map(s => parseInt(s, 10));
    if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    if (parts.length === 2) return parts[0] * 60 + parts[1];
    if (parts.length === 1 && !isNaN(parts[0])) return parts[0];
    return null;
  }

  function decadeFromYear(y) {
    if (!y) return null;
    return Math.floor(y / 10) * 10;
  }

  function dominantCollection(collectionsList) {
    if (!registry || !registry.collections) return null;
    let best = null;
    for (const c of collectionsList) {
      const info = registry.collections[c.toLowerCase()];
      if (!info) continue;
      if (!best || info.weight > best.info.weight) {
        best = { id: c.toLowerCase(), info };
      }
    }
    return best;
  }

  function classifyContentType(collectionsList, subjects, runtimeSec, year) {
    const dom = dominantCollection(collectionsList);
    if (dom && dom.info.category) return dom.info.category;

    const cols = collectionsList.map(c => c.toLowerCase());
    if (cols.some(c => c.includes('classic_tv')))   return 'tv-series';
    if (cols.some(c => c.includes('silent')))       return 'silent-film';
    if (cols.some(c => c.includes('cartoon') || c.includes('animation'))) return 'animation';
    if (cols.some(c => c.includes('prelinger') || c.includes('ephemeral'))) return 'ephemeral';
    if (cols.some(c => c.includes('newsreel') || c.includes('news-and-public'))) return 'newsreel';

    if (year && year < 1928) return 'silent-film';
    if (subjects.some(s => s.toLowerCase().includes('documentary'))) return 'documentary';
    if (runtimeSec != null) {
      if (runtimeSec < 40 * 60) return 'short-film';
      if (runtimeSec > 55 * 60) return 'feature-film';
    }
    return 'feature-film';
  }

  function subjectToGenres(subjects) {
    if (!registry || !registry.subjectKeywordMap) return [];
    const out = new Set();
    const kwMap = registry.subjectKeywordMap;
    for (const subject of subjects) {
      const s = String(subject).toLowerCase();
      for (const [kw, genre] of Object.entries(kwMap)) {
        if (s.includes(kw)) { out.add(genre); break; }
      }
    }
    return [...out];
  }

  // TMDb's movie genre IDs → our Genre rawValues. Stable since v3.
  const TMDB_GENRE_MAP = {
    28: 'action', 16: 'animation', 35: 'comedy', 80: 'crime',
    99: 'documentary', 18: 'drama', 10751: 'family', 14: 'fantasy',
    27: 'horror', 10402: 'musical', 9648: 'mystery', 10749: 'romance',
    878: 'sci-fi', 53: 'thriller', 10752: 'war', 37: 'western'
  };

  // --- Main loop --------------------------------------------------

  async function loadInputs() {
    log('info', 'Loading featured.json + collection registry…');
    const [feat, reg] = await Promise.all([
      fetch('featured.json?ts=' + Date.now()).then(r => r.json()),
      fetch('docs/taxonomy/collections.json?ts=' + Date.now()).then(r => r.json()).catch(() => null)
    ]);
    featured = feat;
    registry = reg;
    log('success', `Loaded ${feat.shelves?.length || 0} shelves, ${Object.keys(reg?.collections || {}).length} collections.`);
  }

  async function build() {
    if (running) return;
    running = true;
    stopRequested = false;
    catalog = {
      version: 1,
      generatedAt: new Date().toISOString(),
      generator: 'browser/build-catalog.html',
      stats: { totalItems: 0, itemsWithIMDb: 0, itemsWithTMDb: 0, itemsWithPoster: 0, itemsPlayable: 0 },
      items: []
    };
    $('bc-start').disabled = true;
    $('bc-stop').disabled = false;
    $('bc-download').disabled = true;
    updateBar(0);

    try {
      await loadInputs();

      const perShelf   = parseInt($('bc-per-shelf').value, 10) || 24;
      const concurrency = parseInt($('bc-concurrency').value, 10) || 2;
      const skipBroken  = $('bc-skip-broken').value === 'true';

      // Collect every (archiveID, sourceShelfID) we want in the catalog.
      log('info', 'Resolving shelves…');
      const picks = await collectArchiveIDs(featured, perShelf);
      log('success', `Resolved ${picks.size} unique Archive IDs across ${featured.shelves.length} shelves.`);

      const token = ($('bc-tmdb').value || '').trim();
      if (token) {
        TMDB.setToken(token);
        try { localStorage.setItem('aw_tmdb_token', token); } catch {}
        log('info', 'TMDb token present — will enrich items with IMDb cross-refs.');
      } else {
        log('warn', 'No TMDb token — catalog will ship Archive-only; app will enrich at runtime.');
      }

      // Enrich each pick, one at a time within a simple concurrency pool.
      const ids = [...picks.keys()];
      const total = ids.length;
      let done = 0;

      const pool = Array.from({ length: concurrency }, () => worker());
      async function worker() {
        while (!stopRequested) {
          const idx = done;
          if (idx >= total) return;
          done++;
          const archiveID = ids[idx];
          const shelves = [...(picks.get(archiveID) || [])];
          try {
            const item = await enrichOne(archiveID, shelves, skipBroken);
            if (item) {
              catalog.items.push(item);
              bumpStats(item);
            }
          } catch (err) {
            log('error', `${archiveID} — ${err.message}`);
          }
          updateBar(((idx + 1) / total) * 100);
          updateStats(
            `${done}/${total} processed · ${catalog.items.length} kept · ` +
            `IMDb ${catalog.stats.itemsWithIMDb} · TMDb ${catalog.stats.itemsWithTMDb} · ` +
            `posters ${catalog.stats.itemsWithPoster}`
          );
        }
      }
      await Promise.all(pool);

      if (stopRequested) {
        log('warn', `Stopped early. ${catalog.items.length} items built.`);
      } else {
        log('success', `Finished. ${catalog.items.length} items in the catalog.`);
      }

      catalog.stats.totalItems = catalog.items.length;
      preparedDownload();
    } catch (err) {
      log('error', `Build failed: ${err.message}`);
    } finally {
      running = false;
      $('bc-start').disabled = false;
      $('bc-stop').disabled = true;
    }
  }

  function bumpStats(item) {
    if (item.imdbID)       catalog.stats.itemsWithIMDb++;
    if (item.tmdbID)       catalog.stats.itemsWithTMDb++;
    if (item.posterURL)    catalog.stats.itemsWithPoster++;
    if (item.videoFile)    catalog.stats.itemsPlayable++;
  }

  async function collectArchiveIDs(featured, perShelf) {
    // Map archiveID -> Set of shelf ids that reference it.
    const byID = new Map();
    const add = (id, shelfID) => {
      if (!id) return;
      if (!byID.has(id)) byID.set(id, new Set());
      byID.get(id).add(shelfID);
    };

    for (const shelf of (featured.shelves || [])) {
      if (stopRequested) break;

      if (shelf.type === 'curated' && Array.isArray(shelf.items)) {
        for (const it of shelf.items) add(it.archiveID, shelf.id);
        log('info', `  ${shelf.id}: ${shelf.items.length} curated`);
        continue;
      }

      if (shelf.type === 'dynamic' && shelf.query) {
        try {
          const { items } = await API.scrape({
            q: shelf.query,
            sorts: shelf.sort || ['-downloads'],
            count: Math.min(shelf.limit || perShelf, perShelf),
            fields: ['identifier']
          });
          items.forEach(it => add(it.identifier, shelf.id));
          log('info', `  ${shelf.id}: ${items.length} dynamic (${shelf.sort?.[0] || '-downloads'})`);
        } catch (err) {
          log('error', `  ${shelf.id}: scrape failed — ${err.message}`);
        }
      }
    }
    return byID;
  }

  async function enrichOne(archiveID, shelves, skipBroken) {
    // Step 1: Archive metadata + derivative picker.
    const metaResponse = await API.fetchMetadata(archiveID);
    const summary = API.summarize(metaResponse);
    if (skipBroken && !summary.hasPlayable) {
      log('warn', `${archiveID}: no playable derivative, skipping.`);
      return null;
    }

    const collections = summary.collections || [];
    const subjects    = summary.subjects    || [];
    const runtimeSec  = parseRuntimeSeconds(metaResponse.metadata?.runtime);
    const year        = summary.year;

    const item = {
      archiveID: summary.identifier || archiveID,
      title: summary.title,
      year,
      decade: decadeFromYear(year),
      runtimeSeconds: runtimeSec,
      synopsis: summary.description || null,
      collections,
      subjects,
      mediatype: summary.mediatype,
      imdbID: summary.imdbID || null,
      tmdbID: null,
      wikidataQID: null,
      videoFile: summary.videoFile || null,
      posterURL: null,
      backdropURL: null,
      artworkSource: summary.videoFile ? 'none' : 'archive',
      contentType: classifyContentType(collections, subjects, runtimeSec, year),
      genres: subjectToGenres(subjects),
      countries: [],
      cast: [],
      director: null,
      shelves
    };

    // Step 2: TMDb enrichment if token + IMDb ID.
    if (TMDB.hasToken() && summary.imdbID) {
      try {
        const match = await TMDB.findByIMDb(summary.imdbID);
        if (match && match.id) {
          const detail = await TMDB.movieDetail(match.id);
          applyTMDbDetail(item, detail);
          log('success', `${archiveID}: enriched (TMDb #${detail.id}).`);
        } else {
          log('warn', `${archiveID}: IMDb ${summary.imdbID} — no TMDb match.`);
        }
      } catch (err) {
        log('error', `${archiveID}: TMDb error — ${err.message}`);
      }
    } else if (!summary.imdbID) {
      // Archive-only fallback for artwork.
      item.posterURL = API.thumbnailURL(archiveID);
      item.artworkSource = 'archive';
    } else {
      // Have IMDb but no token; let the runtime service enrich.
      item.posterURL = API.thumbnailURL(archiveID);
      item.artworkSource = 'archive';
    }

    return item;
  }

  function applyTMDbDetail(item, detail) {
    item.tmdbID = detail.id;
    if (detail.title) item.title = detail.title;
    if (detail.overview) item.synopsis = detail.overview;
    if (detail.runtime) item.runtimeSeconds = detail.runtime * 60;
    if (detail.external_ids?.wikidata_id) item.wikidataQID = detail.external_ids.wikidata_id;

    // Pick the best poster/backdrop from the images bag.
    const images = detail.images || {};
    const bestPoster = pickBestImage(images.posters, ['en', null]);
    const bestBackdrop = pickBestImage(images.backdrops, [null, 'en']);
    const posterPath = bestPoster?.file_path || detail.poster_path;
    const backdropPath = bestBackdrop?.file_path || detail.backdrop_path;
    if (posterPath)   item.posterURL   = TMDB.posterURL(posterPath);
    if (backdropPath) item.backdropURL = TMDB.backdropURL(backdropPath);
    item.artworkSource = 'tmdb';

    if (detail.genres?.length) {
      item.genres = [...new Set(detail.genres.map(g => TMDB_GENRE_MAP[g.id]).filter(Boolean))];
    }
    if (detail.production_countries?.length) {
      item.countries = detail.production_countries.map(c => c.iso_3166_1);
    }
    if (detail.credits?.cast?.length) {
      item.cast = detail.credits.cast
        .slice()
        .sort((a, b) => (a.order ?? 9999) - (b.order ?? 9999))
        .slice(0, 15)
        .map(c => ({ name: c.name, character: c.character || null, order: c.order ?? 0, profilePath: c.profile_path || null }));
    }
    if (detail.credits?.crew?.length) {
      const dir = detail.credits.crew.find(c => (c.job || '').toLowerCase() === 'director');
      if (dir) item.director = dir.name;
    }
  }

  function pickBestImage(pool, prefLangs) {
    if (!pool || !pool.length) return null;
    for (const lang of prefLangs) {
      const bucket = pool.filter(p => p.iso_639_1 === lang);
      if (bucket.length) {
        return bucket.slice().sort((a, b) => {
          const av = (a.vote_average || 0), ac = (a.vote_count || 0);
          const bv = (b.vote_average || 0), bc = (b.vote_count || 0);
          if (bv !== av) return bv - av;
          return bc - ac;
        })[0];
      }
    }
    return pool[0];
  }

  function preparedDownload() {
    if (outputBlobURL) URL.revokeObjectURL(outputBlobURL);
    const blob = new Blob([JSON.stringify(catalog, null, 2)], { type: 'application/json' });
    outputBlobURL = URL.createObjectURL(blob);
    $('bc-download').disabled = false;
  }

  function handleDownload() {
    if (!outputBlobURL) return;
    const a = document.createElement('a');
    a.href = outputBlobURL;
    a.download = 'catalog.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    log('info', 'catalog.json downloaded. Commit it to the repo root, then it will ship inside the tvOS app bundle.');
  }

  // --- Wiring -----------------------------------------------------

  function init() {
    try {
      const saved = localStorage.getItem('aw_tmdb_token');
      if (saved) $('bc-tmdb').value = saved;
    } catch {}

    $('bc-start').addEventListener('click', build);
    $('bc-stop').addEventListener('click', () => {
      stopRequested = true;
      log('warn', 'Stop requested — finishing current item.');
    });
    $('bc-download').addEventListener('click', handleDownload);

    log('info', 'Ready.');
  }

  init();
})();
