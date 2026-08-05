/* Archive Watch — web-TV acceptance suite (run IN a browser).
 *
 * The Node DOM shim (tools/test_tv_focus.mjs) proves the focus ALGORITHM.
 * It cannot prove the things that only exist in a real engine: computed CSS,
 * layout geometry, <dialog> semantics, real media elements. Every bug this
 * file guards against was found by running it in Chrome, not by reasoning.
 *
 * Usage — from the page console or an automation harness, with the site served
 * by tools/devserve.py and loaded with ?tv=1 :
 *
 *     const src = await fetch('/tools/tv_browser_tests.js').then(r => r.text());
 *     await (0, eval)(src);          // returns a results object
 *
 * ⚠️ Load the page with a changed QUERY string between edits, never just a new
 * hash: a hash-only navigation does NOT re-fetch the document, so a hash-router
 * app keeps running the OLD JS while you believe you are testing the fix.
 */
(async function () {
  'use strict';

  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const results = [];
  let pass = 0, fail = 0;

  function check(name, ok, detail) {
    results.push({ name, ok: !!ok, detail });
    ok ? pass++ : fail++;
  }

  function press(keyCode, target) {
    (target || window).dispatchEvent(new KeyboardEvent('keydown', {
      keyCode, which: keyCode, bubbles: true, cancelable: true,
    }));
  }

  const who = () => {
    const a = document.activeElement;
    if (!a || a === document.body) return 'BODY';
    return (a.className || a.tagName) + '::' +
      (a.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 28);
  };

  // ---- 1. Activation ------------------------------------------------------
  check('TV layer active', document.documentElement.classList.contains('tv'),
        document.documentElement.className);

  // ---- 2. Type scale + the rem trap (§4.3) --------------------------------
  const htmlPx = parseFloat(getComputedStyle(document.documentElement).fontSize);
  const bodyPx = parseFloat(getComputedStyle(document.body).fontSize);
  check('root font-size untouched (rem basis intact)', htmlPx === 16, htmlPx + 'px');
  check('body >= 24px ten-foot floor', bodyPx >= 24, bodyPx + 'px');

  // ---- 3. Overscan (§4.2) -------------------------------------------------
  const mainPad = parseFloat(getComputedStyle(document.querySelector('main')).paddingLeft);
  check('main has overscan inset', mainPad >= 48, mainPad + 'px');

  // ---- 4. No horizontal overflow -----------------------------------------
  const ovf = document.documentElement.scrollWidth - document.documentElement.clientWidth;
  check('no horizontal overflow', ovf <= 0, ovf + 'px');

  // ---- 5. Initial focus is CONTENT, not chrome (§3.1) ---------------------
  await wait(300);
  const active = document.activeElement;
  check('something is focused', active && active !== document.body, who());
  check('initial focus is not page chrome',
        !(active && active.closest && active.closest('.brand, footer a')), who());

  // ---- 6. Spatial navigation (§3.5) --------------------------------------
  const cards = [...document.querySelectorAll('#home-shelves .card')];
  if (cards.length > 2) {
    cards[0].focus();
    const a0 = who();
    press(39); await wait(150);
    const a1 = who();
    check('Right moves within a rail', a1 !== a0, a0 + ' -> ' + a1);
    press(37); await wait(150);
    check('Left returns within a rail', who() === a0, a1 + ' -> ' + who());
  } else {
    check('cards present for navigation test', false, 'only ' + cards.length);
  }

  // ---- 7. Enter activates deterministically (§5.2) ------------------------
  const filmCard = cards.find((c) => c.href && c.href.includes('#/item/'));
  if (filmCard) {
    location.hash = '';
    await wait(600);
    filmCard.focus();
    const hashBefore = location.hash;
    press(13, filmCard);
    await wait(900);
    check('Enter opens a title', location.hash !== hashBefore && location.hash.includes('/item/'),
          location.hash.slice(0, 40));
  }

  // ---- 8. Player: full-bleed + transport keys + Back layering -------------
  await wait(2500);
  const playBtn = document.getElementById('item-play');
  if (playBtn) {
    playBtn.click();
    // Give the media element time to reach a usable state.
    for (let i = 0; i < 40; i++) {
      const vv = document.querySelector('video');
      if (vv && vv.readyState >= 2) break;
      await wait(500);
    }
    const v = document.querySelector('video');
    const dlg = document.getElementById('player');

    if (v && dlg) {
      const r = v.getBoundingClientRect();
      check('player video fills viewport width',
            Math.abs(r.width - window.innerWidth) <= 2,
            Math.round(r.width) + ' vs ' + window.innerWidth);

      v.currentTime = 100; await wait(600);
      const t0 = v.currentTime;
      press(39); await wait(400);
      check('Right seeks forward ~10s', Math.round(v.currentTime - t0) === 10,
            Math.round(v.currentTime - t0) + 's');
      const t1 = v.currentTime;
      press(37); await wait(400);
      check('Left seeks back ~10s', Math.round(v.currentTime - t1) === -10,
            Math.round(v.currentTime - t1) + 's');

      const p0 = v.paused;
      press(13); await wait(400);
      check('Enter toggles play/pause', v.paused !== p0, p0 + ' -> ' + v.paused);

      press(415); await wait(300);
      check('MediaPlay(415) plays', !v.paused, 'paused=' + v.paused);
      press(19); await wait(300);
      check('MediaPause(19) pauses', v.paused, 'paused=' + v.paused);
      press(10252); await wait(300);
      check('Tizen PlayPause(10252) toggles', !v.paused, 'paused=' + v.paused);

      // THE certification case: Back must close the overlay FIRST, not
      // navigate away leaving a film playing over the home page.
      const hashAtPlay = location.hash;
      press(461); await wait(900);
      check('Back closes the player (not navigate)',
            dlg.open === false && location.hash === hashAtPlay,
            'open=' + dlg.open + ' hash=' + location.hash.slice(0, 26));
      const stillPlaying = document.querySelector('video') &&
                           !document.querySelector('video').paused;
      check('Back stops playback', !stillPlaying, 'playing=' + !!stillPlaying);

      press(461); await wait(900);
      check('Back again leaves the detail page', location.hash !== hashAtPlay,
            location.hash.slice(0, 26));
    } else {
      check('player opened', false, 'no video/dialog');
    }
  }

  /* ---------------------------------------------------------------- *
   * Magic Remote pointer coexistence (TV-DESIGN §7.4, backlog L3)
   *
   * LG ships a pointer remote and supporting it is not optional. The rule is
   * ONE focus state shared by both input models: hovering moves focus, and
   * the D-pad then continues from the hovered element. A pointer that merely
   * highlights, leaving the D-pad to resume somewhere else, is the failure.
   * ---------------------------------------------------------------- */
  {
    location.hash = '';
    await wait(1000);
    const tiles = [...document.querySelectorAll('a[href^="#/item/"]')]
      .filter((e) => e.offsetParent);
    const hover = (el) => el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));

    if (tiles.length >= 5) {
      tiles[0].focus();
      hover(tiles[3]);
      check('hover moves focus', document.activeElement === tiles[3], who());

      // The point of the bridge: the D-pad resumes from the POINTER, not from
      // wherever focus was before the user picked the pointer up.
      press(39); await wait(150);
      check('D-pad continues from the hovered element',
            document.activeElement === tiles[4], who());

      // A pointer drifting over inert chrome must not drag focus with it.
      tiles[0].focus();
      const heading = document.querySelector('h2, .shelf-title, .row-title');
      if (heading) hover(heading);
      check('hovering a non-focusable element keeps focus',
            document.activeElement === tiles[0], who());

      // Hidden views still hold focusables; hovering one would focus an
      // element the viewer cannot see.
      const buried = document.querySelector('section[hidden] a[href]');
      if (buried) hover(buried);
      check('hovering inside a hidden view keeps focus',
            document.activeElement === tiles[0], who());

      // preventScroll: a hover must never yank the page out from under the
      // pointer, or the element under the cursor changes as you hover it.
      const sy = window.scrollY;
      hover(tiles[tiles.length - 1]);
      check('hover does not jump the scroll position', window.scrollY === sy,
            sy + ' -> ' + window.scrollY);
    } else {
      check('tiles present for pointer test', false, 'only ' + tiles.length);
    }
  }

  const summary = { pass, fail, results };
  console.log('[TV TESTS] ' + pass + ' passed, ' + fail + ' failed');
  results.filter((r) => !r.ok).forEach((r) => console.warn('FAIL: ' + r.name + ' — ' + r.detail));
  return summary;
})();
