/* Watch Together rooms on the WEB — SHAREPLAY §11.
 *
 * WHY THE WEB MATTERS HERE MORE THAN ANYWHERE. §11.6's whole premise is that a
 * room link "has to open for somebody with no app at all", the same promise
 * playlist sharing makes. Without this file that promise was false: the link
 * landed on a page that did nothing. A browser cannot BROADCAST (it cannot
 * speak RTMP) and it can certainly WATCH, which is the only half a joiner
 * needs.
 *
 * The rule and the arithmetic are deliberately the same as the apps', and the
 * input table in tools/test_together_web.mjs is the one §8.28 (Swift), §8.29
 * (the Worker) and StudioRoomTest (Kotlin) all assert. Four implementations of
 * one rule is four chances to disagree about what a heard "oh" means, and the
 * only thing keeping them honest is that table.
 */
(function (global) {
  'use strict';

  const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  const CODE_LENGTH = 4;

  /** Crockford Base32, mapping the glyphs a listener actually mistypes. */
  function normalizeCode(typed) {
    if (typeof typed !== 'string') return null;
    let out = '';
    for (const ch of typed.toUpperCase()) {
      if (ch === ' ' || ch === '-' || ch === '_') continue;
      if (ch === 'I' || ch === 'L') { out += '1'; continue; }
      if (ch === 'O') { out += '0'; continue; }
      if (ch === 'U') return null;
      if (!ALPHABET.includes(ch)) return null;
      out += ch;
    }
    return out.length === CODE_LENGTH ? out : null;
  }

  /** `#/together/CODE-filmID` — the film id may itself contain dashes, which
   *  archive ids routinely do, so split on the FIRST separator only. */
  function parseRoute(seg) {
    if (!seg) return null;
    const i = seg.indexOf('-');
    if (i < 0) return null;
    const code = normalizeCode(seg.slice(0, i));
    const filmID = seg.slice(i + 1);
    return code && filmID ? { code, filmID } : null;
  }

  // ---- the arithmetic, matching StudioSync.swift (§8.27)

  const TOLERANCE = 0.150;
  const SEEK_THRESHOLD = 2.0;
  const NUDGE_FAST = 1.03;
  const NUDGE_SLOW = 0.97;
  const POLL_FAST = 2.0;
  const POLL_IDLE = 10.0;
  const IDLE_AFTER = 60.0;

  /** A PAUSED film does not advance. An elapsed-time formula that forgets to
   *  ask is the single easiest mistake here. */
  function expectedPosition(state, serverNow) {
    if (state.paused) return state.position;
    return state.position + Math.max(0, serverNow - state.atServerTime) * state.rate;
  }

  /** Cristian's algorithm. The error bound is RTT/2, which is WHY the fastest
   *  exchange is the one to keep — averaging mixes a good measurement with bad
   *  ones and discards the bound. */
  function sampleOffset(sentAt, serverTime, receivedAt) {
    return {
      offset: serverTime - (sentAt + receivedAt) / 2,
      rtt: Math.max(0, receivedAt - sentAt),
      error: Math.max(0, receivedAt - sentAt) / 2,
    };
  }

  /** What the PLAYER should be made to do — applied silently, never asked of
   *  a person (§11.2a). */
  function correction(localPosition, localPaused, state, serverNow) {
    if (state.paused !== localPaused) return { kind: 'setPaused', paused: state.paused };
    if (state.paused) return { kind: 'none' };
    const expected = expectedPosition(state, serverNow);
    const drift = expected - localPosition;       // positive = behind
    const magnitude = Math.abs(drift);
    if (magnitude <= TOLERANCE) return { kind: 'none' };
    if (magnitude >= SEEK_THRESHOLD) return { kind: 'seek', to: expected };
    return { kind: 'nudge', rate: drift > 0 ? NUDGE_FAST : NUDGE_SLOW };
  }

  function pollInterval(secondsSinceChange) {
    return secondsSinceChange >= IDLE_AFTER ? POLL_IDLE : POLL_FAST;
  }

  // ---- the client

  /* THE WORKER IS NOT ON archivewatch.org — that host is GitHub Pages, and a
     same-origin call would reach it and 404. The Worker answers at its own
     workers.dev origin, which is where the privacy counter has always posted
     (AW_BEACON_ORIGIN in watch.js). Cross-origin, so together.js sets CORS. */
  const DEFAULT_BASE = 'https://archivewatch-pulse.benwilkoff.workers.dev';

  function Client(base) {
    this.base = base === undefined || base === null ? DEFAULT_BASE : base;
    this.clock = null;          // the FASTEST sample, never the newest
    this.code = null;
    this.state = null;
    this.generationChangedAt = 0;
  }

  Client.prototype.serverNow = function () {
    return Date.now() / 1000 + (this.clock ? this.clock.offset : 0);
  };

  Client.prototype.poll = async function () {
    if (!this.code) throw new Error('no room');
    const sentAt = Date.now() / 1000;
    const r = await fetch(`${this.base}/together/${this.code}`, { cache: 'no-store' });
    const receivedAt = Date.now() / 1000;
    if (r.status === 404 || r.status === 410) throw new Error('room ended');
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const o = await r.json();

    const s = sampleOffset(sentAt, o.serverTime, receivedAt);
    // A slow exchange is not merely imprecise; its bound is RTT/2, so
    // replacing a fast sample with a slow one makes the clock WORSE while
    // looking like an update.
    if (!this.clock || s.rtt < this.clock.rtt) this.clock = s;

    const prev = this.state ? this.state.generation : null;
    this.state = {
      filmID: o.filmID, position: o.position, atServerTime: o.atServerTime,
      rate: o.rate || 1, paused: !!o.paused, generation: o.generation || 1,
    };
    if (this.state.generation !== prev) this.generationChangedAt = Date.now() / 1000;
    return this.state;
  };

  /** "I'm here" — an anonymous token, made fresh per join, tied to nothing;
   *  only a COUNT is ever read back (owner, 2026-09-23). Best-effort. */
  Client.prototype.sayHere = async function (token) {
    if (!this.code) return;
    try {
      await fetch(`${this.base}/together/${this.code}/here`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ token }),
      });
    } catch (e) { /* a missed ping only makes the count lag */ }
  };

  Client.prototype.nextPollDelay = function () {
    const quiet = this.generationChangedAt
      ? Date.now() / 1000 - this.generationChangedAt : 0;
    return pollInterval(quiet);
  };

  /** Drive a <video> from a room. Silent: nobody is ever asked to pause. */
  function follow(video, client, onEnded) {
    let stopped = false;
    let hostRate = 1;

    async function tick() {
      if (stopped) return;
      try {
        const state = await client.poll();
        hostRate = state.rate || 1;
        apply(correction(video.currentTime, video.paused, state, client.serverNow()));
      } catch (e) {
        if (String(e.message).includes('ended')) { stopped = true; onEnded && onEnded(); return; }
        // A poll that failed is a poll, not a reason to stop a film.
      }
      setTimeout(tick, client.nextPollDelay() * 1000);
    }

    function apply(c) {
      switch (c.kind) {
        case 'none':
          // Back to the HOST's rate, not to 1: a nudge left in place plays
          // the rest of the film 3% fast.
          if (!video.paused && video.playbackRate !== hostRate) video.playbackRate = hostRate;
          break;
        case 'nudge': video.playbackRate = hostRate * c.rate; break;
        case 'seek': video.currentTime = c.to; break;
        case 'setPaused':
          if (c.paused) video.pause();
          else { video.playbackRate = hostRate; video.play().catch(() => {}); }
          break;
      }
    }

    // Say "I'm here" every 30 s, so the host sees friends arrive.
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    const token = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
    const here = () => { if (!stopped) client.sayHere(token); };
    here();
    const hereTimer = setInterval(here, 30000);

    tick();
    return { stop() { stopped = true; clearInterval(hereTimer); video.playbackRate = 1; } };
  }

  const API = {
    ALPHABET, CODE_LENGTH, normalizeCode, parseRoute,
    expectedPosition, sampleOffset, correction, pollInterval,
    TOLERANCE, SEEK_THRESHOLD, NUDGE_FAST, NUDGE_SLOW, POLL_FAST, POLL_IDLE, IDLE_AFTER,
    Client, follow, DEFAULT_BASE,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else global.Together = API;
})(typeof globalThis !== 'undefined' ? globalThis : this);
