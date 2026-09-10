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
    // STAY INSIDE THE SCROLLING AREA FIRST. `body` is a flex column with
    // `overflow:hidden`, so <main> scrolls and the footer is a SIBLING pinned
    // below it, permanently on screen. Purely geometric, the footer is
    // therefore the nearest thing below EVERY row on the page — so Down from
    // the category tiles jumped straight to "About & attribution" and the page
    // never scrolled. That is the owner's report, "the screen doesn't follow
    // the rectangle", and it is not a Home bug: it is what a pinned element
    // does to a spatial engine on any surface.
    //
    // A move therefore prefers a target in the same scroll container, and only
    // leaves it when that direction is genuinely exhausted — which is when a
    // viewer means to leave. Measured with tools/tv_glass.mjs at 1920x1080.
    const box = active.getBoundingClientRect();
    const home = scrollParent(active);
    if (home) {
      const inside = pool.filter(function (el) { return scrollParent(el) === home; });
      const near = inside.length && bestInDirection(box, dir, inside);
      if (near) return focusEl(near);
    }
    const next = bestInDirection(box, dir, pool);
    // §3.4 — no dead ends. If nothing lies that way we simply stay put, which
    // is a deliberate stop, not a strand: Back always still works.
    return next ? focusEl(next) : false;
  }

  /** The nearest ancestor that actually scrolls, or null. */
  function scrollParent(el) {
    for (var n = el.parentElement; n && n !== document.body; n = n.parentElement) {
      var oy = getComputedStyle(n).overflowY;
      if ((oy === 'auto' || oy === 'scroll') && n.scrollHeight > n.clientHeight) {
        return n;
      }
    }
    return null;
  }

  /**
   * Chrome that is NOT a destination. Landing initial focus here is technically
   * "something is focused" while being useless to a viewer — the brand logo and
   * the footer links are not what anyone came for.
   */
  const CHROME_SEL = '.brand, .sitefoot a, footer a, .install-prompt *';

  function isChrome(el) {
    return typeof el.closest === 'function' && el.closest(CHROME_SEL) != null;
  }

  /**
   * §3.1 — something is ALWAYS focused. Called on every view change, and
   * retried because views render asynchronously after the hash changes.
   *
   * Prefers real CONTENT over page chrome: focus landing on the logo was the
   * first thing a real browser showed (the shim has no notion of "useful"),
   * and it reads as broken because the first Right/Down goes somewhere
   * unrelated to what the viewer is looking at.
   */
  let claimTimer = null;
  /* §1.7 — BACK RETURNS TO THE PLACE, not the top of the page.
   *
   * Without this, coming back from a film focused the first non-chrome
   * candidate, which on Home is the nav rail: browse deep into a shelf, open a
   * title, press Back, and you were at scroll 0 with focus on "Home" — on a
   * page with several hundred tiles. Roku fixed the same complaint (F8).
   *
   * The remembered key is the element's href where it has one, because that
   * survives the view being re-rendered from scratch on every route change,
   * which is what a hash router does. Text is the fallback for buttons. An
   * index would not survive a shelf whose contents rotate per visit. */
  const lastFocus = Object.create(null);

  function routeKey() {
    return (location.hash || '#/').split('?')[0];
  }

  function elKey(el) {
    return el.getAttribute('href')
        || el.tagName + ':' + (el.textContent || '').trim().slice(0, 40);
  }

  document.addEventListener('focusin', function (ev) {
    const el = ev.target;
    if (el && el !== document.body && typeof el.getAttribute === 'function'
        && isReachable(el) && !isChrome(el)) {
      lastFocus[routeKey()] = elKey(el);
    }
  }, true);

  function claimFocus() {
    clearTimeout(claimTimer);
    let tries = 0;
    (function attempt() {
      const active = document.activeElement;
      if (active && active !== document.body && isReachable(active)) return;
      const pool = candidates();
      if (pool.length) {
        const want = lastFocus[routeKey()];
        if (want) {
          const back = pool.find(function (el) { return elKey(el) === want; });
          if (back) { focusEl(back); return; }
        }
        focusEl(pool.find(function (el) { return !isChrome(el); }) || pool[0]);
        return;
      }
      if (++tries < 20) claimTimer = setTimeout(attempt, 100);
    })();
  }

  /* ------------------------------------------------------------------ *
   * ON-SCREEN PLAYBACK DIAGNOSTICS (§5.4)
   *
   * "Videos do not play except for a few seconds" — reported on a retail
   * Samsung, where there is NO way to see why. `sdb shell` is closed on retail
   * hardware: no console, no dlog, no screenshot, and the Web Inspector needs a
   * developer (UD) unit. Playback is fine in Chrome, so the fault is the
   * platform's and cannot be reproduced anywhere this code can be watched.
   *
   * When the only oracle is the television, the app has to become the
   * instrument — the same move tvOS made with FunctionalAudit when the Apple TV
   * could not be read either. This prints the media pipeline's own events on
   * the screen, so a person standing in front of the TV can read what it did.
   *
   * TOGGLE: Up Up Down Down on the remote, within five seconds. Chosen because
   * a viewer cannot enter it by accident while browsing (it needs a reversal on
   * the same axis), it needs no extra keys registered, and it is enterable on
   * every remote including the minimal Samsung ones.
   *
   * What it records is chosen for THIS bug: every media event, plus readyState,
   * networkState, the buffered end and the error code at the moment it stops.
   * A film that dies at ~10s with networkState NETWORK_NO_SOURCE is a different
   * bug from one that dies with buffered stuck and readyState dropping, and the
   * screen has to be able to tell them apart.
   * ------------------------------------------------------------------ */

  var diagOn = false, diagEl = null, diagLines = [], diagSeq = [], diagSeqAt = 0;
  var DIAG_CODE = [38, 38, 40, 40];          // Up Up Down Down

  var NET = ['EMPTY', 'IDLE', 'LOADING', 'NO_SOURCE'];
  var RDY = ['NOTHING', 'METADATA', 'CURRENT', 'FUTURE', 'ENOUGH'];

  function diagNote(line) {
    if (!diagOn) return;
    var t = new Date().toISOString().slice(11, 23);
    diagLines.push(t + '  ' + line);
    if (diagLines.length > 18) diagLines.shift();
    if (diagEl) diagEl.textContent = diagLines.join('\n');
  }

  function diagSnapshot(v) {
    if (!v) return 'no video element';
    var b = '-';
    try { b = v.buffered.length ? v.buffered.end(v.buffered.length - 1).toFixed(1) : '0'; }
    catch (e) { b = '?'; }
    return 't=' + v.currentTime.toFixed(1) +
           ' buf=' + b +
           ' rdy=' + (RDY[v.readyState] || v.readyState) +
           ' net=' + (NET[v.networkState] || v.networkState) +
           (v.error ? ' ERR=' + v.error.code + ' ' + (v.error.message || '') : '');
  }

  function diagAttach(v) {
    if (!v || v.dataset.tvDiag) return;
    v.dataset.tvDiag = '1';
    ['loadstart', 'loadedmetadata', 'canplay', 'canplaythrough', 'play', 'playing',
     'waiting', 'stalled', 'suspend', 'abort', 'emptied', 'pause', 'ended', 'error']
      .forEach(function (ev) {
        v.addEventListener(ev, function () { diagNote(ev + '  ' + diagSnapshot(v)); });
      });
    // A heartbeat, because the interesting failure is SILENCE: a film that
    // stops without firing anything is the thing an event log alone would miss.
    setInterval(function () {
      if (diagOn && !v.paused) diagNote('tick  ' + diagSnapshot(v));
    }, 5000);
    diagNote('attached  src=' + String(v.currentSrc || v.src || '').slice(-64));
  }

  function diagToggle() {
    diagOn = !diagOn;
    if (diagOn) {
      if (!diagEl) {
        diagEl = document.createElement('pre');
        diagEl.className = 'tv-diag';
      }
      // AN OPEN <dialog> IS IN THE TOP LAYER, and nothing outside it can be
      // painted above — z-index does not apply across that boundary. The
      // player IS a dialog, so an overlay appended to <body> is created,
      // updated, and invisible behind the film. Put it inside whatever is on
      // top. Found on the glass; it would have shipped as a diagnostic that
      // silently showed nothing, which is worse than no diagnostic at all.
      // The STAGE, not the dialog root and not <body>. Evidence, not theory:
      // .tv-transport is appended to video.parentElement and renders correctly
      // inside the open player, so that element is provably paintable. An open
      // <dialog> is in the TOP LAYER and nothing outside it can be drawn above,
      // so <body> is invisible while a film is up — which is exactly when this
      // is needed.
      var v = document.querySelector('video');
      var host = (v && v.parentElement) || document.body;
      if (diagEl.parentElement !== host) host.appendChild(diagEl);
      diagEl.hidden = false;
      diagLines = ['diagnostics ON — Up Up Down Down again to hide',
                   'platform=' + PLATFORM + '  ua=' + navigator.userAgent.slice(0, 60)];
      diagEl.textContent = diagLines.join('\n');
      var v = document.querySelector('video');
      if (v) { diagAttach(v); diagNote('now  ' + diagSnapshot(v)); }
    } else if (diagEl) {
      diagEl.hidden = true;
    }
  }

  function diagKey(code) {
    var now = Date.now();
    if (now - diagSeqAt > 5000) diagSeq = [];
    diagSeqAt = now;
    diagSeq.push(code);
    if (diagSeq.length > DIAG_CODE.length) diagSeq.shift();
    if (diagSeq.length === DIAG_CODE.length &&
        diagSeq.every(function (c, i) { return c === DIAG_CODE[i]; })) {
      diagSeq = [];
      diagToggle();
    }
  }

  /* ------------------------------------------------------------------ *
   * TV TRANSPORT (§5.3)
   *
   * `<video controls>` renders the BROWSER's control bar — pause, 0:00,
   * volume, fullscreen, a kebab menu. On a desktop that is correct and free.
   * On a television it is the owner's "controls that only work for a desktop
   * web browser", and that is literally what they are: Chrome's widgets, laid
   * out for a pointer, at pointer sizes, in a strip a D-pad cannot enter.
   *
   * So on TV the attribute comes OFF and we draw our own, because the KEYS are
   * already ours: OK toggles, Left/Right seek, Back closes (see onKeyDown).
   * A TV transport is a READOUT, not a set of targets — there is nothing to
   * click, so nothing needs to be focusable, and it must never take a press
   * away from the film.
   *
   * It shows on any key and hides itself after a few seconds of stillness,
   * which is the convention every ten-foot player uses.
   * ------------------------------------------------------------------ */

  var transportEl = null, transportTimer = null;

  function fmtTime(sec) {
    if (!isFinite(sec) || sec < 0) sec = 0;
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60),
        s = Math.floor(sec % 60);
    var mm = (h && m < 10 ? '0' : '') + m;
    return (h ? h + ':' : '') + mm + ':' + (s < 10 ? '0' : '') + s;
  }

  function ensureTransport(video) {
    var stage = video.parentElement;
    if (!stage) return null;
    if (transportEl && stage.contains(transportEl)) return transportEl;
    transportEl = document.createElement('div');
    transportEl.className = 'tv-transport';
    transportEl.setAttribute('aria-hidden', 'true');   // a readout, not a control
    transportEl.innerHTML =
      '<div class="tv-tp-row">' +
        '<span class="tv-tp-state"></span>' +
        '<span class="tv-tp-now"></span>' +
        '<div class="tv-tp-bar"><i></i></div>' +
        '<span class="tv-tp-dur"></span>' +
      '</div>' +
      '<p class="tv-tp-hint">OK play/pause · ◀ ▶ 10s · Back to exit</p>';
    stage.appendChild(transportEl);
    return transportEl;
  }

  function paintTransport(video) {
    var el = ensureTransport(video);
    if (!el) return;
    var d = video.duration, t = video.currentTime;
    el.querySelector('.tv-tp-state').textContent = video.paused ? '❚❚' : '▶';
    el.querySelector('.tv-tp-now').textContent = fmtTime(t);
    el.querySelector('.tv-tp-dur').textContent = isFinite(d) ? fmtTime(d) : '';
    el.querySelector('.tv-tp-bar i').style.width =
      (isFinite(d) && d > 0 ? Math.min(100, (t / d) * 100) : 0) + '%';
  }

  function showTransport() {
    var v = activeVideo();
    if (!v) return;
    var el = ensureTransport(v);
    if (!el) return;
    paintTransport(v);
    el.classList.add('on');
    clearTimeout(transportTimer);
    // Paused stays visible: a still frame with no readout looks like a crash.
    if (!v.paused) {
      transportTimer = setTimeout(function () { el.classList.remove('on'); }, 4000);
    }
  }

  /** Strip the browser's controls and take over. Runs whenever a video shows
   *  up, because the player is opened by the app, not by us. */
  function adoptVideo(video) {
    diagAttach(video);          // record from the first frame, not from the toggle
    if (video.dataset.tvAdopted) return;
    video.dataset.tvAdopted = '1';
    video.removeAttribute('controls');
    video.addEventListener('timeupdate', function () {
      if (transportEl && transportEl.classList.contains('on')) paintTransport(video);
    });
    ['play', 'pause', 'seeked', 'loadedmetadata'].forEach(function (ev) {
      video.addEventListener(ev, showTransport);
    });
    showTransport();
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
    // §1.7 — Back is layered, and the layers matter.
    //
    // An OPEN OVERLAY IS THE TOP LAYER. Backing out of the player used to run
    // history.back(), which changed the hash to home while leaving the <dialog>
    // open and the video PLAYING — a film over the home page with no way out,
    // and an automatic fail on LG's and Samsung's Back-behaviour tests.
    // Verified in Chrome; close the overlay and stop playback first.
    const openDialog = document.querySelector('dialog[open]');
    if (openDialog) {
      const vid = openDialog.querySelector('video');
      if (vid) { try { vid.pause(); } catch (e) { /* ignore */ } }
      if (typeof openDialog.close === 'function') openDialog.close();
      else openDialog.removeAttribute('open');
      claimFocus();
      return;
    }

    // Otherwise navigate back, and exit from the root. Never swallowed.
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
    diagKey(code);        // the toggle must see EVERY press, including ones
                          // the player or the focus engine goes on to consume

    if (BACK_KEYS.has(code)) { ev.preventDefault(); goBack(); return; }

    const video = activeVideo();
    if (video) {
      adoptVideo(video);          // the player is opened by the app, not by us
      showTransport();            // any press brings the readout back
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

    // A FOCUSED <select> OWNS UP/DOWN. Without this the handler ran spatial
    // navigation on every arrow regardless of what had focus, so the arrows
    // moved focus off the control and its value could never change: Browse's
    // decade, keyword, studio and sort filters were reachable, looked fine,
    // and were dead on every TV. Left/Right still navigate, so the viewer is
    // never trapped inside a control they cannot leave — which is the failure
    // mode a naive "exempt form controls" fix introduces instead.
    const focused = document.activeElement;
    if (focused && focused.tagName === 'SELECT' && !focused.disabled
        && (code === KEY.UP || code === KEY.DOWN)) {
      return;                       // let the browser change the value
    }

    switch (code) {
      case KEY.LEFT:  ev.preventDefault(); move('left');  break;
      case KEY.UP:    ev.preventDefault(); move('up');    break;
      case KEY.RIGHT: ev.preventDefault(); move('right'); break;
      case KEY.DOWN:  ev.preventDefault(); move('down');  break;
      case KEY.ENTER: {
        // Activate EXPLICITLY rather than relying on native behaviour.
        // Chrome does activate a focused <a> on a real Enter (verified), but TV
        // browsers are inconsistent about it, and "it works in Chrome" is not
        // the bar — the app has to work on the panel. preventDefault() first so
        // a browser that WOULD have activated natively cannot double-fire.
        const a = document.activeElement;
        if (a && a !== document.body && typeof a.click === 'function') {
          ev.preventDefault();
          a.click();
        }
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
      const v = activeVideo();
      if (v) adoptVideo(v);       // strip the browser's controls the moment it exists
      const active = document.activeElement;
      if (!active || active === document.body) claimFocus();
    });
    // ATTRIBUTES TOO. Opening a <dialog> sets `open` — an attribute mutation,
    // not a childList one — and the <video> is static markup that has existed
    // since first paint. Without this the browser's own control bar showed
    // until the viewer happened to press something.
    mo.observe(document.body, { childList: true, subtree: true,
                                attributes: true, attributeFilter: ['open'] });

    claimFocus();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
