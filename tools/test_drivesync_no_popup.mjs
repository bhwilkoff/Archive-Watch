#!/usr/bin/env node
// A Google access token is only ever requested behind a click. Google's
// token client opens a WINDOW on every requestAccessToken(); before
// 2026-09-15 drivesync asked on page load, on tab-focus and every 90 s, so a
// signed-in viewer opening a shared playlist got a login popup unbidden and
// again each time they dismissed it. Runs js/drivesync.js in a shim and
// counts the requests: init() with the signed-in flag must make NONE; the
// Reconnect click must make exactly one. Checked to FAIL on the old file.
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../js/drivesync.js', import.meta.url), 'utf8');

let requests = 0;
const store = new Map([['aw_gsync', '1']]);
const el = () => {
  const e = { children: [], hidden: false, innerHTML: '', textContent: '', className: '', type: '',
    onclick: null, setAttribute() {}, append(...c) { this.children.push(...c); } };
  return e;
};
const window = {
  AW_GOOGLE_CLIENT_ID: 'test-client',
  google: { accounts: { oauth2: { initTokenClient: () => ({ requestAccessToken() { requests++; } }) } } },
  addEventListener() {}, dispatchEvent() {},
};
const document = { createElement: el, addEventListener() {}, hidden: false, head: { appendChild() {} } };
const localStorage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
const timers = [];
const setInterval = (fn) => { timers.push(fn); return 1; };

new Function('window', 'document', 'localStorage', 'setInterval', 'CustomEvent', 'google', src)(
  window, document, localStorage, setInterval, class {}, window.google);
const S = window.AWDriveSync;
const host = el();
S.init({}, host);                       // page load, signed-in flag set
await new Promise(r => setTimeout(r, 20));
for (const t of timers) t();            // the 90 s timer fires
await new Promise(r => setTimeout(r, 20));
const afterLoad = requests;

// The bar must offer a Reconnect control, and clicking it is the ONE request.
const walk = (n, out = []) => { for (const c of n.children || []) { out.push(c); walk(c, out); } return out; };
const reconnect = walk(host).find(c => c.textContent === 'Reconnect Google');
if (reconnect) reconnect.onclick();
await new Promise(r => setTimeout(r, 20));
const afterClick = requests;

let fails = 0;
const check = (ok, msg) => { console.log((ok ? '  ok   ' : '  FAIL ') + msg); if (!ok) fails++; };
check(afterLoad === 0, `no token request on load / focus / timer (got ${afterLoad})`);
check(!!reconnect, 'a Reconnect Google control is rendered while paused');
check(afterClick === 1, `exactly one request after the click (got ${afterClick})`);
console.log(`drivesync no-popup: ${3 - fails}/3 pass`);
process.exit(fails ? 1 : 0);
