/**
 * Archive Watch — Editorial Dashboard
 *
 * Loads featured.json, lets the curator manage shelves, and exports
 * an updated featured.json. Also doubles as a pipeline validator: when
 * the curator pastes an Archive ID, we fetch its metadata in their
 * browser and surface whether it has IMDb linkage and a playable
 * derivative — the same checks the tvOS EnrichmentService will run.
 *
 * No backend, no build step. Pure DOM.
 */
(function () {
  'use strict';

  /* ----------------------------------------------------------------
     State
  ---------------------------------------------------------------- */

  /** @type {object|null} */
  let data = null;
  /** @type {number} index into data.shelves of the active shelf */
  let activeShelfIndex = -1;
  /** Cache: archiveID -> summarized metadata */
  const previewCache = new Map();
  let savedDirty = false;

  /* ----------------------------------------------------------------
     Helpers
  ---------------------------------------------------------------- */

  const $ = (id) => document.getElementById(id);
  const escHtml = (s) => {
    const d = document.createElement('div');
    d.textContent = s == null ? '' : String(s);
    return d.innerHTML;
  };

  function categoryById(id) {
    return data?.categories?.find(c => c.id === id) || null;
  }

  function categoryColor(id) {
    return categoryById(id)?.accent || 'var(--color-accent)';
  }

  function categoryLabel(id) {
    return categoryById(id)?.shortName || id || '—';
  }

  function setDirty(v) {
    savedDirty = v;
    document.title = (v ? '• ' : '') + 'Archive Watch — Editorial Dashboard';
  }

  /* ----------------------------------------------------------------
     Pending tray (items queued by the What's New ticker)
  ---------------------------------------------------------------- */

  function loadPending() {
    try {
      const raw = localStorage.getItem('aw_pending');
      return raw ? JSON.parse(raw) : [];
    } catch { return []; }
  }
  function savePending(arr) {
    if (arr.length === 0) localStorage.removeItem('aw_pending');
    else localStorage.setItem('aw_pending', JSON.stringify(arr));
  }

  function renderPendingBanner() {
    const pending = loadPending();
    const banner = $('pending-banner');
    if (pending.length === 0) {
      banner.hidden = true;
      return;
    }
    $('pending-count').textContent = String(pending.length);
    banner.hidden = false;
  }

  function findEditorsPicksShelf() {
    if (!data) return -1;
    return (data.shelves || []).findIndex(s => s.id === 'editors-picks');
  }

  function mergePendingIntoPicks() {
    const pending = loadPending();
    if (pending.length === 0) return;
    if (!data) return;

    let idx = findEditorsPicksShelf();
    if (idx < 0) {
      // Pick the first curated shelf as a fallback, or create a new one.
      idx = (data.shelves || []).findIndex(s => s.type === 'curated');
      if (idx < 0) {
        data.shelves = data.shelves || [];
        data.shelves.unshift({
          id: 'editors-picks',
          title: "Editor's Picks",
          subtitle: 'Hand-selected curiosities and favorites',
          category: data.categories?.[0]?.id || 'feature-film',
          type: 'curated',
          items: []
        });
        idx = 0;
      }
    }

    const shelf = data.shelves[idx];
    shelf.items = shelf.items || [];
    let added = 0;
    for (const id of pending) {
      if (!shelf.items.some(it => it.archiveID === id)) {
        shelf.items.push({ archiveID: id, note: '' });
        added++;
      }
    }

    savePending([]);
    setDirty(true);
    activeShelfIndex = idx;
    render();
    renderPendingBanner();
    flash(`Added ${added} item${added === 1 ? '' : 's'} to ${shelf.title}. Don't forget to Export.`, 'success');
  }

  function discardPending() {
    if (!confirm('Discard the pending tray? The items will be removed from the queue.')) return;
    savePending([]);
    renderPendingBanner();
  }

  /* ----------------------------------------------------------------
     Load + Save
  ---------------------------------------------------------------- */

  async function loadRemote() {
    try {
      const resp = await fetch('featured.json?ts=' + Date.now());
      if (!resp.ok) throw new Error(`featured.json HTTP ${resp.status}`);
      data = await resp.json();
      activeShelfIndex = -1;
      previewCache.clear();
      setDirty(false);
      render();
      flash('Loaded featured.json from this site.', 'success');
    } catch (err) {
      flash(`Could not load featured.json: ${err.message}`, 'error');
    }
  }

  function importFile(file) {
    const reader = new FileReader();
    reader.onload = () => {
      try {
        data = JSON.parse(reader.result);
        activeShelfIndex = -1;
        previewCache.clear();
        setDirty(true);
        render();
        flash(`Imported "${file.name}".`, 'success');
      } catch (err) {
        flash(`Could not parse JSON: ${err.message}`, 'error');
      }
    };
    reader.readAsText(file);
  }

  function exportJSON() {
    if (!data) return;
    data.updatedAt = new Date().toISOString().slice(0, 10);
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'featured.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    setDirty(false);
    flash('Downloaded featured.json. Commit it to the repo to publish.', 'info');
  }

  /* ----------------------------------------------------------------
     Render
  ---------------------------------------------------------------- */

  function render() {
    if (!data) return;

    // Meta
    $('meta-schema').textContent = data.schemaVersion || data.version || '—';
    $('meta-updated').textContent = data.updatedAt || '—';
    const totalItems = (data.shelves || []).reduce((acc, s) => acc + (s.type === 'curated' ? (s.items?.length || 0) : 0), 0);
    $('meta-counts').textContent = `${(data.shelves || []).length} shelves · ${totalItems} curated items`;

    renderCategories();
    renderShelfList();
    renderShelfEditor();
  }

  function renderCategories() {
    const ul = $('category-list');
    ul.innerHTML = '';
    (data.categories || []).forEach(cat => {
      const li = document.createElement('li');
      li.innerHTML = `
        <span class="cat-dot" style="background:${escHtml(cat.accent)}"></span>
        <span><strong>${escHtml(cat.displayName)}</strong> <span style="color: var(--color-text-dim)">· ${escHtml(cat.id)}</span></span>
      `;
      ul.appendChild(li);
    });
  }

  function renderShelfList() {
    const ol = $('shelf-list');
    ol.innerHTML = '';
    const tpl = $('tpl-shelf-row');

    (data.shelves || []).forEach((shelf, i) => {
      const node = tpl.content.cloneNode(true);
      const li = node.querySelector('.shelf-row');
      const title = node.querySelector('.shelf-row-title');
      const meta  = node.querySelector('.shelf-row-meta');
      const dot   = node.querySelector('.shelf-row-cat-dot');

      li.dataset.idx = String(i);
      if (i === activeShelfIndex) li.classList.add('is-active');
      title.textContent = shelf.title || '(untitled shelf)';
      const count = shelf.type === 'curated'
        ? `${(shelf.items || []).length} items`
        : `dynamic · ${(shelf.sort || []).join(', ') || 'default sort'}`;
      meta.textContent = `${categoryLabel(shelf.category)} · ${count}`;
      dot.style.background = categoryColor(shelf.category);

      li.addEventListener('click', () => selectShelf(i));
      li.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); selectShelf(i); }
      });
      ol.appendChild(node);
    });
  }

  function selectShelf(i) {
    activeShelfIndex = i;
    render();
  }

  function renderShelfEditor() {
    const editor = $('shelf-editor');
    const empty  = $('empty-state');

    if (activeShelfIndex < 0 || !data.shelves[activeShelfIndex]) {
      editor.hidden = true;
      empty.hidden = false;
      return;
    }

    empty.hidden = true;
    editor.hidden = false;

    const shelf = data.shelves[activeShelfIndex];

    // Titles
    $('shelf-title').value = shelf.title || '';
    $('shelf-subtitle').value = shelf.subtitle || '';

    // Category dropdown
    const catSel = $('shelf-category');
    catSel.innerHTML = '';
    (data.categories || []).forEach(cat => {
      const opt = document.createElement('option');
      opt.value = cat.id;
      opt.textContent = cat.displayName;
      if (cat.id === shelf.category) opt.selected = true;
      catSel.appendChild(opt);
    });

    // Type
    $('shelf-type').value = shelf.type || 'curated';

    // Mode panes
    const isCurated = shelf.type !== 'dynamic';
    $('pane-curated').hidden = !isCurated;
    $('pane-dynamic').hidden = isCurated;

    if (isCurated) {
      renderCuratedItems(shelf);
    } else {
      $('shelf-query').value = shelf.query || '';
      $('shelf-sort').value = (shelf.sort && shelf.sort[0]) || '-downloads';
      $('shelf-limit').value = shelf.limit || 24;
      $('dynamic-preview').innerHTML = '';
    }
  }

  /* ----------------------------------------------------------------
     Curated items
  ---------------------------------------------------------------- */

  function renderCuratedItems(shelf) {
    const ol = $('curated-items');
    ol.innerHTML = '';
    const tpl = $('tpl-curated-item');

    (shelf.items || []).forEach((item, idx) => {
      const li = renderItemRow(tpl, item, idx, shelf.items.length);
      ol.appendChild(li);
      lookupAndPaint(item.archiveID, li);
    });
  }

  function renderItemRow(tpl, item, idx, total) {
    const node = tpl.content.cloneNode(true);
    const li   = node.querySelector('.item-row');
    const img  = node.querySelector('img');
    const open = node.querySelector('.item-open');
    const note = node.querySelector('.item-note');

    li.dataset.archiveId = item.archiveID;
    li.dataset.idx = String(idx);
    li.classList.add('is-loading');
    img.src = API.thumbnailURL(item.archiveID);
    img.alt = item.archiveID;
    open.href = API.detailsURL(item.archiveID);
    note.value = item.note || '';

    note.addEventListener('change', () => {
      const shelf = data.shelves[activeShelfIndex];
      shelf.items[idx].note = note.value;
      setDirty(true);
    });

    node.querySelector('.item-up').addEventListener('click', () => moveItem(idx, -1));
    node.querySelector('.item-down').addEventListener('click', () => moveItem(idx, +1));
    node.querySelector('.item-up').disabled = idx === 0;
    node.querySelector('.item-down').disabled = idx === total - 1;
    node.querySelector('.item-remove').addEventListener('click', () => removeItem(idx));

    return li;
  }

  async function lookupAndPaint(archiveID, li) {
    try {
      let summary = previewCache.get(archiveID);
      if (!summary) {
        const meta = await API.fetchMetadata(archiveID);
        summary = API.summarize(meta);
        previewCache.set(archiveID, summary);
      }
      paintRow(li, summary);
    } catch (err) {
      paintRowError(li, err.message);
    } finally {
      li.classList.remove('is-loading');
    }
  }

  function paintRow(li, s) {
    const titleEl = li.querySelector('.item-title');
    const metaEl  = li.querySelector('.item-meta');

    titleEl.textContent = s.title;

    const yearStr = s.year ? `${s.year}` : '—';
    const collectionStr = (s.collections || []).slice(0, 2).join(' · ') || '—';

    const imdbBadge = s.hasIMDb
      ? `<span class="badge badge-good" title="${escHtml(s.imdbID)}">IMDb ✓</span>`
      : `<span class="badge badge-warn" title="No IMDb in external-identifier — will fall back to Wikidata SPARQL">No IMDb</span>`;

    const playableBadge = s.hasPlayable
      ? `<span class="badge badge-good" title="${escHtml(s.videoFile.format || '')} · tier ${s.videoFile.tier}">Playable ✓</span>`
      : `<span class="badge badge-bad" title="No video derivative found">Not playable</span>`;

    metaEl.innerHTML = `
      <span>${escHtml(yearStr)}</span>
      <span>·</span>
      <span title="${escHtml(s.identifier)}">${escHtml(s.identifier)}</span>
      <span>·</span>
      <span>${escHtml(collectionStr)}</span>
      ${imdbBadge}
      ${playableBadge}
    `;
  }

  function paintRowError(li, msg) {
    li.classList.add('is-error');
    li.querySelector('.item-title').textContent = li.dataset.archiveId;
    li.querySelector('.item-meta').innerHTML = `<span class="badge badge-bad">Error: ${escHtml(msg)}</span>`;
  }

  function moveItem(idx, delta) {
    const shelf = data.shelves[activeShelfIndex];
    const items = shelf.items;
    const target = idx + delta;
    if (target < 0 || target >= items.length) return;
    const [removed] = items.splice(idx, 1);
    items.splice(target, 0, removed);
    setDirty(true);
    renderShelfList();
    renderShelfEditor();
  }

  function removeItem(idx) {
    const shelf = data.shelves[activeShelfIndex];
    const id = shelf.items[idx]?.archiveID;
    if (!confirm(`Remove "${id}" from ${shelf.title}?`)) return;
    shelf.items.splice(idx, 1);
    setDirty(true);
    renderShelfList();
    renderShelfEditor();
  }

  /* ----------------------------------------------------------------
     Add curated item
  ---------------------------------------------------------------- */

  async function handleAddID() {
    const input = $('add-archive-id');
    const id = API.normalizeIdentifier(input.value);
    if (!id) {
      flashAdd('Paste an Archive ID or full URL first.', 'error');
      return;
    }
    const shelf = data.shelves[activeShelfIndex];
    if (!shelf || shelf.type !== 'curated') return;

    if (shelf.items.some(it => it.archiveID === id)) {
      flashAdd(`"${id}" is already in this shelf.`, 'error');
      return;
    }

    flashAdd(`Looking up "${id}" on Archive.org…`, 'info');

    try {
      const meta = await API.fetchMetadata(id);
      const summary = API.summarize(meta);
      previewCache.set(id, summary);
      shelf.items.push({ archiveID: id, note: '' });
      setDirty(true);
      input.value = '';

      const issues = [];
      if (!summary.hasPlayable) issues.push('no playable derivative');
      if (!summary.hasIMDb)     issues.push('no IMDb cross-ref (will use Wikidata fallback)');
      const tag = issues.length ? ` Heads up: ${issues.join(', ')}.` : '';
      flashAdd(`Added "${summary.title}" (${summary.year || '—'}).${tag}`, issues.length ? 'info' : 'success');

      renderShelfList();
      renderShelfEditor();
    } catch (err) {
      flashAdd(`Could not fetch "${id}": ${err.message}`, 'error');
    }
  }

  function flashAdd(msg, kind) {
    const fb = $('add-feedback');
    fb.hidden = false;
    fb.className = 'feedback is-' + kind;
    fb.textContent = msg;
  }

  /* ----------------------------------------------------------------
     Dynamic preview
  ---------------------------------------------------------------- */

  async function previewDynamic() {
    const shelf = data.shelves[activeShelfIndex];
    if (!shelf || shelf.type !== 'dynamic') return;

    // Persist edits to shelf before previewing.
    shelf.query = $('shelf-query').value.trim();
    shelf.sort  = [$('shelf-sort').value];
    shelf.limit = parseInt($('shelf-limit').value, 10) || 24;
    setDirty(true);

    const ol = $('dynamic-preview');
    ol.innerHTML = `<li class="feedback is-info">Loading from Archive.org…</li>`;

    try {
      const { items } = await API.scrape({
        q: shelf.query,
        sorts: shelf.sort,
        count: shelf.limit
      });
      ol.innerHTML = '';
      const tpl = $('tpl-curated-item');

      items.forEach((it, idx) => {
        const li = renderItemRow(tpl, { archiveID: it.identifier, note: '' }, idx, items.length);
        // Disable mutation actions in preview mode
        li.querySelectorAll('.item-up, .item-down, .item-remove').forEach(b => b.style.visibility = 'hidden');
        li.querySelector('.item-note').readOnly = true;
        li.querySelector('.item-note').placeholder = '(preview only)';
        ol.appendChild(li);
        lookupAndPaint(it.identifier, li);
      });

      if (items.length === 0) {
        ol.innerHTML = `<li class="feedback is-error">No results. Check your query syntax.</li>`;
      }
    } catch (err) {
      ol.innerHTML = `<li class="feedback is-error">${escHtml(err.message)}</li>`;
    }
  }

  /* ----------------------------------------------------------------
     Shelf-level operations
  ---------------------------------------------------------------- */

  function bindEditorChanges() {
    $('shelf-title').addEventListener('change', () => {
      data.shelves[activeShelfIndex].title = $('shelf-title').value;
      setDirty(true); renderShelfList();
    });
    $('shelf-subtitle').addEventListener('change', () => {
      data.shelves[activeShelfIndex].subtitle = $('shelf-subtitle').value;
      setDirty(true);
    });
    $('shelf-category').addEventListener('change', () => {
      data.shelves[activeShelfIndex].category = $('shelf-category').value;
      setDirty(true); renderShelfList();
    });
    $('shelf-type').addEventListener('change', () => {
      const shelf = data.shelves[activeShelfIndex];
      shelf.type = $('shelf-type').value;
      if (shelf.type === 'curated' && !shelf.items) shelf.items = [];
      if (shelf.type === 'dynamic' && !shelf.query) shelf.query = 'mediatype:movies';
      setDirty(true); renderShelfList(); renderShelfEditor();
    });

    $('btn-delete-shelf').addEventListener('click', () => {
      const shelf = data.shelves[activeShelfIndex];
      if (!shelf) return;
      if (!confirm(`Delete the shelf "${shelf.title}"? This can't be undone (until you re-export).`)) return;
      data.shelves.splice(activeShelfIndex, 1);
      activeShelfIndex = -1;
      setDirty(true);
      render();
    });
  }

  function newShelf() {
    if (!data) return;
    const shelf = {
      id: 'shelf-' + Date.now(),
      title: 'New shelf',
      subtitle: '',
      category: data.categories?.[0]?.id || 'feature-film',
      type: 'curated',
      items: []
    };
    data.shelves = data.shelves || [];
    data.shelves.push(shelf);
    activeShelfIndex = data.shelves.length - 1;
    setDirty(true);
    render();
  }

  /* ----------------------------------------------------------------
     Toast (very small)
  ---------------------------------------------------------------- */

  let toastTimeout = null;
  function flash(msg, kind) {
    // Reuse the add-feedback element if no shelf is active; otherwise
    // log to console so the curator's eye stays where they're working.
    if (activeShelfIndex < 0) {
      const empty = $('empty-state');
      empty.querySelector('p').innerHTML = `<span class="feedback is-${kind}">${escHtml(msg)}</span>`;
      clearTimeout(toastTimeout);
      toastTimeout = setTimeout(() => {
        empty.querySelector('p').innerHTML = 'Or hit <strong>Reload</strong> to fetch the latest <code>featured.json</code>.';
      }, 4000);
    } else {
      console.log(`[${kind}] ${msg}`);
    }
  }

  /* ----------------------------------------------------------------
     Init
  ---------------------------------------------------------------- */

  function init() {
    bindEditorChanges();

    $('btn-load-remote').addEventListener('click', loadRemote);
    $('btn-export').addEventListener('click', exportJSON);
    $('btn-import').addEventListener('click', () => $('file-import').click());
    $('file-import').addEventListener('change', (e) => {
      if (e.target.files?.[0]) importFile(e.target.files[0]);
    });

    $('btn-add-shelf').addEventListener('click', newShelf);
    $('btn-add-id').addEventListener('click', handleAddID);

    $('btn-pending-merge').addEventListener('click', mergePendingIntoPicks);
    $('btn-pending-discard').addEventListener('click', discardPending);
    renderPendingBanner();
    // Re-check when the user returns to this tab from What's New.
    window.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') renderPendingBanner();
    });
    $('add-archive-id').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); handleAddID(); }
    });
    $('btn-preview-dynamic').addEventListener('click', previewDynamic);

    window.addEventListener('beforeunload', (e) => {
      if (savedDirty) {
        e.preventDefault();
        e.returnValue = '';
      }
    });

    loadRemote();
  }

  init();
})();
