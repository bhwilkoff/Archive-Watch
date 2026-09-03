/* Cross-device sync for the web viewer via the user's OWN Google Drive
 * (App Data folder) — Decision 028's no-backend analog of CloudKit: the
 * data lives in the user's account, we never see it, and Android shares
 * the same blob so a phone and a browser converge.
 *
 * ACTIVATION: set window.AW_GOOGLE_CLIENT_ID in index.html to the OAuth
 * client ID (owner action — see docs/google-oauth-setup.md). Until then
 * every entry point here is a silent no-op and no Google script loads.
 *
 * Blob: one JSON file `awsync.json` in the appDataFolder, mirroring the
 * CloudKit AWSync payload shapes (favorites / playlists / progress with
 * history fields / channels) so the merge rules match Decision 078:
 * position is last-writer-wins by `at`; HISTORY is a union (earliest
 * firstAt, max plays, everDone-anywhere = everywhere); favorites and
 * playlists last-writer-wins; deletions carry TOMBSTONES (v2) so a
 * removal made here never resurrects from a device that still has it.
 */
window.AWDriveSync = (() => {
  const CLIENT_ID = window.AW_GOOGLE_CLIENT_ID || '';
  const SCOPE = 'https://www.googleapis.com/auth/drive.appdata';
  const FILE = 'awsync.json';
  let DB = null;
  let token = null;
  let tokenClient = null;
  let lastSync = 0;
  let lastError = null;
  let pendingResolve = null;
  let ui = null;

  const configured = () => !!CLIENT_ID;
  const signedIn = () => !!localStorage.getItem('aw_gsync');

  function loadGIS() {
    return new Promise((resolve, reject) => {
      if (window.google?.accounts?.oauth2) return resolve();
      const s = document.createElement('script');
      s.src = 'https://accounts.google.com/gsi/client';
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  async function getToken(interactive) {
    await loadGIS();
    tokenClient ||= google.accounts.oauth2.initTokenClient({
      client_id: CLIENT_ID, scope: SCOPE, callback: () => {},
      // Never silent (per-ecosystem-sync-islands rule 3): a blocked popup
      // or a dismissed consent is SAID on the Library page, not swallowed.
      error_callback: (e) => {
        lastError = e?.type === 'popup_failed_to_open'
          ? 'Your browser blocked the Google sign-in window — allow pop-ups for this site and try again.'
          : e?.type === 'popup_closed' ? 'Google sign-in was closed before finishing.'
          : ('Google sign-in failed: ' + (e?.message || e?.type || 'unknown'));
        render();
        pendingResolve?.(null); pendingResolve = null;
      },
    });
    return new Promise((resolve) => {
      pendingResolve = resolve;
      tokenClient.callback = (resp) => {
        if (resp.access_token) {
          token = resp.access_token;
          lastError = null;
          localStorage.setItem('aw_gsync', '1');
        } else if (resp.error) {
          lastError = 'Google sign-in failed: ' + resp.error;
        }
        pendingResolve = null;
        resolve(resp.access_token || null);
      };
      tokenClient.requestAccessToken({ prompt: interactive ? 'consent' : '' });
    });
  }

  async function drive(path, opts = {}) {
    const r = await fetch(`https://www.googleapis.com${path}`, {
      ...opts,
      headers: { Authorization: `Bearer ${token}`, ...(opts.headers || {}) },
    });
    if (r.status === 401) throw new Error('auth');
    return r;
  }

  async function findFile() {
    const r = await drive(
      `/drive/v3/files?spaces=appDataFolder&q=name%3D%27${FILE}%27&fields=files(id)`);
    const d = await r.json();
    return d.files?.[0]?.id || null;
  }

  async function pull(fileId) {
    const r = await drive(`/drive/v3/files/${fileId}?alt=media`);
    return r.ok ? r.json().catch(() => null) : null;
  }

  async function push(fileId, blob) {
    const body = JSON.stringify(blob);
    if (fileId) {
      await drive(`/upload/drive/v3/files/${fileId}?uploadType=media`, {
        method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body,
      });
    } else {
      const meta = { name: FILE, parents: ['appDataFolder'] };
      const boundary = 'awsyncb';
      await drive(`/upload/drive/v3/files?uploadType=multipart`, {
        method: 'POST',
        headers: { 'Content-Type': `multipart/related; boundary=${boundary}` },
        body: `--${boundary}\r\nContent-Type: application/json\r\n\r\n${JSON.stringify(meta)}` +
              `\r\n--${boundary}\r\nContent-Type: application/json\r\n\r\n${body}\r\n--${boundary}--`,
      });
    }
  }

  // Merge cloud state into IndexedDB and return the union blob to push
  // back. v2 blob, field-for-field the Android DriveSync's (google flavor):
  //   favorites   union minus tombstones
  //   playlists   last writer wins by modifiedAt, minus tombstones
  //   channels    union minus tombstones (Android says contentType, we say type)
  //   progress    position LWW by `at`; HISTORY is a UNION (Decision 078)
  //   tombstones  union, 90-day TTL; a re-add newer than its stone clears it
  const TOMB_TTL = 90 * 24 * 3600_000;
  async function merge(cloud) {
    const c = cloud || {};
    const now = Date.now();

    const tombs = new Map();
    for (const t of await DB.tombstones().catch(() => [])) tombs.set(t.kind + ':' + t.id, t.at);
    for (const t of c.tombstones || []) {
      const k = t.kind + ':' + t.id;
      if ((t.at || 0) > (tombs.get(k) || 0)) tombs.set(k, t.at);
    }
    for (const [k, at] of tombs) if (now - at > TOMB_TTL) tombs.delete(k);
    const dead = (kind, id, itemAt) => (tombs.get(kind + ':' + id) || 0) > (itemAt || 0);

    const localFavs = await DB.favorites();
    const favs = new Map(localFavs.map(f => [f.id, f]));
    for (const f of c.favorites || []) {
      if (!f?.id) continue;
      const mine = favs.get(f.id);
      if (!mine || (f.addedAt || 0) > (mine.addedAt || 0)) favs.set(f.id, { id: f.id, addedAt: f.addedAt || now });
    }
    for (const [id, f] of [...favs]) if (dead('fav', id, f.addedAt)) favs.delete(id);
    const localFavIDs = new Set(localFavs.map(f => f.id));
    for (const [id, f] of favs) if (!localFavIDs.has(id)) await DB.saveFavorite(f);
    for (const id of localFavIDs) if (!favs.has(id)) await DB.removeFavoriteRaw(id);

    const localPls = await DB.playlists().catch(() => []);
    const pls = new Map(localPls.map(p => [p.id, p]));
    for (const p of c.playlists || []) {
      if (!p?.id) continue;
      const mine = pls.get(p.id);
      if (!mine || (p.modifiedAt || 0) > (mine.modifiedAt || 0)) {
        pls.set(p.id, { id: p.id, name: p.name || '', archiveIDs: (p.archiveIDs || []).filter(Boolean),
                        createdAt: p.createdAt || p.modifiedAt || now, modifiedAt: p.modifiedAt || now });
      }
    }
    for (const [id, p] of [...pls]) if (dead('pl', id, p.modifiedAt)) pls.delete(id);
    const localPlByID = new Map(localPls.map(p => [p.id, p]));
    for (const [id, p] of pls) {
      const mine = localPlByID.get(id);
      if (!mine || (p.modifiedAt || 0) > (mine.modifiedAt || 0)) await DB.savePlaylistRaw(p);
    }
    for (const id of localPlByID.keys()) if (!pls.has(id)) await DB.removePlaylistRaw(id);

    const localChs = await DB.userChannels().catch(() => []);
    const chs = new Map(localChs.map(ch => [ch.id, ch]));
    for (const ch of c.channels || []) {
      if (!ch?.id || chs.has(ch.id)) continue;
      chs.set(ch.id, { id: ch.id, name: ch.name || '', type: ch.type ?? ch.contentType ?? null,
                       genre: ch.genre ?? null, decade: ch.decade ?? null, createdAt: ch.createdAt || now });
    }
    for (const [id, ch] of [...chs]) if (dead('ch', id, ch.createdAt)) chs.delete(id);
    const localChIDs = new Set(localChs.map(ch => ch.id));
    for (const [id, ch] of chs) if (!localChIDs.has(id)) await DB.saveUserChannel(ch);
    for (const id of localChIDs) if (!chs.has(id)) await DB.removeUserChannelRaw(id);

    const prog = new Map((await DB.progress()).map(p => [p.id, p]));
    for (const p of c.progress || []) {
      if (!p?.id) continue;
      const mine = prog.get(p.id);
      if (!mine) {
        prog.set(p.id, p);
        await DB.putProgressRaw(p);
      } else {
        const winner = (p.at || 0) > (mine.at || 0) ? { ...mine, ...p } : { ...mine };
        // HISTORY = union, never LWW (Decision 078).
        winner.firstAt = Math.min(mine.firstAt || mine.at || now, p.firstAt || p.at || now);
        winner.plays = Math.max(mine.plays || 1, p.plays || 1);
        winner.everDone = !!(mine.everDone || p.everDone);
        prog.set(p.id, winner);
        await DB.putProgressRaw(winner);
      }
    }

    for (const [k, at] of tombs) {
      const i = k.indexOf(':');
      await DB.putTombstone(k.slice(0, i), k.slice(i + 1), at);
    }

    return {
      v: 2, at: now,
      favorites: [...favs.values()],
      playlists: [...pls.values()],
      channels: [...chs.values()].map(ch => ({ ...ch, contentType: ch.type ?? null })),
      progress: [...prog.values()],
      tombstones: [...tombs].map(([k, at]) => {
        const i = k.indexOf(':');
        return { kind: k.slice(0, i), id: k.slice(i + 1), at };
      }),
    };
  }

  async function syncNow(interactive = false) {
    if (!configured() || !DB) return;
    if (!signedIn() && !interactive) return;
    try {
      if (!token && !(await getToken(interactive))) return;
      let fileId = await findFile();
      const cloud = fileId ? await pull(fileId) : null;
      const mergedBlob = await merge(cloud);
      await push(fileId, mergedBlob);
      lastSync = Date.now();
      render();
      window.dispatchEvent(new CustomEvent('aw-sync-done'));
    } catch (e) {
      if (e.message === 'auth') { token = null; }
      lastError = e.message === 'auth' ? 'Google Drive access expired — sign in again.' : ('Sync failed: ' + e.message);
      render();
      console.warn('[sync]', e);
    }
  }

  function signOut() {
    localStorage.removeItem('aw_gsync');
    token = null;
    render();
  }

  function render() {
    if (!ui || !configured()) return;
    ui.hidden = false;
    if (signedIn()) {
      ui.innerHTML = '';
      const span = document.createElement('span');
      span.textContent = lastSync
        ? `Synced ${new Date(lastSync).toLocaleTimeString()} · `
        : 'Sync on · ';
      const out = document.createElement('button');
      out.textContent = 'Sign out';
      out.onclick = signOut;
      ui.append(span, out);
    } else {
      ui.innerHTML = '';
      const btn = document.createElement('button');
      btn.textContent = 'Sign in with Google to sync across devices';
      btn.onclick = () => syncNow(true);
      ui.append(btn);
    }
    if (lastError) {
      const err = document.createElement('span');
      err.className = 'sync-error';
      err.textContent = ' ' + lastError;
      ui.append(err);
    }
  }

  return {
    init(db, uiHost) {
      DB = db; ui = uiHost;
      if (!configured()) return;   // silent until a client ID is configured
      render();
      if (signedIn()) syncNow(false);
      // Re-sync when the tab regains focus and every 90s while visible.
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden) syncNow(false);
      });
      setInterval(() => { if (!document.hidden) syncNow(false); }, 90_000);
    },
    nudge() { if (configured() && signedIn()) syncNow(false); },
    // The merge is shared with js/cloudkitsync.js (Apple's island reaches
    // the browser through CloudKit JS); one set of rules, two clouds.
    merge,
  };
})();
