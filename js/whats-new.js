/**
 * Archive Watch — What's New Curation Ticker
 *
 * Surfaces recently uploaded items from each major Archive collection
 * so the curator can spot fresh material to add to Editor's Picks.
 *
 * Storage:
 *   - localStorage["aw_seen"]      — Set of Archive IDs the curator has dismissed
 *   - localStorage["aw_pending"]   — IDs queued for the dashboard's Editor's Picks shelf
 *
 * The dashboard reads aw_pending on its next load and offers to merge.
 */
(function () {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const escHtml = (s) => { const d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; };

  // ---- State -----------------------------------------------------

  let activeCollection = 'feature_films';
  let seen = loadSeen();

  function loadSeen() {
    try {
      const raw = localStorage.getItem('aw_seen');
      return new Set(raw ? JSON.parse(raw) : []);
    } catch { return new Set(); }
  }
  function saveSeen() {
    localStorage.setItem('aw_seen', JSON.stringify([...seen]));
  }

  function loadPending() {
    try {
      const raw = localStorage.getItem('aw_pending');
      return raw ? JSON.parse(raw) : [];
    } catch { return []; }
  }
  function savePending(arr) {
    localStorage.setItem('aw_pending', JSON.stringify(arr));
  }
  function queueForPicks(archiveID) {
    const list = loadPending();
    if (list.includes(archiveID)) return false;
    list.push(archiveID);
    savePending(list);
    return true;
  }

  // ---- Loaders ---------------------------------------------------

  async function loadFeed() {
    const list  = $('wn-list');
    const status = $('wn-status');
    const window = parseInt($('wn-window').value, 10);
    const limit  = parseInt($('wn-limit').value, 10);
    const showSeen = $('wn-show-seen').value === 'true';

    list.innerHTML = '';
    status.textContent = `Fetching recent ${activeCollection}…`;
    status.classList.add('is-loading');

    try {
      // We sort by publicdate descending and rely on the API surface
      // to give us the freshest items. The window filter is applied
      // client-side after the response (Archive's date filtering in
      // the q-string is brittle).
      const sinceTs = Date.now() - window * 24 * 60 * 60 * 1000;
      const sinceDate = new Date(sinceTs).toISOString().slice(0, 10);

      const { items } = await API.scrape({
        q: `mediatype:movies AND collection:${activeCollection} AND publicdate:[${sinceDate} TO null]`,
        sorts: ['-publicdate'],
        count: limit,
        fields: ['identifier', 'title', 'creator', 'year', 'date', 'publicdate', 'description', 'collection', 'subject', 'downloads']
      });

      const filtered = items.filter(it => showSeen || !seen.has(it.identifier));
      renderItems(filtered, items.length);

      const seenCount = items.length - filtered.length;
      const tag = seenCount > 0 && !showSeen ? ` (${seenCount} hidden as seen)` : '';
      status.classList.remove('is-loading');
      status.textContent = `${filtered.length} items in ${activeCollection}${tag}`;
      $('wn-stats').textContent = `seen: ${seen.size} · pending: ${loadPending().length}`;
    } catch (err) {
      status.classList.remove('is-loading');
      status.textContent = `Error: ${err.message}. Try again, or check your network.`;
    }
  }

  function renderItems(items, _totalBeforeFilter) {
    const ol = $('wn-list');
    const tpl = $('tpl-feed-item');

    items.forEach((item, idx) => {
      const node = tpl.content.cloneNode(true);
      const li = node.querySelector('.wn-item');
      const poster = node.querySelector('.wn-poster');
      const img = node.querySelector('img');
      const title = node.querySelector('.wn-title');
      const meta  = node.querySelector('.wn-meta');
      const desc  = node.querySelector('.wn-desc');

      li.dataset.archiveId = item.identifier;
      img.src = API.thumbnailURL(item.identifier);
      img.alt = item.title || item.identifier;
      poster.href = API.detailsURL(item.identifier);

      title.textContent = item.title || item.identifier;

      const year = (item.year || (item.date || '').slice(0, 4)) || '—';
      const added = (item.publicdate || '').slice(0, 10) || '—';
      const downloads = item.downloads ? Number(item.downloads).toLocaleString() : '—';
      meta.innerHTML = `
        <span>${escHtml(year)}</span>
        <span>·</span>
        <span title="Added to Archive">added ${escHtml(added)}</span>
        <span>·</span>
        <span title="Downloads"> ${escHtml(downloads)} dl</span>
      `;

      const descText = Array.isArray(item.description) ? item.description[0] : item.description;
      desc.innerHTML = stripTags(descText || '');

      // Actions
      node.querySelector('.wn-act-copy').addEventListener('click', () => {
        copyText(item.identifier);
      });

      node.querySelector('.wn-act-seen').addEventListener('click', () => {
        seen.add(item.identifier);
        saveSeen();
        li.classList.add('is-seen');
        toast(`Marked "${item.identifier}" as seen.`, 'success');
        $('wn-stats').textContent = `seen: ${seen.size} · pending: ${loadPending().length}`;
      });

      node.querySelector('.wn-act-add').addEventListener('click', () => {
        if (queueForPicks(item.identifier)) {
          toast(`Sent to Picks tray. Open the Dashboard to publish.`, 'success');
          $('wn-stats').textContent = `seen: ${seen.size} · pending: ${loadPending().length}`;
        } else {
          toast(`"${item.identifier}" is already in the pending tray.`, 'success');
        }
      });

      // Hydrate playable + IMDb badges asynchronously.
      ol.appendChild(node);
      hydrateBadges(li, item.identifier);
    });
  }

  async function hydrateBadges(li, archiveID) {
    try {
      const meta = await API.fetchMetadata(archiveID);
      const summary = API.summarize(meta);
      const metaEl = li.querySelector('.wn-meta');

      const imdbBadge = summary.hasIMDb
        ? `<span class="badge badge-good" title="${escHtml(summary.imdbID)}">IMDb ✓</span>`
        : `<span class="badge badge-warn" title="No IMDb cross-ref \u2014 will use Wikidata fallback">No IMDb</span>`;

      const playableBadge = summary.hasPlayable
        ? `<span class="badge badge-good" title="${escHtml(summary.videoFile.format || '')} · tier ${summary.videoFile.tier}">Playable ✓</span>`
        : `<span class="badge badge-bad" title="No video derivative found">Not playable</span>`;

      metaEl.insertAdjacentHTML('beforeend', imdbBadge + playableBadge);
    } catch (err) {
      li.classList.add('is-error');
    }
  }

  // ---- Helpers ---------------------------------------------------

  function stripTags(s) {
    // Archive descriptions sometimes contain HTML. Render text only,
    // so a stray <script> or weird formatting can't bleed through.
    const d = document.createElement('div');
    d.innerHTML = String(s);
    return escHtml(d.textContent || '');
  }

  let toastTimer = null;
  function toast(msg, kind) {
    const t = $('toast');
    t.textContent = msg;
    t.className = 'toast is-' + (kind || 'success');
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, 2400);
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      toast(`Copied "${text}" to clipboard.`, 'success');
    } catch {
      toast('Clipboard unavailable in this browser.', 'error');
    }
  }

  // ---- Wiring ----------------------------------------------------

  function bindCollectionTabs() {
    document.querySelectorAll('.wn-coll-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.wn-coll-btn').forEach(b => b.classList.remove('is-active'));
        btn.classList.add('is-active');
        activeCollection = btn.dataset.coll;
        loadFeed();
      });
    });
  }

  function init() {
    bindCollectionTabs();
    $('btn-refresh').addEventListener('click', loadFeed);
    $('wn-window').addEventListener('change', loadFeed);
    $('wn-limit').addEventListener('change', loadFeed);
    $('wn-show-seen').addEventListener('change', loadFeed);

    $('wn-stats').textContent = `seen: ${seen.size} · pending: ${loadPending().length}`;
    loadFeed();
  }

  init();
})();
