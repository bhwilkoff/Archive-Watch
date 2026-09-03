/* Sign in with Apple on the web → the SAME CloudKit private database the
 * tvOS / iOS / macOS apps sync through (Decision 022's container,
 * `iCloud.app.archivewatch.tvos`, record type `AWSync`, five fixed-ID
 * records: tombstones / favorites / playlists / progress / channels, each a
 * JSON `payload` blob). Apple's own CloudKit JS does the sign-in (the
 * Apple ID sheet, 2FA and all) and hands this page an authenticated
 * private-database client — no server of ours, no Apple secret.
 *
 * ACTIVATION: set window.AW_CLOUDKIT_API_TOKEN in index.html to a CloudKit
 * JS API token created in CloudKit Console → the container → API Access →
 * "Create API Token" with Sign in with Apple ALLOWED (the token is public
 * by nature, like the Google client ID). Until then every entry point here
 * is a silent no-op and no Apple script loads. docs/web-apple-sync.md.
 *
 * Merge rules are Decision 078's, shared with js/drivesync.js
 * (AWDriveSync.merge): the Apple records are converted to the v2 blob
 * shape, merged into IndexedDB, and the union is written back. A browser
 * signed into BOTH clouds is therefore the one place the two islands meet.
 */
window.AWCloudKitSync = (() => {
  const TOKEN = window.AW_CLOUDKIT_API_TOKEN || '';
  const CONTAINER = 'iCloud.app.archivewatch.tvos';
  const RECORDS = ['tombstones', 'favorites', 'playlists', 'progress', 'channels'];
  let DB = null;
  let ui = null;
  let container = null;
  let lastSync = 0;
  let lastError = null;
  let syncing = false;

  const configured = () => !!TOKEN;

  function loadCK() {
    return new Promise((resolve, reject) => {
      if (window.CloudKit) return resolve();
      const s = document.createElement('script');
      s.src = 'https://cdn.apple-cloudkit.com/ck/2/cloudkit.js';
      s.onload = resolve;
      s.onerror = () => reject(new Error('CloudKit JS failed to load'));
      document.head.appendChild(s);
    });
  }

  async function setup() {
    await loadCK();
    if (container) return container;
    window.CloudKit.configure({
      containers: [{
        containerIdentifier: CONTAINER,
        apiTokenAuth: { apiToken: TOKEN, persist: true },
        environment: 'production',
      }],
    });
    container = window.CloudKit.getDefaultContainer();
    return container;
  }

  // --- payload codecs: CloudKit BYTES are base64; the apps write JSON with
  // dates as SECONDS since 1970 (Swift .secondsSince1970).
  const dec = (rec) => {
    const b64 = rec?.fields?.payload?.value;
    if (!b64) return [];
    try { return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), c => c.charCodeAt(0)))); }
    catch { return []; }
  };
  const enc = (arr) => btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(arr))));
  const sec = (ms) => (ms ? ms / 1000 : undefined);
  const ms = (s) => (s ? Math.round(s * 1000) : 0);

  function toBlob(recs) {
    const by = Object.fromEntries(recs.map(r => [r.recordName, r]));
    return {
      v: 2,
      favorites: dec(by.favorites).map(f => ({ id: f.archiveID, addedAt: ms(f.addedAt) })),
      playlists: dec(by.playlists).map(p => ({
        id: p.id, name: p.name, archiveIDs: p.archiveIDs || [],
        createdAt: ms(p.createdAt), modifiedAt: ms(p.modifiedAt),
      })),
      channels: dec(by.channels).map(c => ({
        id: c.id, name: c.name, genre: c.genre ?? null, type: c.contentType ?? null,
        decade: c.decade ?? null, createdAt: ms(c.createdAt),
      })),
      progress: dec(by.progress).map(p => ({
        id: p.archiveID, position: p.positionSeconds, duration: p.durationSeconds,
        at: ms(p.lastWatchedAt), firstAt: ms(p.firstWatchedAt), plays: p.playCount || 1,
        everDone: !!p.everCompleted,
      })),
      // Apple keys are "fav:<id>" / "pl:<id>" / "ch:<id>" / "wp:<id>"; the
      // blob carries kind + id. "wp" (a cleared progress) has no web twin
      // and is passed through untouched below.
      tombstones: dec(by.tombstones).map(t => {
        const i = t.key.indexOf(':');
        return { kind: t.key.slice(0, i), id: t.key.slice(i + 1), at: ms(t.deletedAt) };
      }),
    };
  }

  function fromBlob(blob, prior) {
    const by = Object.fromEntries(prior.map(r => [r.recordName, r]));
    const rec = (name, arr) => ({
      recordName: name,
      recordType: 'AWSync',
      ...(by[name]?.recordChangeTag ? { recordChangeTag: by[name].recordChangeTag } : {}),
      fields: { payload: { value: enc(arr) }, modifiedAt: { value: Date.now() } },
    });
    return [
      rec('favorites', blob.favorites.map(f => ({ archiveID: f.id, addedAt: sec(f.addedAt) }))),
      rec('playlists', blob.playlists.map(p => ({
        id: p.id, name: p.name, archiveIDs: p.archiveIDs,
        createdAt: sec(p.createdAt), modifiedAt: sec(p.modifiedAt),
      }))),
      rec('channels', blob.channels.map(c => ({
        id: c.id, name: c.name, genre: c.genre ?? undefined, contentType: c.type ?? undefined,
        decade: c.decade ?? undefined, createdAt: sec(c.createdAt),
      }))),
      rec('progress', blob.progress.map(p => ({
        archiveID: p.id, positionSeconds: p.position, durationSeconds: p.duration,
        lastWatchedAt: sec(p.at), firstWatchedAt: sec(p.firstAt), playCount: p.plays || 1,
        everCompleted: !!p.everDone,
      }))),
      rec('tombstones', blob.tombstones.map(t => ({ key: t.kind + ':' + t.id, deletedAt: sec(t.at) }))),
    ];
  }

  async function syncNow() {
    if (!configured() || !DB || syncing) return;
    const c = await setup().catch(e => { lastError = e.message; render(); return null; });
    if (!c) return;
    syncing = true;
    try {
      const auth = await c.setUpAuth();
      if (!auth) { render(); return; }            // signed out: the Apple button is showing
      const db = c.privateCloudDatabase;
      const fetched = await db.fetchRecords(RECORDS);
      if (fetched.hasErrors) {
        // A record that does not exist yet is not an error for us.
        const real = fetched.errors.filter(e => e.ckErrorCode !== 'NOT_FOUND');
        if (real.length) throw new Error(real[0].reason || real[0].ckErrorCode);
      }
      const prior = fetched.records || [];
      const merged = await window.AWDriveSync.merge(toBlob(prior));
      const saved = await db.saveRecords(fromBlob(merged, prior));
      if (saved.hasErrors) throw new Error(saved.errors[0].reason || saved.errors[0].ckErrorCode);
      lastSync = Date.now();
      lastError = null;
      localStorage.setItem('aw_cksync', '1');
      render();
      window.dispatchEvent(new CustomEvent('aw-sync-done'));
    } catch (e) {
      lastError = 'iCloud sync failed: ' + (e.message || e);
      render();
      console.warn('[cksync]', e);
    } finally {
      syncing = false;
    }
  }

  function render() {
    if (!ui || !configured()) return;
    ui.hidden = false;
    ui.replaceChildren();
    // CloudKit JS renders Apple's own sign-in / sign-out buttons into these
    // two ids; it shows whichever applies after setUpAuth().
    const inBtn = document.createElement('div'); inBtn.id = 'apple-sign-in-button';
    const outBtn = document.createElement('div'); outBtn.id = 'apple-sign-out-button';
    const status = document.createElement('span');
    status.textContent = lastSync
      ? ` iCloud synced ${new Date(lastSync).toLocaleTimeString()} · `
      : (localStorage.getItem('aw_cksync') ? ' iCloud sync on · ' : ' Sign in with Apple to sync with your Apple TV, iPhone and Mac · ');
    ui.append(inBtn, status, outBtn);
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
      if (!configured()) return;   // silent until the CloudKit token is configured
      render();
      setup().then(c => {
        c.setUpAuth().then(user => { if (user) syncNow(); });
        c.whenUserSignsIn().then(() => syncNow());
        c.whenUserSignsOut().then(() => { localStorage.removeItem('aw_cksync'); lastSync = 0; render(); });
      }).catch(e => { lastError = e.message; render(); });
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden && localStorage.getItem('aw_cksync')) syncNow();
      });
      setInterval(() => { if (!document.hidden && localStorage.getItem('aw_cksync')) syncNow(); }, 90_000);
    },
    nudge() { if (configured() && localStorage.getItem('aw_cksync')) syncNow(); },
  };
})();
