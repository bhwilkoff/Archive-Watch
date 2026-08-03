/* Archive Watch — smart-TV layer (Samsung Tizen · LG webOS · VIDAA · aggregators).
 *
 * Binding rules: docs/TV-DESIGN.md §7. Strategy: Decision 047.
 *
 * This is an ADDITIVE layer over the existing vanilla viewer — same watch.js,
 * same watch.css, same service worker, no build step, no framework. It is NOT a
 * fork of the web app (§7.1), and it is deliberately dependency-free: every
 * mature spatial-navigation library (Norigin and friends) is React-based, which
 * this codebase is not.
 *
 * It works by observing the DOM the viewer already produces — cards are real
 * <a> elements, so they are focusable without touching a line of view code.
 * The per-platform differences are ONLY key codes, lifecycle events and
 * packaging (§7.3); no logic below branches on platform beyond that table.
 */
(function () {
  'use strict';

  /* ------------------------------------------------------------------ *
   * Platform detection + the per-platform shim table (§7.3)
   * ------------------------------------------------------------------ */

  const UA = navigator.userAgent || '';
  const PLATFORM =
    /Tizen/i.test(UA) ? 'tizen' :
    /Web0S|webOS/i.test(UA) ? 'webos' :
    /VIDAA/i.test(UA) ? 'vidaa' :
    // ?tv=1 lets the TV surface be developed and screenshotted in a desktop
    // browser. Without it a TV build could only ever be tested on a TV.
    (new URLSearchParams(location.search).get('tv') === '1' ? 'debug' : null);

  if (!PLATFORM) return;   // ordinary phone/desktop web — do nothing at all.

  // Back is the one key every platform spells differently, and getting it wrong
  // is a certification failure on all of them (§1.7).
  const BACK_KEYS = new Set([
    461,    // webOS
    10009,  // Tizen
    27,     // Escape — desktop debug + some aggregator remotes
    8,      // Backspace — VIDAA and several white-label remotes
  ]);

  const KEY = {
    LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40,
    ENTER: 13,
    PLAY: 415, PAUSE: 19, PLAY_PAUSE: 10252, STOP: 413,
    FF: 417, REWIND: 412,
  };

  const SEEK_STEP = 10;   // seconds per FF/REW press — the TV convention.

  /* ------------------------------------------------------------------ *
   * Focus engine (§3, §7.2)
   * ------------------------------------------------------------------ */

  const FOCUSABLE = [
    'a[href]',
    'button:not([disabled])',
    'input:not([disabled])',
    'select:not([disabled])',
    '[tabindex]:not([tabindex="-1"])',
  ].join(',');

  /** Visible, laid-out, and inside a view that is not `hidden`. A hidden view's
   *  cards stay in the DOM, so without this the D-pad would walk into the
   *  previous screen. */
  function isReachable(el) {
    if (el.closest('[hidden]')) return false;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return false;
    const style = getComputedStyle(el);
    return style.visibility !== 'hidden' && style.display !== 'none';
  }

  function candidates() {
    return Array.prototype.filter.call(
      document.querySelectorAll(FOCUSABLE), isReachable);
  }

  function centreOf(r) {
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }

  /**
   * Pick the best element in `dir` from `fromRect`.
   *
   * Scoring = distance along the axis of travel + a weighted penalty for
   * misalignment across it. The weight is what makes a grid feel like a grid:
   * pressing Down from a card should land on the card *below* it, not on a
   * nearer one three columns over (§3.5 — directional intent is preserved).
   */
  function bestInDirection(fromRect, dir, pool) {
    const from = centreOf(fromRect);
    const MISALIGN_WEIGHT = 3;
    let best = null;
    let bestScore = Infinity;

    for (const el of pool) {
      const r = el.getBoundingClientRect();
      const to = centreOf(r);

      // Must lie genuinely in the direction of travel. Compare EDGES, not
      // centres: a tall neighbour whose centre is behind us can still be the
      // correct target.
      let along, across;
      if (dir === 'right') {
        if (r.left < fromRect.right - 1) continue;
        along = r.left - fromRect.right; across = Math.abs(to.y - from.y);
      } else if (dir === 'left') {
        if (r.right > fromRect.left + 1) continue;
        along = fromRect.left - r.right; across = Math.abs(to.y - from.y);
      } else if (dir === 'down') {
        if (r.top < fromRect.bottom - 1) continue;
        along = r.top - fromRect.bottom; across = Math.abs(to.x - from.x);
      } else {
        if (r.bottom > fromRect.top + 1) continue;
        along = fromRect.top - r.bottom; across = Math.abs(to.x - from.x);
      }

      const score = Math.max(along, 0) + across * MISALIGN_WEIGHT;
      if (score < bestScore) { bestScore = score; best = el; }
    }
    return best;
  }

  /** §3.3 — a focused element must never sit under the overscan margin or
   *  off-screen; the D-pad has no other way to reveal it. */
  function reveal(el) {
    el.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' });
  }

  function focusEl(el) {
    if (!el) return false;
    el.focus({ preventScroll: true });
    reveal(el);
    return true;
  }

  function move(dir) {
    const pool = candidates();
    if (!pool.length) return false;

    const active = document.activeElement;
    if (!active || active === document.body || !isReachable(active)) {
      return focusEl(pool[0]);
    }
    const next = bestInDirection(active.getBoundingClientRect(), dir, pool);
    // §3.4 — no dead ends. If nothing lies that way we simply stay put, which
    // is a deliberate stop, not a strand: Back always still works.
    return next ? focusEl(next) : false;
  }

  /** §3.1 — something is ALWAYS focused. Called on every view change, and
   *  retried because views render asynchronously after the hash changes. */
  let claimTimer = null;
  function claimFocus() {
    clearTimeout(claimTimer);
    let tries = 0;
    (function attempt() {
      const active = document.activeElement;
      if (active && active !== document.body && isReachable(active)) return;
      const pool = candidates();
      if (pool.length) { focusEl(pool[0]); return; }
      if (++tries < 20) claimTimer = setTimeout(attempt, 100);
    })();
  }

  /* ------------------------------------------------------------------ *
   * Playback keys (§5.2)
   * ------------------------------------------------------------------ */

  function activeVideo() {
    const v = document.querySelector('video');
    return v && isReachable(v) ? v : null;
  }

  function togglePlay(v) { if (v.paused) v.play(); else v.pause(); }
  function seekBy(v, delta) {
    const end = isFinite(v.duration) ? v.duration : Infinity;
    v.currentTime = Math.min(Math.max(v.currentTime + delta, 0), end);
  }

  /* ------------------------------------------------------------------ *
   * Key handling
   * ------------------------------------------------------------------ */

  function goBack() {
    // §1.7 — Back navigates back, and exits from the root. Never swallowed.
    if ((location.hash || '#/').replace(/^#\/?/, '') === '') {
      exitApp();
    } else {
      history.back();
    }
  }

  function exitApp() {
    if (PLATFORM === 'tizen' && window.tizen && tizen.application) {
      try { tizen.application.getCurrentApplication().exit(); return; } catch (e) { /* fall through */ }
    }
    if (PLATFORM === 'webos' && window.webOS && webOS.platformBack) {
      try { webOS.platformBack(); return; } catch (e) { /* fall through */ }
    }
    window.close();
  }

  function onKeyDown(ev) {
    const code = ev.keyCode;

    if (BACK_KEYS.has(code)) { ev.preventDefault(); goBack(); return; }

    const video = activeVideo();
    if (video) {
      switch (code) {
        case KEY.PLAY_PAUSE: case KEY.ENTER:
          ev.preventDefault(); togglePlay(video); return;
        case KEY.PLAY: ev.preventDefault(); video.play(); return;
        case KEY.PAUSE: ev.preventDefault(); video.pause(); return;
        case KEY.STOP: ev.preventDefault(); video.pause(); goBack(); return;
        case KEY.REWIND: case KEY.LEFT:
          ev.preventDefault(); seekBy(video, -SEEK_STEP); return;
        case KEY.FF: case KEY.RIGHT:
          ev.preventDefault(); seekBy(video, SEEK_STEP); return;
        default: break;
      }
    }

    switch (code) {
      case KEY.LEFT:  ev.preventDefault(); move('left');  break;
      case KEY.UP:    ev.preventDefault(); move('up');    break;
      case KEY.RIGHT: ev.preventDefault(); move('right'); break;
      case KEY.DOWN:  ev.preventDefault(); move('down');  break;
      case KEY.ENTER: {
        // Anchors activate natively on Enter; buttons need the nudge.
        const a = document.activeElement;
        if (a && a.tagName === 'BUTTON') { ev.preventDefault(); a.click(); }
        break;
      }
      default: break;
    }
  }

  /* ------------------------------------------------------------------ *
   * Lifecycle (§7.3) — pause on suspend, resume focus on return
   * ------------------------------------------------------------------ */

  function onHidden() {
    const v = document.querySelector('video');
    if (v && !v.paused) v.pause();
  }

  function installLifecycle() {
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) onHidden(); else claimFocus();
    });

    if (PLATFORM === 'webos') {
      // webOS relaunch delivers a fresh launch params payload rather than a
      // new document — treat it as a re-entry and re-claim focus.
      document.addEventListener('webOSRelaunch', claimFocus);
      document.addEventListener('webOSLaunch', claimFocus);
    }
    if (PLATFORM === 'tizen') {
      // The hardware Back/Exit key arrives as its own event on Tizen in
      // addition to keydown, depending on firmware.
      document.addEventListener('tizenhwkey', function (e) {
        if (e.keyName === 'back') { e.preventDefault(); goBack(); }
      });
    }
  }

  /** Tizen only delivers the media/colour keys after they are registered. */
  function registerTizenKeys() {
    if (PLATFORM !== 'tizen' || !window.tizen || !tizen.tvinputdevice) return;
    ['MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop',
     'MediaRewind', 'MediaFastForward'].forEach(function (name) {
      try { tizen.tvinputdevice.registerKey(name); } catch (e) { /* not all models expose all keys */ }
    });
  }

  /* ------------------------------------------------------------------ *
   * Magic Remote coexistence (§7.4) — pointer and D-pad share one focus state
   * ------------------------------------------------------------------ */

  function installPointerBridge() {
    // LG's pointer mode is not optional to support. Hovering moves focus so
    // that when the user puts the pointer down, the D-pad continues from where
    // they were looking — two input models, ONE focus state.
    document.addEventListener('mouseover', function (ev) {
      const el = ev.target && ev.target.closest ? ev.target.closest(FOCUSABLE) : null;
      if (el && isReachable(el) && el !== document.activeElement) {
        el.focus({ preventScroll: true });
      }
    });
  }

  /* ------------------------------------------------------------------ *
   * Boot
   * ------------------------------------------------------------------ */

  function boot() {
    // Activates the TV breakpoint in tv.css. Additive: the mobile-first
    // stylesheet is untouched (§7.5).
    document.documentElement.classList.add('tv', 'tv-' + PLATFORM);

    registerTizenKeys();
    installLifecycle();
    installPointerBridge();
    window.addEventListener('keydown', onKeyDown, true);

    // Re-claim focus whenever the viewer swaps views. Hash routing means we do
    // not need to hook showView() at all — no view code changes (§7.1).
    window.addEventListener('hashchange', claimFocus);

    // The first render is asynchronous (catalog index fetch), so watch for the
    // DOM filling in rather than guessing a delay.
    const mo = new MutationObserver(function () {
      const active = document.activeElement;
      if (!active || active === document.body) claimFocus();
    });
    mo.observe(document.body, { childList: true, subtree: true });

    claimFocus();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
