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
 * playlists union by recency. v1 limitation, documented: deletions made
 * on web don't carry tombstones yet, so a removal can resurrect from
 * another device — same as Apple's pre-#84 state; tombstones follow.
 */
window.AWDriveSync = (() => {
  const CLIENT_ID = window.AW_GOOGLE_CLIENT_ID || '';
  const SCOPE = 'https://www.googleapis.com/auth/drive.appdata';
  const FILE = 'awsync.json';
  let DB = null;
  let token = null;
  let tokenClient = null;
  let lastSync = 0;
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
    });
    return new Promise((resolve) => {
      tokenClient.callback = (resp) => {
        if (resp.access_token) {
          token = resp.access_token;
          localStorage.setItem('aw_gsync', '1');
        }
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

  // Merge cloud state into IndexedDB, Decision 078 rules; returns the
  // merged blob to push back.
  async function merge(cloud) {
    const local = {
      favorites: await DB.favorites(),
      playlists: await DB.playlists().catch(() => []),
      progress: await DB.progress(),
    };
    const c = cloud || {};

    const favs = new Map(local.favorites.map(f => [f.id, f]));
    for (const f of c.favorites || []) {
      if (!favs.has(f.id)) { favs.set(f.id, f); await DB.saveFavorite?.(f) ?? DB.toggleFavorite?.(f.id); }
    }

    const pls = new Map(local.playlists.map(p => [p.id, p]));
    for (const p of c.playlists || []) {
      const mine = pls.get(p.id);
      if (!mine || (p.modifiedAt || 0) > (mine.modifiedAt || 0)) {
        pls.set(p.id, p); await DB.savePlaylist?.(p);
      }
    }

    const prog = new Map(local.progress.map(p => [p.id, p]));
    for (const p of c.progress || []) {
      const mine = prog.get(p.id);
      if (!mine) {
        prog.set(p.id, p);
        await DB.putProgressRaw(p);
      } else {
        const winner = (p.at || 0) > (mine.at || 0) ? { ...mine, ...p } : { ...mine };
        // HISTORY = union, never LWW (Decision 078).
        winner.firstAt = Math.min(mine.firstAt || mine.at || Date.now(),
                                  p.firstAt || p.at || Date.now());
        winner.plays = Math.max(mine.plays || 1, p.plays || 1);
        winner.everDone = !!(mine.everDone || p.everDone);
        prog.set(p.id, winner);
        await DB.putProgressRaw(winner);
      }
    }

    return {
      v: 1, at: Date.now(),
      favorites: [...favs.values()],
      playlists: [...pls.values()],
      progress: [...prog.values()],
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
  }

  return {
    init(db, uiHost) {
      DB = db; ui = uiHost;
      if (!configured()) return;   // silent until the owner adds the client ID
      render();
      if (signedIn()) syncNow(false);
      // Re-sync when the tab regains focus and every 90s while visible.
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden) syncNow(false);
      });
      setInterval(() => { if (!document.hidden) syncNow(false); }, 90_000);
    },
    nudge() { if (configured() && signedIn()) syncNow(false); },
  };
})();
